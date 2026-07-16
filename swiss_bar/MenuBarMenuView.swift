//
//  MenuBarMenuView.swift
//  swiss_bar
//

import AppKit
import SwiftUI

struct MenuBarMenuView: View {
    @ObservedObject var permissionManager: AccessibilityPermissionManager

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
        Divider()
        Button("Quit swiss_bar") {
            NSApplication.shared.terminate(nil)
        }
    }
}
