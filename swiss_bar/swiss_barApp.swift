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

        // `.constant(...)` rather than a two-way `$settings.networkSpeedEnabled` Binding
        // deliberately - MenuBarExtra's `isInserted:` has a documented SwiftUI defect where it can
        // write back into the bound storage during its own internal scene update, which (with a
        // `@Published` property) fires `objectWillChange` while a view update is already in
        // progress and causes an unending update-retry loop - confirmed via a real freeze sample
        // showing `MenuBarExtraHost.requestUpdate` repeatedly calling `updateButton` for *both*
        // status items. A `.constant` has no real settable storage, so there's nothing to write
        // back into; `body` still re-evaluates (and passes a fresh value) whenever `settings`
        // publishes a change, since it's already observed via `@ObservedObject` above.
        MenuBarExtra(isInserted: .constant(settings.networkSpeedEnabled)) {
            NetworkSpeedGraphView(monitor: appDelegate.networkSpeedMonitor, settings: settings)
        } label: {
            NetworkSpeedMenuBarLabel(imageRenderer: appDelegate.networkSpeedMenuBarImageRenderer)
        }
        .menuBarExtraStyle(.window)

        // Same `.constant(...)` rationale as above - never a two-way binding to a `@Published`
        // property on `isInserted:`.
        MenuBarExtra(isInserted: .constant(settings.claudeUsageEnabled)) {
            ClaudeUsageDropdownView(monitor: appDelegate.claudeUsageMonitor)
        } label: {
            ClaudeUsageMenuBarLabel(imageRenderer: appDelegate.claudeUsageMenuBarImageRenderer)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(settings: settings, clipboardHistoryStore: appDelegate.clipboardHistoryStore)
        }
    }
}
