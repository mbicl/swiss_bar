//
//  swiss_barApp.swift
//  swiss_bar
//
//  Created by Maqsud Baxriddinov on 16/07/26.
//

import SwiftUI

@main
struct swiss_barApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @ObservedObject private var settings = AppSettings.shared

    var body: some Scene {
        MenuBarExtra("swiss_bar", systemImage: "square.stack") {
            MenuBarMenuView(
                permissionManager: appDelegate.permissionManager,
                keyboardCleaningManager: appDelegate.keyboardCleaningManager,
                clipboardHistoryStore: appDelegate.clipboardHistoryStore
            )
        }
        .menuBarExtraStyle(.window)

        MenuBarExtra(isInserted: $settings.networkSpeedEnabled) {
            NetworkSpeedGraphView(monitor: appDelegate.networkSpeedMonitor, settings: settings)
        } label: {
            NetworkSpeedMenuBarLabel(imageRenderer: appDelegate.networkSpeedMenuBarImageRenderer)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(settings: settings, clipboardHistoryStore: appDelegate.clipboardHistoryStore)
        }
    }
}
