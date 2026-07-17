//
//  SettingsView.swift
//  swiss_bar
//

import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        TabView {
            WindowSwitcherSettingsTab(settings: settings)
                .tabItem { Label("Window Switcher", systemImage: "rectangle.stack") }
            ClipboardHistorySettingsTab(settings: settings)
                .tabItem { Label("Clipboard", systemImage: "doc.on.clipboard") }
            KeyboardCleaningSettingsTab(settings: settings)
                .tabItem { Label("Keyboard Cleaning", systemImage: "keyboard") }
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

    var body: some View {
        Form {
            Toggle("Enable clipboard history", isOn: $settings.clipboardHistoryEnabled)
            ComingSoonNote()
        }
        .formStyle(.grouped)
    }
}

private struct KeyboardCleaningSettingsTab: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            Toggle("Enable keyboard cleaning mode", isOn: $settings.keyboardCleaningEnabled)
            ComingSoonNote()
        }
        .formStyle(.grouped)
    }
}

private struct NetworkSpeedSettingsTab: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            Toggle("Enable network speed indicator", isOn: $settings.networkSpeedEnabled)
            ComingSoonNote()
        }
        .formStyle(.grouped)
    }
}

private struct ClaudeUsageSettingsTab: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            Toggle("Enable Claude usage indicator", isOn: $settings.claudeUsageEnabled)
            ComingSoonNote()
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
