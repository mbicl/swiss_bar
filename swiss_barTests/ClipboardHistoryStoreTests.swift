//
//  ClipboardHistoryStoreTests.swift
//  swiss_barTests
//

import Foundation
import Testing
@testable import swiss_bar

@MainActor
struct ClipboardHistoryStoreTests {

    private func makeItem(_ text: String) -> ClipboardItem {
        ClipboardItem(id: UUID(), date: Date(), contentHash: ClipboardContentHasher.hash(text), kind: .text(text))
    }

    /// Fresh, isolated temp directory per test so tests never touch each other's on-disk state.
    private func makePersistence() -> ClipboardHistoryPersistence {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ClipboardHistoryStoreTests-\(UUID().uuidString)")
        return ClipboardHistoryPersistence(rootDirectory: root)
    }

    private func text(of item: ClipboardItem) -> String? {
        if case .text(let value) = item.kind { return value }
        return nil
    }

    @Test func trimmedDropsOldestBeyondCapacity() {
        let items = (0..<5).map { makeItem("item\($0)") }
        let trimmed = ClipboardHistoryStore.trimmed(items, toCapacity: 3)
        #expect(trimmed == Array(items.prefix(3)))
    }

    @Test func trimmedUnderCapacityIsUnchanged() {
        let items = (0..<2).map { makeItem("item\($0)") }
        #expect(ClipboardHistoryStore.trimmed(items, toCapacity: 5) == items)
    }

    @Test func trimmedAtZeroCapacityIsEmpty() {
        let items = (0..<2).map { makeItem("item\($0)") }
        #expect(ClipboardHistoryStore.trimmed(items, toCapacity: 0).isEmpty)
    }

    @Test func trimmedWithNegativeCapacityIsEmpty() {
        let items = (0..<2).map { makeItem("item\($0)") }
        #expect(ClipboardHistoryStore.trimmed(items, toCapacity: -1).isEmpty)
    }

    @Test func addPrependsNewestFirst() {
        let store = ClipboardHistoryStore(persistence: makePersistence(), capacity: 10)
        store.add(makeItem("first"))
        store.add(makeItem("second"))
        #expect(store.items.map(text) == ["second", "first"])
    }

    @Test func addEvictsOldestBeyondCapacity() {
        let store = ClipboardHistoryStore(persistence: makePersistence(), capacity: 2)
        store.add(makeItem("a"))
        store.add(makeItem("b"))
        store.add(makeItem("c"))
        #expect(store.items.map(text) == ["c", "b"])
    }

    @Test func setCapacityTrimsExistingItems() {
        let store = ClipboardHistoryStore(persistence: makePersistence(), capacity: 10)
        for i in 0..<5 { store.add(makeItem("item\(i)")) }
        store.setCapacity(2)
        #expect(store.items.count == 2)
    }

    @Test func setCapacityIncreaseKeepsExistingItems() {
        let store = ClipboardHistoryStore(persistence: makePersistence(), capacity: 2)
        store.add(makeItem("a"))
        store.add(makeItem("b"))
        store.setCapacity(10)
        #expect(store.items.count == 2)
    }

    @Test func promoteToTopMovesItemToFront() {
        let store = ClipboardHistoryStore(persistence: makePersistence(), capacity: 10)
        store.add(makeItem("a"))
        store.add(makeItem("b"))
        store.add(makeItem("c"))
        let target = store.items[2] // "a", currently last
        store.promoteToTop(target)
        #expect(store.items.first == target)
        #expect(store.items.map(text) == ["a", "c", "b"])
    }

    @Test func promoteToTopOfAlreadyTopItemIsNoOp() {
        let store = ClipboardHistoryStore(persistence: makePersistence(), capacity: 10)
        store.add(makeItem("a"))
        store.add(makeItem("b"))
        let before = store.items
        store.promoteToTop(before[0])
        #expect(store.items == before)
    }
}
