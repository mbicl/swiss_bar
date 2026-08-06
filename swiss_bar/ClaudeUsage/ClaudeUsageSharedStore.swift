//
//  ClaudeUsageSharedStore.swift
//  swiss_bar
//

import Foundation
import os

/// One account slot's data as handed across to `swiss_barWidgets` - mirrors
/// `ClaudeUsageAccountSettings` + `ClaudeUsageMonitor.snapshot`, but only what a widget needs to
/// render (no `cliCommand`, `menuBarStyle`, etc).
struct ClaudeUsageWidgetAccountPayload: Codable, Identifiable, Equatable {
    let id: Int
    let displayName: String
    let snapshot: ClaudeUsageSnapshot?
    let lastUpdated: Date
}

/// Disk I/O for the JSON file `swiss_barWidgets` reads to render its timeline entries - the
/// cross-process equivalent of `ClipboardHistoryPersistence`. Root directory is injectable so
/// tests never touch the real user's Application Support folder.
///
/// A plain file under `~/Library/Application Support/`, not an App Group container -
/// `containerURL(forSecurityApplicationGroupIdentifier:)` was tried first (the documented
/// mechanism for exactly this unsandboxed-app + sandboxed-extension pairing), and it looked
/// right on paper: both targets' entitlements listed the group, `codesign -d --entitlements`
/// confirmed it was embedded and properly provisioned, and the unsandboxed app could write the
/// container fine. But verified on-device (macOS 26.5.2), the sandboxed widget's own reads of a
/// file the unsandboxed app had written into that same container failed with a sandbox-layer
/// "you don't have permission to view it" - not a POSIX permission problem (the file was
/// world-readable, same UID on both sides) but Seatbelt declining to honor the App Group grant
/// for a file it didn't see a sandboxed process create. That's a real, reproducible limitation
/// of mixing an unsandboxed writer with a sandboxed reader on an App Group container on this OS
/// version, not a misconfiguration - so this store sidesteps App Group semantics entirely.
/// `swiss_barWidgets.entitlements` instead grants the widget direct read access to this
/// directory via `com.apple.security.temporary-exception.files.home-relative-path.read-only`, a
/// blunter sandbox rule keyed on path rather than App Group container provenance.
struct ClaudeUsageSharedStore {
    private static let logger = Logger(subsystem: "com.MBI.swiss-bar", category: "ClaudeUsageSharedStore")

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

    let rootDirectory: URL

    /// The *host app's* bundle ID, keyed the same "-dev" way `ClipboardHistoryPersistence`
    /// already uses - not `Bundle.main.bundleIdentifier` directly, since inside
    /// `swiss_barWidgets` that resolves to the widget's *own* bundle
    /// (`com.MBI.swiss-bar(-dev).Widgets`), not the host app's, and both sides must agree on one
    /// path regardless of which of them is asking. Both the app's and the widget's Debug bundle
    /// IDs share the "-dev" suffix convention, so a plain substring check on whichever target's
    /// own `Bundle.main` gives the right answer from either process.
    private static var hostAppBundleID: String {
        (Bundle.main.bundleIdentifier ?? "").contains("-dev") ? "com.MBI.swiss-bar-dev" : "com.MBI.swiss-bar"
    }

    /// The real, non-sandbox-redirected home directory, from the user database rather than
    /// `FileManager.default.homeDirectoryForCurrentUser`/`NSHomeDirectory()` - both of those
    /// resolve to the sandboxed widget's *container* home
    /// (`~/Library/Containers/com.MBI.swiss-bar(-dev).Widgets/Data`) when called from inside it,
    /// not the real `~/`. `home-relative-path` temporary-exception entitlements are specifically
    /// meant to be resolved against the real home directory (that's the whole point - reaching
    /// outside the container to one specific real-world path), so this must not go through the
    /// sandbox-aware APIs or the widget and the host app would each compute a different path.
    private static var realHomeDirectory: URL {
        guard let pw = getpwuid(getuid()) else { return FileManager.default.homeDirectoryForCurrentUser }
        return URL(fileURLWithPath: String(cString: pw.pointee.pw_dir))
    }

    /// `~/Library/Application Support/<host-app-bundle-id>/ClaudeUsage/` - keyed by bundle ID so
    /// `swiss_bar_dev` and the Release build never share (and one can never clobber the other's)
    /// widget data, mirroring `ClipboardHistoryPersistence.defaultRootDirectory`. Must stay in
    /// sync with the literal paths listed in `swiss_barWidgets.entitlements`'s
    /// `home-relative-path` temporary exception.
    static var defaultRootDirectory: URL {
        realHomeDirectory
            .appendingPathComponent("Library")
            .appendingPathComponent("Application Support")
            .appendingPathComponent(hostAppBundleID)
            .appendingPathComponent("ClaudeUsage")
    }

    init(rootDirectory: URL = ClaudeUsageSharedStore.defaultRootDirectory) {
        self.rootDirectory = rootDirectory
    }

    private var fileURL: URL { rootDirectory.appendingPathComponent("claude-usage-widget-data.json") }

    /// Staged (rather than one collapsed `try?`) so a failure here - most importantly when called
    /// from inside the sandboxed widget extension, where a sandbox read denial is a real
    /// possibility distinct from "no data written yet" - is diagnosable via `log stream` instead
    /// of silently indistinguishable from the empty-state case.
    func readAll() -> [ClaudeUsageWidgetAccountPayload] {
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            Self.logger.error("readAll: failed to read \(fileURL.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return []
        }
        do {
            return try JSONDecoder().decode([ClaudeUsageWidgetAccountPayload].self, from: data)
        } catch {
            Self.logger.error("readAll: failed to decode \(fileURL.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    /// Atomic write: encode fully in memory, write to a temp file, then replace the target file in
    /// one filesystem operation, so a crash/kill mid-save (or the widget reading concurrently)
    /// never sees a half-written file.
    func write(_ payloads: [ClaudeUsageWidgetAccountPayload]) {
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
