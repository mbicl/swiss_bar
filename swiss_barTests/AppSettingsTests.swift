//
//  AppSettingsTests.swift
//  swiss_barTests
//

import Foundation
import SwiftUI
import Testing
@testable import swiss_bar

@MainActor
struct AppSettingsTests {

    /// Fresh, isolated defaults per test so tests never touch real preferences or each other.
    private func makeDefaults() -> UserDefaults {
        let suiteName = "AppSettingsTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    @Test func allFeaturesDefaultToEnabled() {
        let settings = AppSettings(defaults: makeDefaults())

        #expect(settings.windowSwitcherEnabled)
        #expect(settings.clipboardHistoryEnabled)
        #expect(settings.networkSpeedEnabled)
        #expect(settings.claudeUsageEnabled)
    }

    @Test func switcherStyleDefaultsToHorizontal() {
        let settings = AppSettings(defaults: makeDefaults())
        #expect(settings.switcherStyle == .horizontal)
    }

    @Test func disablingAFeaturePersists() {
        let defaults = makeDefaults()

        AppSettings(defaults: defaults).windowSwitcherEnabled = false

        let reloaded = AppSettings(defaults: defaults)
        #expect(reloaded.windowSwitcherEnabled == false)
        #expect(reloaded.clipboardHistoryEnabled == true)
    }

    @Test func switcherStylePersists() {
        let defaults = makeDefaults()

        AppSettings(defaults: defaults).switcherStyle = .vertical

        let reloaded = AppSettings(defaults: defaults)
        #expect(reloaded.switcherStyle == .vertical)
    }

    @Test func invalidStoredStyleFallsBackToHorizontal() {
        let defaults = makeDefaults()
        defaults.set("bogus", forKey: SwitcherStyle.defaultsKey)

        let settings = AppSettings(defaults: defaults)
        #expect(settings.switcherStyle == .horizontal)
    }

    @Test func switcherSizeDefaultsToMedium() {
        let settings = AppSettings(defaults: makeDefaults())
        #expect(settings.switcherSize == .medium)
    }

    @Test func switcherTileContentDefaultsToAppIcon() {
        let settings = AppSettings(defaults: makeDefaults())
        #expect(settings.switcherTileContent == .appIcon)
    }

    @Test func switcherSizeAndTileContentPersist() {
        let defaults = makeDefaults()

        let settings = AppSettings(defaults: defaults)
        settings.switcherSize = .large
        settings.switcherTileContent = .windowPreview

        let reloaded = AppSettings(defaults: defaults)
        #expect(reloaded.switcherSize == .large)
        #expect(reloaded.switcherTileContent == .windowPreview)
    }

    @Test func clipboardHistoryCapacityDefaultsToTwenty() {
        let settings = AppSettings(defaults: makeDefaults())
        #expect(settings.clipboardHistoryCapacity == 20)
    }

    @Test func clipboardHistoryReorderOnPasteDefaultsToTrue() {
        let settings = AppSettings(defaults: makeDefaults())
        #expect(settings.clipboardHistoryReorderOnPaste == true)
    }

    @Test func clipboardHistoryCapacityPersists() {
        let defaults = makeDefaults()

        AppSettings(defaults: defaults).clipboardHistoryCapacity = 50

        let reloaded = AppSettings(defaults: defaults)
        #expect(reloaded.clipboardHistoryCapacity == 50)
    }

    @Test func clipboardHistoryReorderOnPastePersists() {
        let defaults = makeDefaults()

        AppSettings(defaults: defaults).clipboardHistoryReorderOnPaste = false

        let reloaded = AppSettings(defaults: defaults)
        #expect(reloaded.clipboardHistoryReorderOnPaste == false)
    }

    @Test func networkSpeedColorsDefaultToYellowAndMint() {
        let settings = AppSettings(defaults: makeDefaults())
        #expect(settings.networkSpeedUploadColor == .yellow)
        #expect(settings.networkSpeedDownloadColor == .mint)
    }

    @Test func networkSpeedColorsPersist() {
        let defaults = makeDefaults()

        let settings = AppSettings(defaults: defaults)
        settings.networkSpeedUploadColor = .red
        settings.networkSpeedDownloadColor = .blue

        // `Color`'s `==` isn't reliable across different construction paths (a named system color
        // vs. one reconstructed from RGBA components), so compare via the same hex encoding the
        // persistence layer itself uses rather than comparing `Color` values directly.
        let reloaded = AppSettings(defaults: defaults)
        #expect(ColorHex.hexString(from: reloaded.networkSpeedUploadColor) == ColorHex.hexString(from: .red))
        #expect(ColorHex.hexString(from: reloaded.networkSpeedDownloadColor) == ColorHex.hexString(from: .blue))
    }
}
