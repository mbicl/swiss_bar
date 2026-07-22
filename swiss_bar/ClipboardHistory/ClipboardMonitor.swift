//
//  ClipboardMonitor.swift
//  swiss_bar
//

import AppKit
import os

/// Polls `NSPasteboard.general` for changes and records new entries into a `ClipboardHistoryStore`.
/// There's no notification API for pasteboard changes, so this is a `Timer`-driven poll of
/// `changeCount` - the same lifecycle shape as `AccessibilityPermissionManager`'s TCC polling.
@MainActor
final class ClipboardMonitor {
    private static let logger = Logger(subsystem: "com.MBI.swiss-bar", category: "ClipboardMonitor")
    private static let concealedType = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
    private static let pollInterval: TimeInterval = 0.3

    private let store: ClipboardHistoryStore
    private let persistence: ClipboardHistoryPersistence
    private var timer: Timer?
    private var lastChangeCount: Int

    init(store: ClipboardHistoryStore, persistence: ClipboardHistoryPersistence = ClipboardHistoryPersistence()) {
        self.store = store
        self.persistence = persistence
        lastChangeCount = NSPasteboard.general.changeCount
    }

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.poll()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Advances the tracked change count to the pasteboard's current value without inspecting its
    /// contents - called immediately after the app writes to the pasteboard itself (paste-from-history
    /// commit), so that self-write is never re-captured as a new/duplicate history entry.
    func syncAfterSelfWrite() {
        lastChangeCount = NSPasteboard.general.changeCount
    }

    private func poll() {
        let pasteboard = NSPasteboard.general
        let changeCount = pasteboard.changeCount
        guard changeCount != lastChangeCount else { return }
        lastChangeCount = changeCount

        let types = pasteboard.types ?? []
        guard !Self.containsConcealedType(types) else { return }

        guard let item = Self.buildItem(from: pasteboard, types: types, persistence: persistence) else { return }
        guard !Self.isDuplicateOfTop(hash: item.contentHash, topHash: store.topContentHash) else { return }
        store.add(item)
    }

    nonisolated static func containsConcealedType(_ types: [NSPasteboard.PasteboardType]) -> Bool {
        types.contains(concealedType)
    }

    nonisolated static func isDuplicateOfTop(hash: String, topHash: String?) -> Bool {
        hash == topHash
    }

    /// Text takes priority over image - some apps (e.g. Excel) put both a picture and a text
    /// representation on the pasteboard for a copied selection, and the text is what the user means.
    /// Image capture only fires for actual image *data* types (`.tiff`/`.png`), not a bare
    /// `NSImage(pasteboard:)` load, which would also resolve image *files* copied in Finder - a
    /// Finder file copy shouldn't become a bitmap history entry.
    private static func buildItem(
        from pasteboard: NSPasteboard, types: [NSPasteboard.PasteboardType], persistence: ClipboardHistoryPersistence
    ) -> ClipboardItem? {
        if let text = pasteboard.string(forType: .string), !text.isEmpty {
            return ClipboardItem(id: UUID(), date: Date(), contentHash: ClipboardContentHasher.hash(text), kind: .text(text))
        }
        guard types.contains(.tiff) || types.contains(.png) else { return nil }
        guard let image = NSImage(pasteboard: pasteboard),
              let (fileName, pixelSize, pngData) = persistence.writeImageFile(image) else {
            return nil
        }
        return ClipboardItem(
            id: UUID(), date: Date(), contentHash: ClipboardContentHasher.hash(pngData),
            kind: .image(fileName: fileName, pixelSize: pixelSize)
        )
    }
}
