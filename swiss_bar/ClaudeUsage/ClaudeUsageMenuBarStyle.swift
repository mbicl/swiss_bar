//
//  ClaudeUsageMenuBarStyle.swift
//  swiss_bar
//

import Foundation

/// How the Claude usage status item renders in the menu bar, user-selectable in Settings.
enum ClaudeUsageMenuBarStyle: String, CaseIterable {
    /// Two lines of colored percentage text.
    case numbers
    /// Two small colored progress bars, session on top and weekly on bottom.
    case progressBars

    static let defaultsKey = "claudeUsageMenuBarStyle"

    static var current: ClaudeUsageMenuBarStyle {
        UserDefaults.standard.string(forKey: defaultsKey).flatMap(ClaudeUsageMenuBarStyle.init) ?? .numbers
    }
}
