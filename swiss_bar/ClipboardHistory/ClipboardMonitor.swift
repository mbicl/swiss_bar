//
//  ClipboardMonitor.swift
//  swiss_bar
//

import AppKit
import UniformTypeIdentifiers
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
    private let settings: AppSettings
    private var timer: Timer?
    private var lastChangeCount: Int
    /// Logged once per app run, the first time a Finder file-copy image read is blocked (denied
    /// folder permission) - so a silently-vanishing capture is diagnosable instead of invisible.
    private static var didLogBlockedFileRead = false

    init(store: ClipboardHistoryStore, persistence: ClipboardHistoryPersistence = ClipboardHistoryPersistence(), settings: AppSettings) {
        self.store = store
        self.persistence = persistence
        self.settings = settings
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

        guard let item = Self.buildItem(
            from: pasteboard, types: types, persistence: persistence,
            captureFileURLs: settings.clipboardHistoryCaptureFinderImageFiles
        ) else { return }
        guard !Self.isDuplicateOfTop(hash: item.contentHash, topHash: store.topContentHash) else { return }
        store.add(item)
    }

    nonisolated static func containsConcealedType(_ types: [NSPasteboard.PasteboardType]) -> Bool {
        types.contains(concealedType)
    }

    nonisolated static func isDuplicateOfTop(hash: String, topHash: String?) -> Bool {
        hash == topHash
    }

    enum CaptureCategory: Equatable {
        case text, image, fileURL
    }

    /// Categories present on the pasteboard, in the order the source app declared them (deduped).
    /// `NSPasteboard.types` preserves declaration order, and apps declare their primary/richest
    /// representation first - so this order expresses what the copy "primarily is". This is what
    /// lets an image copied from a browser's "Copy Image" (image data + the image's URL as plain
    /// text) capture as an image instead of as a URL text entry, while a plain text copy that
    /// happens to carry other flavors still captures as text.
    nonisolated static func captureCategories(in types: [NSPasteboard.PasteboardType]) -> [CaptureCategory] {
        var seen: [CaptureCategory] = []
        for type in types {
            let category: CaptureCategory?
            if type == .fileURL {
                category = .fileURL
            } else if let ut = UTType(type.rawValue), ut.conforms(to: .plainText) {
                category = .text
            } else if let ut = UTType(type.rawValue), ut.conforms(to: .image) {
                category = .image
            } else {
                category = nil // html/rtf/dyn/legacy flavors don't decide the capture
            }
            if let category, !seen.contains(category) {
                seen.append(category)
            }
        }
        return seen
    }

    nonisolated static func isImageFile(_ url: URL) -> Bool {
        UTType(filenameExtension: url.pathExtension)?.conforms(to: .image) ?? false
    }

    /// Tries each declared category in order, falling through to the next when one can't actually
    /// produce an item (e.g. a file-url category whose file turns out not to be an image).
    private static func buildItem(
        from pasteboard: NSPasteboard, types: [NSPasteboard.PasteboardType], persistence: ClipboardHistoryPersistence,
        captureFileURLs: Bool
    ) -> ClipboardItem? {
        for category in captureCategories(in: types) {
            switch category {
            case .text:
                if let text = pasteboard.string(forType: .string), !text.isEmpty {
                    return ClipboardItem(id: UUID(), date: Date(), contentHash: ClipboardContentHasher.hash(text), kind: .text(text))
                }
            case .image:
                if let image = NSImage(pasteboard: pasteboard),
                   let (fileName, pixelSize, pngData) = persistence.writeImageFile(image) {
                    return ClipboardItem(
                        id: UUID(), date: Date(), contentHash: ClipboardContentHasher.hash(pngData),
                        kind: .image(fileName: fileName, pixelSize: pixelSize)
                    )
                }
            case .fileURL:
                // Reads the file from wherever it lives on disk - opt-in only, since the first
                // read from a TCC-protected folder (Desktop/Documents/Downloads/…) triggers an
                // unexplained folder-access prompt attributed to this app. See
                // AppSettings.clipboardHistoryCaptureFinderImageFiles.
                guard captureFileURLs else { continue }
                guard let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
                      urls.count == 1, isImageFile(urls[0]) else { continue }
                guard let image = NSImage(contentsOf: urls[0]) else {
                    if !didLogBlockedFileRead {
                        didLogBlockedFileRead = true
                        logger.notice("image file copy could not be read (likely a denied folder permission): \(urls[0].path, privacy: .public)")
                    }
                    continue
                }
                if let (fileName, pixelSize, pngData) = persistence.writeImageFile(image) {
                    return ClipboardItem(
                        id: UUID(), date: Date(), contentHash: ClipboardContentHasher.hash(pngData),
                        kind: .image(fileName: fileName, pixelSize: pixelSize)
                    )
                }
            }
        }
        return nil
    }
}
