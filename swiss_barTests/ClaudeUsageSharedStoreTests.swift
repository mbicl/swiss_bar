//
//  ClaudeUsageSharedStoreTests.swift
//  swiss_barTests
//

import Foundation
import Testing
@testable import swiss_bar

struct ClaudeUsageSharedStoreTests {

    /// Fresh, isolated temp directory per test - real App Group container resolution
    /// (`containerURL(forSecurityApplicationGroupIdentifier:)`) requires entitlements the test
    /// host never has (both ci.yml and release.yml run tests with CODE_SIGNING_ALLOWED=NO), so
    /// every test must inject its own root rather than relying on the default.
    private func makeRoot() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("ClaudeUsageSharedStoreTests-\(UUID().uuidString)")
    }

    private func makeSnapshot(sessionPercent: Int = 42) -> ClaudeUsageSnapshot {
        ClaudeUsageSnapshot(
            sessionPercent: sessionPercent,
            sessionResetDescription: "5pm",
            weeklyLines: [ClaudeUsageWeeklyLine(label: "all models", percent: 10, resetDescription: "Monday")],
            contributing: nil
        )
    }

    @Test func readAllOnMissingContainerReturnsEmpty() {
        let store = ClaudeUsageSharedStore(rootDirectory: makeRoot())
        #expect(store.readAll().isEmpty)
    }

    @Test func writeAndReadAllRoundTrips() {
        let store = ClaudeUsageSharedStore(rootDirectory: makeRoot())
        let payloads = [
            ClaudeUsageWidgetAccountPayload(id: 0, displayName: "Work", snapshot: makeSnapshot(), lastUpdated: Date()),
            ClaudeUsageWidgetAccountPayload(id: 1, displayName: "Home", snapshot: nil, lastUpdated: Date()),
        ]
        store.write(payloads)
        #expect(store.readAll() == payloads)
    }

    @Test func upsertSlotInsertsNewSlot() {
        let store = ClaudeUsageSharedStore(rootDirectory: makeRoot())
        let payload = ClaudeUsageWidgetAccountPayload(id: 0, displayName: "Work", snapshot: makeSnapshot(), lastUpdated: Date())
        store.upsertSlot(payload)
        #expect(store.readAll() == [payload])
    }

    @Test func upsertSlotReplacesExistingSlotWithoutDisturbingOthers() {
        let store = ClaudeUsageSharedStore(rootDirectory: makeRoot())
        let other = ClaudeUsageWidgetAccountPayload(id: 1, displayName: "Home", snapshot: makeSnapshot(sessionPercent: 5), lastUpdated: Date())
        store.write([
            ClaudeUsageWidgetAccountPayload(id: 0, displayName: "Work", snapshot: makeSnapshot(sessionPercent: 10), lastUpdated: Date()),
            other,
        ])

        let updated = ClaudeUsageWidgetAccountPayload(id: 0, displayName: "Work", snapshot: makeSnapshot(sessionPercent: 90), lastUpdated: Date())
        store.upsertSlot(updated)

        let all = store.readAll()
        #expect(all.count == 2)
        #expect(all.contains(updated))
        #expect(all.contains(other))
    }

    @Test func removeSlotDropsOnlyThatSlot() {
        let store = ClaudeUsageSharedStore(rootDirectory: makeRoot())
        let keep = ClaudeUsageWidgetAccountPayload(id: 1, displayName: "Home", snapshot: makeSnapshot(), lastUpdated: Date())
        store.write([
            ClaudeUsageWidgetAccountPayload(id: 0, displayName: "Work", snapshot: makeSnapshot(), lastUpdated: Date()),
            keep,
        ])

        store.removeSlot(id: 0)

        #expect(store.readAll() == [keep])
    }
}
