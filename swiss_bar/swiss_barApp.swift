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

    var body: some Scene {
        MenuBarExtra("swiss_bar", systemImage: "square.stack") {
            MenuBarMenuView(permissionManager: appDelegate.permissionManager)
        }
        Settings {
            SettingsView(settings: AppSettings.shared)
        }
    }
}
