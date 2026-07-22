//
//  ClaudeUsageParser.swift
//  swiss_bar
//

import Foundation

/// Parses the prose output of `claude -p "/usage"` into a `ClaudeUsageSnapshot`.
///
/// This is undocumented CLI prose, not a stable API - Anthropic could reword it in any Claude
/// Code update and silently break these patterns. Parsing is deliberately line-by-line (not one
/// giant multi-line regex) and every field beyond the two headline percentages is independently
/// optional, so a reworded "contributing to usage" section degrades to a missing breakdown rather
/// than losing the headline numbers or crashing.
enum ClaudeUsageParser {
    nonisolated private static let sessionRegex = try! NSRegularExpression(
        pattern: #"^Current session:\s*(\d+)%\s*used\s*·\s*resets\s*(.+)$"#
    )
    nonisolated private static let weeklyRegex = try! NSRegularExpression(
        pattern: #"^Current week \(([^)]+)\):\s*(\d+)%\s*used\s*·\s*resets\s*(.+)$"#
    )
    nonisolated private static let periodHeaderRegex = try! NSRegularExpression(
        pattern: #"^Last (24h|7d)\s*·\s*(\d+)\s*requests?\s*·\s*(\d+)\s*sessions?$"#
    )
    nonisolated private static let subagentHeavyRegex = try! NSRegularExpression(
        pattern: #"^(\d+)%\s*of your usage came from subagent-heavy sessions$"#
    )
    nonisolated private static let largeContextRegex = try! NSRegularExpression(
        pattern: #"^(\d+)%\s*of your usage was at >150k context$"#
    )
    nonisolated private static let longSessionRegex = try! NSRegularExpression(
        pattern: #"^(\d+)%\s*of your usage came from sessions active for 8\+ hours$"#
    )
    nonisolated private static let topSkillsRegex = try! NSRegularExpression(pattern: #"^Top skills:\s*(.+)$"#)
    nonisolated private static let topSubagentsRegex = try! NSRegularExpression(pattern: #"^Top subagents:\s*(.+)$"#)
    nonisolated private static let namedPercentRegex = try! NSRegularExpression(pattern: #"^(\S+)\s+(\d+)%$"#)

    nonisolated static func parse(_ raw: String) -> ClaudeUsageSnapshot? {
        let lines = raw.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }

        var sessionPercent: Int?
        var sessionReset: String?
        var weeklyLines: [ClaudeUsageWeeklyLine] = []
        var periods: [String: PeriodBuilder] = [:]
        var currentPeriodKey: String?

        for line in lines {
            if let match = firstMatch(sessionRegex, in: line) {
                sessionPercent = Int(match.group(1, in: line))
                sessionReset = match.group(2, in: line)
                continue
            }
            if let match = firstMatch(weeklyRegex, in: line) {
                let label = match.group(1, in: line)
                guard let percent = Int(match.group(2, in: line)) else { continue }
                weeklyLines.append(ClaudeUsageWeeklyLine(label: label, percent: percent, resetDescription: match.group(3, in: line)))
                continue
            }
            if let match = firstMatch(periodHeaderRegex, in: line) {
                let key = match.group(1, in: line)
                let requestCount = Int(match.group(2, in: line)) ?? 0
                let sessionCount = Int(match.group(3, in: line)) ?? 0
                periods[key] = PeriodBuilder(requestCount: requestCount, sessionCount: sessionCount)
                currentPeriodKey = key
                continue
            }
            guard let key = currentPeriodKey else { continue }
            if let match = firstMatch(subagentHeavyRegex, in: line) {
                periods[key]?.subagentHeavyPercent = Int(match.group(1, in: line))
            } else if let match = firstMatch(largeContextRegex, in: line) {
                periods[key]?.largeContextPercent = Int(match.group(1, in: line))
            } else if let match = firstMatch(longSessionRegex, in: line) {
                periods[key]?.longSessionPercent = Int(match.group(1, in: line))
            } else if let match = firstMatch(topSkillsRegex, in: line) {
                periods[key]?.topSkills = parseNamedPercents(match.group(1, in: line))
            } else if let match = firstMatch(topSubagentsRegex, in: line) {
                periods[key]?.topSubagents = parseNamedPercents(match.group(1, in: line))
            }
        }

        guard let sessionPercent, let sessionReset, !weeklyLines.isEmpty else { return nil }

        var contributing: ClaudeUsageContributing?
        if let last24h = periods["24h"]?.build(), let last7d = periods["7d"]?.build() {
            contributing = ClaudeUsageContributing(last24h: last24h, last7d: last7d)
        }

        return ClaudeUsageSnapshot(
            sessionPercent: sessionPercent,
            sessionResetDescription: sessionReset,
            weeklyLines: weeklyLines,
            contributing: contributing
        )
    }

    nonisolated private static func parseNamedPercents(_ raw: String) -> [ClaudeUsageNamedPercent] {
        raw.components(separatedBy: ",").compactMap { entry in
            let trimmed = entry.trimmingCharacters(in: .whitespaces)
            guard let match = firstMatch(namedPercentRegex, in: trimmed), let percent = Int(match.group(2, in: trimmed)) else {
                return nil
            }
            return ClaudeUsageNamedPercent(name: match.group(1, in: trimmed), percent: percent)
        }
    }

    nonisolated private static func firstMatch(_ regex: NSRegularExpression, in line: String) -> NSTextCheckingResult? {
        regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line))
    }

    private struct PeriodBuilder {
        let requestCount: Int
        let sessionCount: Int
        var subagentHeavyPercent: Int?
        var largeContextPercent: Int?
        var longSessionPercent: Int?
        var topSkills: [ClaudeUsageNamedPercent] = []
        var topSubagents: [ClaudeUsageNamedPercent] = []

        nonisolated func build() -> ClaudeUsagePeriod {
            ClaudeUsagePeriod(
                requestCount: requestCount,
                sessionCount: sessionCount,
                subagentHeavyPercent: subagentHeavyPercent,
                largeContextPercent: largeContextPercent,
                longSessionPercent: longSessionPercent,
                topSkills: topSkills,
                topSubagents: topSubagents
            )
        }
    }
}

private extension NSTextCheckingResult {
    nonisolated func group(_ index: Int, in string: String) -> String {
        guard let range = Range(self.range(at: index), in: string) else { return "" }
        return String(string[range])
    }
}
