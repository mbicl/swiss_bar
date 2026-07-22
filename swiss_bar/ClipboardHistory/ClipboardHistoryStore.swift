//
//  ClipboardHistoryStore.swift
//  swiss_bar
//

import Combine
import Foundation

/// In-memory source of truth for clipboard history, backed by `ClipboardHistoryPersistence`.
/// Main-actor confined: mutated from the pasteboard-poll timer and the paste-commit flow (both
/// main-thread in practice), read by SwiftUI.
@MainActor
final class ClipboardHistoryStore: ObservableObject {
    /// Newest first.
    @Published private(set) var items: [ClipboardItem] = []

    private let persistence: ClipboardHistoryPersistence
    private var capacity: Int

    init(persistence: ClipboardHistoryPersistence = ClipboardHistoryPersistence(), capacity: Int) {
        self.persistence = persistence
        self.capacity = capacity
        let loaded = persistence.load()
        let trimmed = Self.trimmed(loaded, toCapacity: capacity)
        items = trimmed
        // The capacity setting may have shrunk while the app was closed - persist the trim so the
        // evicted items' image files get cleaned up rather than lingering on disk forever.
        if trimmed.count != loaded.count {
            persistence.deleteImageFiles(for: Array(loaded.suffix(from: trimmed.count)))
            persistence.save(trimmed)
        }
    }

    var topContentHash: String? { items.first?.contentHash }

    func add(_ item: ClipboardItem) {
        var updated = [item] + items
        let dropped = updated.count > capacity ? Array(updated.suffix(from: capacity)) : []
        updated = Self.trimmed(updated, toCapacity: capacity)
        items = updated
        persistence.deleteImageFiles(for: dropped)
        persistence.save(updated)
    }

    func setCapacity(_ newCapacity: Int) {
        capacity = newCapacity
        let trimmed = Self.trimmed(items, toCapacity: newCapacity)
        guard trimmed.count != items.count else { return }
        let dropped = Array(items.suffix(from: trimmed.count))
        items = trimmed
        persistence.deleteImageFiles(for: dropped)
        persistence.save(trimmed)
    }

    /// Moves an already-present item to the front of history (used when "move pasted item to top"
    /// is enabled). No-op if the item isn't found (e.g. history was cleared concurrently).
    func promoteToTop(_ item: ClipboardItem) {
        guard let index = items.firstIndex(of: item), index != 0 else { return }
        var updated = items
        updated.remove(at: index)
        updated.insert(item, at: 0)
        items = updated
        persistence.save(updated)
    }

    /// Drops every item and deletes their persisted image files. No-op (and no disk write) if
    /// history is already empty.
    func clear() {
        guard !items.isEmpty else { return }
        persistence.deleteImageFiles(for: items)
        items = []
        persistence.save(items)
    }

    nonisolated static func trimmed(_ items: [ClipboardItem], toCapacity capacity: Int) -> [ClipboardItem] {
        Array(items.prefix(max(capacity, 0)))
    }
}
