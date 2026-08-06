//
//  ClaudeUsageSharedStoreTests.swift
//  swiss_barTests
//

import Foundation
import Testing
@testable import swiss_bar

struct ClaudeUsageSharedStoreTests {

    /// Fresh, isolated temp directory per test, so tests never touch the real user's
    /// `~/Library/Application Support/` (mirrors `ClipboardHistoryPersistence`'s test rationale).
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

    @Test func readAllOnMissingFileReturnsEmpty() {
        let store = ClaudeUsageSharedStore(rootDirectory: makeRoot())
        #expect(store.readAll().isEmpty)
    }

    /// Guards the staged error handling in `readAll()` - a corrupt/partial file (e.g. a concurrent
    /// read racing an in-progress write, or a schema mismatch) must degrade to "no data" rather
    /// than crash the widget extension.
    @Test func readAllOnCorruptFileReturnsEmpty() throws {
        let root = makeRoot()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("not valid json".utf8).write(to: root.appendingPathComponent("claude-usage-widget-data.json"))

        let store = ClaudeUsageSharedStore(rootDirectory: root)
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

    /// Guards the path shape (`~/Library/Application Support/<bundle-id>/ClaudeUsage`) that
    /// `swiss_barWidgets.entitlements`'s `home-relative-path` temporary exception is keyed to -
    /// this test process is unsandboxed (like the real host app), so it can't reproduce the
    /// sandbox-container-redirection bug this path computation was written to avoid, but it does
    /// catch an accidental reversion to a different directory shape.
    @Test func defaultRootDirectoryIsApplicationSupportSlashBundleIDSlashClaudeUsage() {
        let url = ClaudeUsageSharedStore.defaultRootDirectory
        #expect(url.lastPathComponent == "ClaudeUsage")
        #expect(url.deletingLastPathComponent().lastPathComponent.hasPrefix("com.MBI.swiss-bar"))
        #expect(url.path.contains("/Library/Application Support/"))
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
