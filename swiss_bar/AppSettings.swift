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
        static let claudeUsageEnabled = "feature.claudeUsage.enabled"
        static let claudeUsageShowWeeklyInMenuBar = "feature.claudeUsage.showWeeklyInMenuBar"
        static let claudeUsageCLICommand = "feature.claudeUsage.cliCommand"
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
    @Published var claudeUsageEnabled: Bool {
        didSet { defaults.set(claudeUsageEnabled, forKey: Keys.claudeUsageEnabled) }
    }
    @Published var claudeUsageMenuBarStyle: ClaudeUsageMenuBarStyle {
        didSet { defaults.set(claudeUsageMenuBarStyle.rawValue, forKey: ClaudeUsageMenuBarStyle.defaultsKey) }
    }
    @Published var claudeUsageShowWeeklyInMenuBar: Bool {
        didSet { defaults.set(claudeUsageShowWeeklyInMenuBar, forKey: Keys.claudeUsageShowWeeklyInMenuBar) }
    }
    /// Executable name (resolved via the login shell's PATH, so a bare name works the same as a
    /// full path) or absolute path - lets a user with multiple Claude Code installs (e.g.
    /// `claude-work`, `claude-personal`) point the usage monitor at the right one.
    @Published var claudeUsageCLICommand: String {
        didSet { defaults.set(claudeUsageCLICommand, forKey: Keys.claudeUsageCLICommand) }
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
        claudeUsageEnabled = defaults.object(forKey: Keys.claudeUsageEnabled) as? Bool ?? false
        claudeUsageMenuBarStyle = defaults.string(forKey: ClaudeUsageMenuBarStyle.defaultsKey).flatMap(ClaudeUsageMenuBarStyle.init) ?? .numbers
        claudeUsageShowWeeklyInMenuBar = defaults.object(forKey: Keys.claudeUsageShowWeeklyInMenuBar) as? Bool ?? true
        claudeUsageCLICommand = defaults.string(forKey: Keys.claudeUsageCLICommand) ?? "claude"
        switcherStyle = defaults.string(forKey: SwitcherStyle.defaultsKey).flatMap(SwitcherStyle.init) ?? .horizontal
        switcherSize = defaults.string(forKey: SwitcherSize.defaultsKey).flatMap(SwitcherSize.init) ?? .medium
        switcherTileContent = defaults.string(forKey: SwitcherTileContent.defaultsKey).flatMap(SwitcherTileContent.init) ?? .appIcon
    }
}
