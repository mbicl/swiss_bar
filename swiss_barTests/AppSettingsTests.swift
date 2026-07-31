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

    @Test func allFeaturesDefaultToDisabled() {
        let settings = AppSettings(defaults: makeDefaults())

        #expect(settings.windowSwitcherEnabled == false)
        #expect(settings.clipboardHistoryEnabled == false)
        #expect(settings.networkSpeedEnabled == false)
        #expect(settings.claudeUsageAccounts.allSatisfy { !$0.enabled })
    }

    @Test func switcherStyleDefaultsToHorizontal() {
        let settings = AppSettings(defaults: makeDefaults())
        #expect(settings.switcherStyle == .horizontal)
    }

    @Test func enablingAFeaturePersistsWithoutAffectingOthers() {
        let defaults = makeDefaults()

        AppSettings(defaults: defaults).windowSwitcherEnabled = true

        let reloaded = AppSettings(defaults: defaults)
        #expect(reloaded.windowSwitcherEnabled == true)
        #expect(reloaded.clipboardHistoryEnabled == false)
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

    @Test func clipboardHistoryCaptureFinderImageFilesDefaultsToFalse() {
        let settings = AppSettings(defaults: makeDefaults())
        #expect(settings.clipboardHistoryCaptureFinderImageFiles == false)
    }

    @Test func clipboardHistoryCaptureFinderImageFilesPersists() {
        let defaults = makeDefaults()

        AppSettings(defaults: defaults).clipboardHistoryCaptureFinderImageFiles = true

        let reloaded = AppSettings(defaults: defaults)
        #expect(reloaded.clipboardHistoryCaptureFinderImageFiles == true)
    }

    @Test func networkSpeedColorsDefaultToConfiguredHexValues() {
        let settings = AppSettings(defaults: makeDefaults())
        #expect(ColorHex.hexString(from: settings.networkSpeedUploadColor) == "#FDD464FF")
        #expect(ColorHex.hexString(from: settings.networkSpeedDownloadColor) == "#A4FFB1FF")
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

    @Test func claudeUsageAccountsDefaultToThreeDisabledSlots() {
        let settings = AppSettings(defaults: makeDefaults())

        #expect(settings.claudeUsageAccounts.count == ClaudeUsageAccountSettings.slotCount)
        #expect(settings.claudeUsageAccounts.map(\.id) == Array(0..<ClaudeUsageAccountSettings.slotCount))
        #expect(settings.claudeUsageAccounts.allSatisfy { !$0.enabled && $0.cliCommand == "claude" })
    }

    @Test func claudeUsageAccountsRoundTripAndLeaveOtherSlotsUntouched() {
        let defaults = makeDefaults()

        let settings = AppSettings(defaults: defaults)
        settings.claudeUsageAccounts[1].enabled = true
        settings.claudeUsageAccounts[1].displayName = "Work"
        settings.claudeUsageAccounts[1].cliCommand = "CLAUDE_CONFIG_DIR=~/.claude-work claude"

        let reloaded = AppSettings(defaults: defaults)
        #expect(reloaded.claudeUsageAccounts[1].enabled == true)
        #expect(reloaded.claudeUsageAccounts[1].displayName == "Work")
        #expect(reloaded.claudeUsageAccounts[1].cliCommand == "CLAUDE_CONFIG_DIR=~/.claude-work claude")
        #expect(reloaded.claudeUsageAccounts[0].enabled == false)
        #expect(reloaded.claudeUsageAccounts[2].enabled == false)
    }

    @Test func legacyClaudeUsageKeysMigrateIntoSlotZero() {
        let defaults = makeDefaults()
        defaults.set(true, forKey: AppSettings.Keys.legacyClaudeUsageEnabled)
        defaults.set("CLAUDE_CONFIG_DIR=~/.claude-work claude", forKey: AppSettings.Keys.legacyClaudeUsageCLICommand)
        defaults.set(false, forKey: AppSettings.Keys.legacyClaudeUsageShowWeeklyInMenuBar)
        defaults.set(ClaudeUsageMenuBarStyle.progressBars.rawValue, forKey: ClaudeUsageMenuBarStyle.defaultsKey)

        let settings = AppSettings(defaults: defaults)

        #expect(settings.claudeUsageAccounts[0].enabled == true)
        #expect(settings.claudeUsageAccounts[0].cliCommand == "CLAUDE_CONFIG_DIR=~/.claude-work claude")
        #expect(settings.claudeUsageAccounts[0].showWeeklyInMenuBar == false)
        #expect(settings.claudeUsageAccounts[0].menuBarStyle == .progressBars)
        #expect(settings.claudeUsageAccounts[1].enabled == false)
        #expect(settings.claudeUsageAccounts[2].enabled == false)
    }

    @Test func legacyClaudeUsageKeysDoNotOverrideAnAlreadyMigratedArray() {
        let defaults = makeDefaults()
        defaults.set(true, forKey: AppSettings.Keys.legacyClaudeUsageEnabled)
        defaults.set("claude-legacy", forKey: AppSettings.Keys.legacyClaudeUsageCLICommand)

        // First construction performs the migration and persists the new array key.
        _ = AppSettings(defaults: defaults)
        // Simulate the user having since changed slot 0 through the new storage.
        let migrated = AppSettings(defaults: defaults)
        migrated.claudeUsageAccounts[0].cliCommand = "claude-current"

        let reloaded = AppSettings(defaults: defaults)
        #expect(reloaded.claudeUsageAccounts[0].cliCommand == "claude-current")
    }

    @Test func corruptClaudeUsageAccountsDataFallsBackToDefaults() {
        let defaults = makeDefaults()
        defaults.set(Data("not json".utf8), forKey: AppSettings.Keys.claudeUsageAccounts)

        let settings = AppSettings(defaults: defaults)
        #expect(settings.claudeUsageAccounts.count == ClaudeUsageAccountSettings.slotCount)
        #expect(settings.claudeUsageAccounts.map(\.id) == Array(0..<ClaudeUsageAccountSettings.slotCount))
    }

    @Test func oversizedClaudeUsageAccountsArrayIsTruncatedAndReindexed() throws {
        let defaults = makeDefaults()
        let oversized = (0..<5).map { ClaudeUsageAccountSettings(id: $0, displayName: "Slot\($0)") }
        let data = try JSONEncoder().encode(oversized)
        defaults.set(data, forKey: AppSettings.Keys.claudeUsageAccounts)

        let settings = AppSettings(defaults: defaults)
        #expect(settings.claudeUsageAccounts.count == ClaudeUsageAccountSettings.slotCount)
        #expect(settings.claudeUsageAccounts.map(\.id) == Array(0..<ClaudeUsageAccountSettings.slotCount))
        #expect(settings.claudeUsageAccounts.map(\.displayName) == ["Slot0", "Slot1", "Slot2"])
    }

    @Test func undersizedClaudeUsageAccountsArrayIsPaddedWithDefaults() throws {
        let defaults = makeDefaults()
        let undersized = [ClaudeUsageAccountSettings(id: 0, displayName: "Only")]
        let data = try JSONEncoder().encode(undersized)
        defaults.set(data, forKey: AppSettings.Keys.claudeUsageAccounts)

        let settings = AppSettings(defaults: defaults)
        #expect(settings.claudeUsageAccounts.count == ClaudeUsageAccountSettings.slotCount)
        #expect(settings.claudeUsageAccounts.map(\.id) == Array(0..<ClaudeUsageAccountSettings.slotCount))
        #expect(settings.claudeUsageAccounts[0].displayName == "Only")
        #expect(settings.claudeUsageAccounts[1].enabled == false)
        #expect(settings.claudeUsageAccounts[2].enabled == false)
    }
}
