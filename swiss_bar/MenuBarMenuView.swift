//
//  MenuBarMenuView.swift
//  swiss_bar
//

import AppKit
import SwiftUI

struct MenuBarMenuView: View {
    @ObservedObject var permissionManager: AccessibilityPermissionManager
    @ObservedObject var keyboardCleaningManager: KeyboardCleaningManager
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        if !permissionManager.isAccessibilityTrusted {
            Button("Grant Accessibility Access…") {
                permissionManager.requestAccessibilityAccess()
            }
            Button("Open Accessibility Settings…") {
                permissionManager.openAccessibilitySettings()
            }
        }
        if !permissionManager.isInputMonitoringGranted {
            Button("Grant Input Monitoring Access…") {
                permissionManager.requestInputMonitoringAccess()
            }
            Button("Open Input Monitoring Settings…") {
                permissionManager.openInputMonitoringSettings()
            }
        }
        if !permissionManager.isScreenRecordingGranted {
            Text("Screen Recording off — window titles on other Spaces may show app names, and previews are unavailable.")
            Button("Grant Screen Recording Access…") {
                permissionManager.requestScreenRecordingAccess()
            }
            Button("Open Screen Recording Settings…") {
                permissionManager.openScreenRecordingSettings()
            }
        }
        Toggle("Keyboard Cleaning Mode", isOn: Binding(
            get: { keyboardCleaningManager.isActive },
            set: { _ in keyboardCleaningManager.toggle() }
        ))
        .disabled(!permissionManager.isAccessibilityTrusted)
        if keyboardCleaningManager.isActive {
            Text("Keyboard input is disabled — toggle off to restore it.")
        }
        Button("Settings…") {
            // An accessory (LSUIElement) app isn't frontmost when the menu item is clicked, so
            // the Settings window would open behind other apps without an explicit activation.
            NSApp.activate(ignoringOtherApps: true)
            openSettings()
        }
        .keyboardShortcut(",")
        Divider()
        Button("Quit swiss_bar") {
            NSApplication.shared.terminate(nil)
        }
    }
}
