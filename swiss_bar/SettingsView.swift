//
//  SettingsView.swift
//  swiss_bar
//

import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var clipboardHistoryStore: ClipboardHistoryStore
    @ObservedObject var launchAtLoginManager: LaunchAtLoginManager

    var body: some View {
        TabView {
            GeneralSettingsTab(launchAtLoginManager: launchAtLoginManager)
                .tabItem { Label("General", systemImage: "gearshape") }
            WindowSwitcherSettingsTab(settings: settings)
                .tabItem { Label("Window Switcher", systemImage: "rectangle.stack") }
            ClipboardHistorySettingsTab(settings: settings, clipboardHistoryStore: clipboardHistoryStore)
                .tabItem { Label("Clipboard", systemImage: "doc.on.clipboard") }
            NetworkSpeedSettingsTab(settings: settings)
                .tabItem { Label("Network Speed", systemImage: "speedometer") }
            ClaudeUsageSettingsTab(settings: settings)
                .tabItem { Label("Claude Usage", systemImage: "gauge.with.needle") }
        }
        .frame(width: 520, height: 300)
    }
}

private struct GeneralSettingsTab: View {
    @ObservedObject var launchAtLoginManager: LaunchAtLoginManager

    var body: some View {
        Form {
            Toggle("Launch at login", isOn: Binding(
                get: { launchAtLoginManager.isEnabled },
                set: { launchAtLoginManager.setEnabled($0) }
            ))
            if launchAtLoginManager.requiresApproval {
                Text("Approve swiss_bar in Login Items to finish enabling this.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Open Login Items Settings…") {
                    launchAtLoginManager.openLoginItemsSettings()
                }
            }
            Text("Starts swiss_bar automatically when you log in.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }
}

private struct WindowSwitcherSettingsTab: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            Toggle("Enable window switcher (⌘ Tab)", isOn: $settings.windowSwitcherEnabled)
            Picker("Switcher style", selection: $settings.switcherStyle) {
                Text("Horizontal Icons").tag(SwitcherStyle.horizontal)
                Text("Vertical List").tag(SwitcherStyle.vertical)
            }
            .disabled(!settings.windowSwitcherEnabled)
            Picker("Size", selection: $settings.switcherSize) {
                Text("Compact").tag(SwitcherSize.compact)
                Text("Medium").tag(SwitcherSize.medium)
                Text("Large").tag(SwitcherSize.large)
            }
            .disabled(!settings.windowSwitcherEnabled)
            Picker("Tile content", selection: $settings.switcherTileContent) {
                Text("App Icon").tag(SwitcherTileContent.appIcon)
                Text("Window Preview").tag(SwitcherTileContent.windowPreview)
            }
            .disabled(!settings.windowSwitcherEnabled || settings.switcherStyle != .horizontal)
            Text("Window previews apply to the horizontal style and require Screen Recording permission. Tiles fall back to the app icon when a preview can't be captured.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Replaces the system app switcher with one that cycles through individual windows. Disabling restores the native ⌘ Tab behavior immediately.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }
}

private struct ClipboardHistorySettingsTab: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var clipboardHistoryStore: ClipboardHistoryStore

    var body: some View {
        Form {
            Toggle("Enable clipboard history", isOn: $settings.clipboardHistoryEnabled)
            Stepper("History size: \(settings.clipboardHistoryCapacity)", value: $settings.clipboardHistoryCapacity, in: 1...500)
                .disabled(!settings.clipboardHistoryEnabled)
            Toggle("Move pasted item to top of history", isOn: $settings.clipboardHistoryReorderOnPaste)
                .disabled(!settings.clipboardHistoryEnabled)
            Toggle("Capture image files copied in Finder", isOn: $settings.clipboardHistoryCaptureFinderImageFiles)
                .disabled(!settings.clipboardHistoryEnabled)
            Text("Reads the copied file to store a preview, so macOS will ask for access to the folders those files are in (Desktop, Documents, Downloads, …). Images copied from apps (browsers, screenshots) are always captured and never need folder access.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Clear History", role: .destructive) {
                clipboardHistoryStore.clear()
            }
            .disabled(clipboardHistoryStore.items.isEmpty)
            Text("Records copied text and images. Paste from history with ⌘⇧V. Oldest items are removed once this many are stored.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if NSPasteboard.general.accessBehavior != .alwaysAllow {
                Text("macOS may ask to let swiss_bar \u{201C}access data from other apps\u{201D} — that prompt is this feature reading the clipboard. Choose \u{201C}Always Allow\u{201D} to stop it recurring.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct NetworkSpeedSettingsTab: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            Toggle("Enable network speed indicator", isOn: $settings.networkSpeedEnabled)
            ColorPicker("Upload color", selection: $settings.networkSpeedUploadColor)
                .disabled(!settings.networkSpeedEnabled)
            ColorPicker("Download color", selection: $settings.networkSpeedDownloadColor)
                .disabled(!settings.networkSpeedEnabled)
            Text("Shows live upload/download speed as a separate menu bar item. Click it for a rolling graph of the last minute.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }
}

private struct ClaudeUsageSettingsTab: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            Text("Up to \(ClaudeUsageAccountSettings.slotCount) independent menu bar items, one per Claude account. Point each at a different install with its own CLI command below.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Each enabled account is also available as a desktop/Notification Center widget - add one from the macOS widget gallery (\u{2018}Claude Usage (Slot 1/2/3)\u{2019}, matching the slot order below).")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach($settings.claudeUsageAccounts) { $account in
                Section(account.displayName.isEmpty ? "Account \(account.id + 1)" : account.displayName) {
                    ClaudeUsageAccountSettingsSection(account: $account)
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct ClaudeUsageAccountSettingsSection: View {
    @Binding var account: ClaudeUsageAccountSettings

    var body: some View {
        Toggle("Enable this indicator", isOn: $account.enabled)
        TextField("Label", text: $account.displayName, prompt: Text("Account \(account.id + 1)"))
            .disabled(!account.enabled)
        Picker("Menu bar style", selection: $account.menuBarStyle) {
            Text("Numbers").tag(ClaudeUsageMenuBarStyle.numbers)
            Text("Progress Bars").tag(ClaudeUsageMenuBarStyle.progressBars)
        }
        .disabled(!account.enabled)
        Toggle("Show weekly usage in menu bar", isOn: $account.showWeeklyInMenuBar)
            .disabled(!account.enabled)
        TextField("CLI command", text: $account.cliCommand, prompt: Text("claude"))
            .disabled(!account.enabled)
        Text("The command run to fetch usage (\"<command> -p '/usage'\"). If you have more than one Claude Code install set up as a shell alias, enter the underlying command instead of the alias name, e.g. \"CLAUDE_CONFIG_DIR=~/.claude-work claude\" rather than \"claude-work\" - this field can't see your shell's alias definitions. The label above (keep it short, ~5 characters) is what distinguishes this item from your other accounts' in the menu bar.")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}
