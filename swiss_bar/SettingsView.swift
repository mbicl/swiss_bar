//
//  SettingsView.swift
//  swiss_bar
//

import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var clipboardHistoryStore: ClipboardHistoryStore

    var body: some View {
        TabView {
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
            Toggle("Enable Claude usage indicator", isOn: $settings.claudeUsageEnabled)
            Picker("Menu bar style", selection: $settings.claudeUsageMenuBarStyle) {
                Text("Numbers").tag(ClaudeUsageMenuBarStyle.numbers)
                Text("Progress Bars").tag(ClaudeUsageMenuBarStyle.progressBars)
            }
            .disabled(!settings.claudeUsageEnabled)
            Toggle("Show weekly usage in menu bar", isOn: $settings.claudeUsageShowWeeklyInMenuBar)
                .disabled(!settings.claudeUsageEnabled)
            TextField("CLI command", text: $settings.claudeUsageCLICommand, prompt: Text("claude"))
                .disabled(!settings.claudeUsageEnabled)
            Text("The command run to fetch usage (\"<command> -p '/usage'\"). If you have more than one Claude Code install set up as a shell alias, enter the underlying command instead of the alias name, e.g. \"CLAUDE_CONFIG_DIR=~/.claude-work claude\" rather than \"claude-work\" - this field can't see your shell's alias definitions.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Shows live Claude Code session/weekly usage as a separate menu bar item, colored green/yellow/red by how close you are to the limit. Click it for the full usage breakdown.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }
}

private struct ComingSoonNote: View {
    var body: some View {
        Text("This feature isn't implemented yet — the toggle controls whether it activates once it ships.")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}
