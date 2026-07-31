//
//  ClaudeUsageAccountSettings.swift
//  swiss_bar
//

import Foundation

/// One Claude usage menu bar indicator's configuration - up to `slotCount` of these are stored as
/// a fixed-size array in `AppSettings.claudeUsageAccounts`, one per independent status item.
struct ClaudeUsageAccountSettings: Codable, Identifiable, Equatable {
    /// Stable slot index (0, 1, 2) - never reordered, since `id` also drives which
    /// `ClaudeUsageMonitor`/`MenuBarExtra`/Settings section an element corresponds to.
    var id: Int
    var enabled: Bool = false
    /// Short label shown in the menu bar and dropdown to distinguish accounts (e.g. "Work",
    /// "Home"). Empty renders identically to the pre-multi-account single indicator.
    var displayName: String = ""
    var cliCommand: String = "claude"
    var menuBarStyle: ClaudeUsageMenuBarStyle = .numbers
    var showWeeklyInMenuBar: Bool = true

    /// Single source of truth for how many indicators exist - `swiss_barApp.swift` still declares
    /// this many `MenuBarExtra` scenes by hand (SwiftUI scenes can't be built from a dynamic
    /// `ForEach`), so changing this alone is not sufficient to add a 4th slot.
    static let slotCount = 3

    static func defaults() -> [ClaudeUsageAccountSettings] {
        (0..<slotCount).map { ClaudeUsageAccountSettings(id: $0) }
    }
}
