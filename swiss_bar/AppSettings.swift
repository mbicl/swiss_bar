//
//  AppSettings.swift
//  swiss_bar
//

import Combine
import Foundation

/// Single source of truth for user-configurable settings, backed by `UserDefaults`
/// (injectable so tests don't touch real preferences). Every feature has an enabled flag;
/// feature-specific options (like the switcher style) live here too.
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    enum Keys {
        static let windowSwitcherEnabled = "feature.windowSwitcher.enabled"
        static let clipboardHistoryEnabled = "feature.clipboardHistory.enabled"
        static let keyboardCleaningEnabled = "feature.keyboardCleaning.enabled"
        static let networkSpeedEnabled = "feature.networkSpeed.enabled"
        static let claudeUsageEnabled = "feature.claudeUsage.enabled"
    }

    @Published var windowSwitcherEnabled: Bool {
        didSet { defaults.set(windowSwitcherEnabled, forKey: Keys.windowSwitcherEnabled) }
    }
    @Published var clipboardHistoryEnabled: Bool {
        didSet { defaults.set(clipboardHistoryEnabled, forKey: Keys.clipboardHistoryEnabled) }
    }
    @Published var keyboardCleaningEnabled: Bool {
        didSet { defaults.set(keyboardCleaningEnabled, forKey: Keys.keyboardCleaningEnabled) }
    }
    @Published var networkSpeedEnabled: Bool {
        didSet { defaults.set(networkSpeedEnabled, forKey: Keys.networkSpeedEnabled) }
    }
    @Published var claudeUsageEnabled: Bool {
        didSet { defaults.set(claudeUsageEnabled, forKey: Keys.claudeUsageEnabled) }
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

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        windowSwitcherEnabled = defaults.object(forKey: Keys.windowSwitcherEnabled) as? Bool ?? true
        clipboardHistoryEnabled = defaults.object(forKey: Keys.clipboardHistoryEnabled) as? Bool ?? true
        keyboardCleaningEnabled = defaults.object(forKey: Keys.keyboardCleaningEnabled) as? Bool ?? true
        networkSpeedEnabled = defaults.object(forKey: Keys.networkSpeedEnabled) as? Bool ?? true
        claudeUsageEnabled = defaults.object(forKey: Keys.claudeUsageEnabled) as? Bool ?? true
        switcherStyle = defaults.string(forKey: SwitcherStyle.defaultsKey).flatMap(SwitcherStyle.init) ?? .horizontal
        switcherSize = defaults.string(forKey: SwitcherSize.defaultsKey).flatMap(SwitcherSize.init) ?? .medium
        switcherTileContent = defaults.string(forKey: SwitcherTileContent.defaultsKey).flatMap(SwitcherTileContent.init) ?? .appIcon
    }
}
