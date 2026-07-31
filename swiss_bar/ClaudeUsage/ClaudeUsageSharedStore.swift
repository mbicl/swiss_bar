//
//  ClaudeUsageSharedStore.swift
//  swiss_bar
//

import Foundation
import os

/// One account slot's data as handed across the App Group boundary to `swiss_barWidgets` -
/// mirrors `ClaudeUsageAccountSettings` + `ClaudeUsageMonitor.snapshot`, but only what a widget
/// needs to render (no `cliCommand`, `menuBarStyle`, etc).
struct ClaudeUsageWidgetAccountPayload: Codable, Identifiable, Equatable {
    let id: Int
    let displayName: String
    let snapshot: ClaudeUsageSnapshot?
    let lastUpdated: Date
}

/// Disk I/O for the JSON file `swiss_barWidgets` reads to render its timeline entries - the
/// App Group equivalent of `ClipboardHistoryPersistence`. Root directory is injectable for the
/// same reason: both `ci.yml` and `release.yml` run `xcodebuild test` with
/// `CODE_SIGNING_ALLOWED=NO`, so the test host has no entitlements and
/// `containerURL(forSecurityApplicationGroupIdentifier:)` returns `nil` there - tests must never
/// depend on it resolving.
///
/// Deliberately a plain JSON file rather than `UserDefaults(suiteName:)` - `containerURL` is the
/// documented mechanism for cross-process sharing regardless of sandbox state on either side
/// (this app is unsandboxed, the widget extension is sandboxed), and a plain file is trivially
/// inspectable from Terminal while debugging.
struct ClaudeUsageSharedStore {
    private static let logger = Logger(subsystem: "com.MBI.swiss-bar", category: "ClaudeUsageSharedStore")
    static let appGroupID = "group.com.MBI.swiss-bar"

    /// Single source of truth for the per-slot `kind:` both `ClaudeUsageMonitor`'s
    /// `WidgetCenter.reloadTimelines(ofKind:)` call and each slot's `Widget` declaration use -
    /// keeping them as separately-built string literals is exactly how the two would silently
    /// drift out of sync. One static `Widget` type per slot (`ClaudeUsageWidgetSlot0/1/2` in
    /// swiss_barWidgets) rather than one `AppIntentConfiguration`-based widget with an in-gallery
    /// account picker - a real toolchain bug in this Xcode/SDK combination makes `WidgetKit`'s
    /// `Widget`/`WidgetConfiguration` symbols unresolvable in any file of a module that also
    /// imports `AppIntents` (reproduced with a minimal two-file repro outside Xcode entirely, so
    /// this isn't fixable from this codebase). Three static slots also mirrors the pattern
    /// `swiss_barApp.swift` already uses for the menu bar's `MenuBarExtra` scenes.
    static func widgetKind(forSlot id: Int) -> String { "ClaudeUsageWidgetSlot\(id)" }

    let rootDirectory: URL?

    static var defaultRootDirectory: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
    }

    init(rootDirectory: URL? = ClaudeUsageSharedStore.defaultRootDirectory) {
        self.rootDirectory = rootDirectory
    }

    private var fileURL: URL? { rootDirectory?.appendingPathComponent("claude-usage-widget-data.json") }

    func readAll() -> [ClaudeUsageWidgetAccountPayload] {
        guard let fileURL, let data = try? Data(contentsOf: fileURL),
              let payloads = try? JSONDecoder().decode([ClaudeUsageWidgetAccountPayload].self, from: data) else {
            return []
        }
        return payloads
    }

    /// Atomic write: encode fully in memory, write to a temp file, then replace the target file in
    /// one filesystem operation, so a crash/kill mid-save (or the widget reading concurrently)
    /// never sees a half-written file.
    func write(_ payloads: [ClaudeUsageWidgetAccountPayload]) {
        guard let rootDirectory, let fileURL else {
            Self.logger.error("containerURL(forSecurityApplicationGroupIdentifier:) returned nil - App Group entitlement not effective")
            return
        }
        do {
            try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(payloads)
            let tmpURL = rootDirectory.appendingPathComponent("claude-usage-widget-data.json.tmp")
            try data.write(to: tmpURL)
            _ = try FileManager.default.replaceItemAt(fileURL, withItemAt: tmpURL)
        } catch {
            Self.logger.error("write failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Read-modify-write helper for a single account slot - safe to call from any one
    /// `ClaudeUsageMonitor` without coordinating with the others, since all monitors are
    /// `@MainActor` and therefore never call this concurrently with each other.
    func upsertSlot(_ payload: ClaudeUsageWidgetAccountPayload) {
        var all = readAll()
        if let index = all.firstIndex(where: { $0.id == payload.id }) {
            all[index] = payload
        } else {
            all.append(payload)
        }
        write(all)
    }

    /// Removes a slot entirely - used when an account is disabled, so a widget still configured
    /// to show it doesn't keep displaying stale numbers forever.
    func removeSlot(id: Int) {
        write(readAll().filter { $0.id != id })
    }
}
