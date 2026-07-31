//
//  ClaudeUsageMenuBarStyle.swift
//  swiss_bar
//

import Foundation

/// How the Claude usage status item renders in the menu bar, user-selectable in Settings.
enum ClaudeUsageMenuBarStyle: String, CaseIterable, Codable {
    /// Two lines of colored percentage text.
    case numbers
    /// Two small colored progress bars, session on top and weekly on bottom.
    case progressBars

    /// Kept only for `AppSettings`' one-time migration off the old single-account flat key -
    /// current storage is per-account, nested inside `AppSettings.claudeUsageAccounts`.
    static let defaultsKey = "claudeUsageMenuBarStyle"
}
