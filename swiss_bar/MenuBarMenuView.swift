//
//  MenuBarMenuView.swift
//  swiss_bar
//

import AppKit
import SwiftUI

/// `.menuBarExtraStyle(.window)` renders this in a custom floating panel rather than a native
/// NSMenu - that's required for the Keyboard Cleaning row to show a real system switch (NSMenu
/// items only support text + a checkmark/icon, never an interactive control). The tradeoff: rows
/// don't auto-dismiss the panel the way native menu items would, so each row closes it explicitly
/// via `NSApp.keyWindow?.close()` before acting - except the switch itself, which (like Control
/// Center's toggles) stays open so the panel's "keyboard input is disabled" reminder stays visible.
struct MenuBarMenuView: View {
    @ObservedObject var permissionManager: AccessibilityPermissionManager
    @ObservedObject var keyboardCleaningManager: KeyboardCleaningManager
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !permissionManager.isAccessibilityTrusted {
                MenuRow("Grant Accessibility Access…") {
                    permissionManager.requestAccessibilityAccess()
                }
                MenuRow("Open Accessibility Settings…") {
                    permissionManager.openAccessibilitySettings()
                }
                Divider()
            }
            if !permissionManager.isInputMonitoringGranted {
                MenuRow("Grant Input Monitoring Access…") {
                    permissionManager.requestInputMonitoringAccess()
                }
                MenuRow("Open Input Monitoring Settings…") {
                    permissionManager.openInputMonitoringSettings()
                }
                Divider()
            }
            if !permissionManager.isScreenRecordingGranted {
                Text("Screen Recording off — window titles on other Spaces may show app names, and previews are unavailable.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                MenuRow("Grant Screen Recording Access…") {
                    permissionManager.requestScreenRecordingAccess()
                }
                MenuRow("Open Screen Recording Settings…") {
                    permissionManager.openScreenRecordingSettings()
                }
                Divider()
            }

            Toggle(isOn: Binding(
                get: { keyboardCleaningManager.isActive },
                set: { _ in keyboardCleaningManager.toggle() }
            )) {
                Text("Keyboard cleaning")
            }
            .toggleStyle(.switch)
            .disabled(!permissionManager.isAccessibilityTrusted)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)

            if keyboardCleaningManager.isActive {
                Text("Keyboard input is disabled — switch off to restore it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 4)
            }

            Divider()

            MenuRow("Settings…", keyboardShortcut: ",") {
                // An accessory (LSUIElement) app isn't frontmost when the row is clicked, so
                // the Settings window would open behind other apps without an explicit activation.
                NSApp.activate(ignoringOtherApps: true)
                openSettings()
            }
            Divider()
            MenuRow("Quit swiss_bar") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(.vertical, 6)
        .frame(width: 280)
    }
}

/// A menu-item-style row for the custom `.window`-style panel: full-width, left-aligned, subtle
/// hover highlight, closes the panel before running `action` (mirrors a native NSMenu item, which
/// closes the menu as part of selecting it).
private struct MenuRow: View {
    let title: String
    var keyboardShortcut: KeyEquivalent?
    let action: () -> Void

    @State private var isHovering = false

    init(_ title: String, keyboardShortcut: KeyEquivalent? = nil, action: @escaping () -> Void) {
        self.title = title
        self.keyboardShortcut = keyboardShortcut
        self.action = action
    }

    var body: some View {
        let button = Button {
            NSApp.keyWindow?.close()
            action()
        } label: {
            Text(title)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(isHovering ? Color.accentColor.opacity(0.15) : Color.clear)
        .onHover { isHovering = $0 }

        if let keyboardShortcut {
            button.keyboardShortcut(keyboardShortcut)
        } else {
            button
        }
    }
}
