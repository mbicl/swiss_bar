//
//  ClaudeUsageSnapshot.swift
//  swiss_bar
//

import Foundation

/// Parsed result of a `claude -p "/usage"` invocation. Reset times are kept as the raw display
/// string (e.g. "Jul 22 at 8:20pm (Asia/Samarkand)") rather than parsed into a `Date` - the source
/// string has no year and nothing here needs countdown math, just display.
struct ClaudeUsageSnapshot {
    let sessionPercent: Int
    /// `nil` when no session is currently active (e.g. right after a reset, before the next
    /// message) - `/usage` then omits the "· resets ..." suffix entirely.
    let sessionResetDescription: String?
    /// "all models" plus any additional per-model line (e.g. a separate Fable 5 line), if present.
    let weeklyLines: [ClaudeUsageWeeklyLine]
    /// `nil` when the "contributing to usage" section fails to parse - kept independent of the
    /// headline percentages so a reworded breakdown section doesn't take those down too.
    let contributing: ClaudeUsageContributing?
}

struct ClaudeUsageWeeklyLine {
    let label: String
    let percent: Int
    let resetDescription: String
}

struct ClaudeUsageContributing {
    let last24h: ClaudeUsagePeriod
    let last7d: ClaudeUsagePeriod
}

struct ClaudeUsagePeriod {
    let requestCount: Int
    let sessionCount: Int
    let subagentHeavyPercent: Int?
    let largeContextPercent: Int?
    /// "X% of your usage came from sessions active for 8+ hours" - only observed in the 7d panel,
    /// so its absence is normal, not a parse failure.
    let longSessionPercent: Int?
    let topSkills: [ClaudeUsageNamedPercent]
    let topSubagents: [ClaudeUsageNamedPercent]
}

struct ClaudeUsageNamedPercent {
    let name: String
    let percent: Int
}
