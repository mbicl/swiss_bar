//
//  AppSettings.swift
//  swiss_bar
//

import Combine
import Foundation
import SwiftUI

/// Single source of truth for user-configurable settings, backed by `UserDefaults`
/// (injectable so tests don't touch real preferences). Every feature has an enabled flag;
/// feature-specific options (like the switcher style) live here too.
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    enum Keys {
        static let windowSwitcherEnabled = "feature.windowSwitcher.enabled"
        static let clipboardHistoryEnabled = "feature.clipboardHistory.enabled"
        static let clipboardHistoryCapacity = "feature.clipboardHistory.capacity"
        static let clipboardHistoryReorderOnPaste = "feature.clipboardHistory.reorderOnPaste"
        static let clipboardHistoryCaptureFinderImageFiles = "feature.clipboardHistory.captureFinderImageFiles"
        static let networkSpeedEnabled = "feature.networkSpeed.enabled"
        static let networkSpeedUploadColorHex = "feature.networkSpeed.uploadColorHex"
        static let networkSpeedDownloadColorHex = "feature.networkSpeed.downloadColorHex"
        static let claudeUsageAccounts = "feature.claudeUsage.accounts"
        // Pre-multi-account keys, read only by the one-time migration in `init` below - never
        // written to again, but kept indefinitely (not deleted post-migration) so a user who
        // downgrades to an older build (this ships via signed DMGs, not an auto-updating store)
        // still finds their old single-account config intact.
        static let legacyClaudeUsageEnabled = "feature.claudeUsage.enabled"
        static let legacyClaudeUsageShowWeeklyInMenuBar = "feature.claudeUsage.showWeeklyInMenuBar"
        static let legacyClaudeUsageCLICommand = "feature.claudeUsage.cliCommand"
    }

    @Published var windowSwitcherEnabled: Bool {
        didSet { defaults.set(windowSwitcherEnabled, forKey: Keys.windowSwitcherEnabled) }
    }
    @Published var clipboardHistoryEnabled: Bool {
        didSet { defaults.set(clipboardHistoryEnabled, forKey: Keys.clipboardHistoryEnabled) }
    }
    @Published var clipboardHistoryCapacity: Int {
        didSet { defaults.set(clipboardHistoryCapacity, forKey: Keys.clipboardHistoryCapacity) }
    }
    @Published var clipboardHistoryReorderOnPaste: Bool {
        didSet { defaults.set(clipboardHistoryReorderOnPaste, forKey: Keys.clipboardHistoryReorderOnPaste) }
    }
    /// Off by default: capturing a Finder-copied image file reads it from wherever it lives on
    /// disk, which makes macOS prompt for access to that folder (Desktop/Documents/Downloads/…)
    /// the first time - a surprising, unexplained prompt for a menu bar utility. Images copied
    /// from apps (browsers, screenshots) carry image *data* on the pasteboard directly and are
    /// unaffected by this setting.
    @Published var clipboardHistoryCaptureFinderImageFiles: Bool {
        didSet { defaults.set(clipboardHistoryCaptureFinderImageFiles, forKey: Keys.clipboardHistoryCaptureFinderImageFiles) }
    }
    @Published var networkSpeedEnabled: Bool {
        didSet { defaults.set(networkSpeedEnabled, forKey: Keys.networkSpeedEnabled) }
    }
    @Published var networkSpeedUploadColor: Color {
        didSet { defaults.set(ColorHex.hexString(from: networkSpeedUploadColor), forKey: Keys.networkSpeedUploadColorHex) }
    }
    @Published var networkSpeedDownloadColor: Color {
        didSet { defaults.set(ColorHex.hexString(from: networkSpeedDownloadColor), forKey: Keys.networkSpeedDownloadColorHex) }
    }
    /// Always exactly `ClaudeUsageAccountSettings.slotCount` elements with ids `0..<slotCount` -
    /// every consumer (monitors, renderers, the 3 hardcoded `MenuBarExtra` scenes) indexes this
    /// array by slot, so `AppSettings.normalized(_:)` enforces that shape on every write path
    /// (decode success, decode failure, and the one-time migration) rather than trusting it.
    @Published var claudeUsageAccounts: [ClaudeUsageAccountSettings] {
        didSet {
            if let data = try? Self.jsonEncoder.encode(claudeUsageAccounts) {
                defaults.set(data, forKey: Keys.claudeUsageAccounts)
            }
        }
    }
    @Published var switcherStyle: SwitcherStyle {
        didSet { defaults.set(switcherStyle.rawValue, forKey: SwitcherStyle.defaultsKey) }
    }
    @Published var switcherSize: SwitcherSize {
        didSet { defaults.set(switcherSize.rawValue, forKey: SwitcherSize.defaultsKey) }
    }
    @Published var switcherTileContent: SwitcherTileContent {
        didSet { defaults.set(switcherTileContent.rawValue, forKey: SwitcherTileContent.defaultsKey) }
    }

    /// Fallback hex colors when nothing's been persisted yet.
    private static let defaultUploadColorHex = "#FDD464FF"
    private static let defaultDownloadColorHex = "#A4FFB1FF"

    private static let jsonEncoder = JSONEncoder()
    private static let jsonDecoder = JSONDecoder()

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        windowSwitcherEnabled = defaults.object(forKey: Keys.windowSwitcherEnabled) as? Bool ?? false
        clipboardHistoryEnabled = defaults.object(forKey: Keys.clipboardHistoryEnabled) as? Bool ?? false
        clipboardHistoryCapacity = defaults.object(forKey: Keys.clipboardHistoryCapacity) as? Int ?? 20
        clipboardHistoryReorderOnPaste = defaults.object(forKey: Keys.clipboardHistoryReorderOnPaste) as? Bool ?? true
        clipboardHistoryCaptureFinderImageFiles = defaults.object(forKey: Keys.clipboardHistoryCaptureFinderImageFiles) as? Bool ?? false
        networkSpeedEnabled = defaults.object(forKey: Keys.networkSpeedEnabled) as? Bool ?? false
        networkSpeedUploadColor = defaults.string(forKey: Keys.networkSpeedUploadColorHex).flatMap(ColorHex.color(fromHex:))
            ?? ColorHex.color(fromHex: Self.defaultUploadColorHex) ?? .yellow
        networkSpeedDownloadColor = defaults.string(forKey: Keys.networkSpeedDownloadColorHex).flatMap(ColorHex.color(fromHex:))
            ?? ColorHex.color(fromHex: Self.defaultDownloadColorHex) ?? .mint
        claudeUsageAccounts = Self.loadClaudeUsageAccounts(from: defaults)
        switcherStyle = defaults.string(forKey: SwitcherStyle.defaultsKey).flatMap(SwitcherStyle.init) ?? .horizontal
        switcherSize = defaults.string(forKey: SwitcherSize.defaultsKey).flatMap(SwitcherSize.init) ?? .medium
        switcherTileContent = defaults.string(forKey: SwitcherTileContent.defaultsKey).flatMap(SwitcherTileContent.init) ?? .appIcon
    }

    /// Loads the per-account array if present, otherwise migrates the old single-account flat
    /// keys into slot 0 (only run once - the new key's presence is what marks migration as done).
    /// Always returns exactly `ClaudeUsageAccountSettings.slotCount` elements with ids
    /// `0..<slotCount`, regardless of what was actually stored - every consumer indexes this array
    /// by slot, so a corrupt or hand-edited defaults value must degrade to defaults, never crash.
    private static func loadClaudeUsageAccounts(from defaults: UserDefaults) -> [ClaudeUsageAccountSettings] {
        if let data = defaults.data(forKey: Keys.claudeUsageAccounts),
           let decoded = try? jsonDecoder.decode([ClaudeUsageAccountSettings].self, from: data) {
            return normalized(decoded)
        }

        var accounts = ClaudeUsageAccountSettings.defaults()
        if defaults.object(forKey: Keys.legacyClaudeUsageEnabled) != nil {
            accounts[0].enabled = defaults.object(forKey: Keys.legacyClaudeUsageEnabled) as? Bool ?? false
            accounts[0].cliCommand = defaults.string(forKey: Keys.legacyClaudeUsageCLICommand) ?? "claude"
            accounts[0].menuBarStyle = defaults.string(forKey: ClaudeUsageMenuBarStyle.defaultsKey)
                .flatMap(ClaudeUsageMenuBarStyle.init) ?? .numbers
            accounts[0].showWeeklyInMenuBar = defaults.object(forKey: Keys.legacyClaudeUsageShowWeeklyInMenuBar) as? Bool ?? true
        }
        return normalized(accounts)
    }

    /// Forces any array (freshly decoded, migrated, or otherwise) to exactly `slotCount` elements
    /// with ids `0..<slotCount` - truncates extras, pads missing slots with defaults, and
    /// reassigns ids so a stale/tampered `id` field can never desync from its array position.
    private static func normalized(_ accounts: [ClaudeUsageAccountSettings]) -> [ClaudeUsageAccountSettings] {
        var result = accounts
        if result.count > ClaudeUsageAccountSettings.slotCount {
            result = Array(result.prefix(ClaudeUsageAccountSettings.slotCount))
        } else if result.count < ClaudeUsageAccountSettings.slotCount {
            result += (result.count..<ClaudeUsageAccountSettings.slotCount).map { ClaudeUsageAccountSettings(id: $0) }
        }
        for index in result.indices {
            result[index].id = index
        }
        return result
    }
}
