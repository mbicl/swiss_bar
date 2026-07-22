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
        static let networkSpeedEnabled = "feature.networkSpeed.enabled"
        static let networkSpeedUploadColorHex = "feature.networkSpeed.uploadColorHex"
        static let networkSpeedDownloadColorHex = "feature.networkSpeed.downloadColorHex"
        static let claudeUsageEnabled = "feature.claudeUsage.enabled"
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
        windowSwitcherEnabled = defaults.object(forKey: Keys.windowSwitcherEnabled) as? Bool ?? true
        clipboardHistoryEnabled = defaults.object(forKey: Keys.clipboardHistoryEnabled) as? Bool ?? true
        clipboardHistoryCapacity = defaults.object(forKey: Keys.clipboardHistoryCapacity) as? Int ?? 20
        clipboardHistoryReorderOnPaste = defaults.object(forKey: Keys.clipboardHistoryReorderOnPaste) as? Bool ?? true
        networkSpeedEnabled = defaults.object(forKey: Keys.networkSpeedEnabled) as? Bool ?? true
        networkSpeedUploadColor = defaults.string(forKey: Keys.networkSpeedUploadColorHex).flatMap(ColorHex.color(fromHex:))
            ?? ColorHex.color(fromHex: Self.defaultUploadColorHex) ?? .yellow
        networkSpeedDownloadColor = defaults.string(forKey: Keys.networkSpeedDownloadColorHex).flatMap(ColorHex.color(fromHex:))
            ?? ColorHex.color(fromHex: Self.defaultDownloadColorHex) ?? .mint
        claudeUsageEnabled = defaults.object(forKey: Keys.claudeUsageEnabled) as? Bool ?? true
        switcherStyle = defaults.string(forKey: SwitcherStyle.defaultsKey).flatMap(SwitcherStyle.init) ?? .horizontal
        switcherSize = defaults.string(forKey: SwitcherSize.defaultsKey).flatMap(SwitcherSize.init) ?? .medium
        switcherTileContent = defaults.string(forKey: SwitcherTileContent.defaultsKey).flatMap(SwitcherTileContent.init) ?? .appIcon
    }
}
