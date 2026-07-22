//
//  ClaudeUsageDropdownView.swift
//  swiss_bar
//

import SwiftUI

/// The Claude usage `MenuBarExtra`'s dropdown content - session/weekly percentages and reset
/// times, plus the full "contributing to usage" breakdown exactly as `claude -p "/usage"` reports
/// it. Weekly usage is always shown here regardless of the menu-bar-only "show weekly" setting.
struct ClaudeUsageDropdownView: View {
    @ObservedObject var monitor: ClaudeUsageMonitor

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let snapshot = monitor.snapshot {
                    headline(snapshot: snapshot)
                    if let contributing = snapshot.contributing {
                        Divider()
                        periodSection(title: "Last 24h", period: contributing.last24h)
                        Divider()
                        periodSection(title: "Last 7d", period: contributing.last7d)
                    } else {
                        Text("Usage breakdown unavailable.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("Claude usage unavailable. Confirm the Claude Code CLI command in Settings.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
        }
        .frame(width: 320, height: 380)
    }

    private func headline(snapshot: ClaudeUsageSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            row(label: "Session", percent: snapshot.sessionPercent, resetDescription: snapshot.sessionResetDescription)
            ForEach(Array(snapshot.weeklyLines.enumerated()), id: \.offset) { _, line in
                row(label: "Week (\(line.label))", percent: line.percent, resetDescription: line.resetDescription)
            }
        }
    }

    private func row(label: String, percent: Int, resetDescription: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack {
                Text(label).font(.headline)
                Spacer()
                Text("\(percent)%")
                    .font(.headline).bold()
                    .foregroundStyle(ClaudeUsageThreshold.severity(forPercent: percent).color)
            }
            Text("Resets \(resetDescription)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func periodSection(title: String, period: ClaudeUsagePeriod) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.subheadline).bold()
            Text("\(period.requestCount) requests · \(period.sessionCount) sessions")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let subagentHeavyPercent = period.subagentHeavyPercent {
                Text("\(subagentHeavyPercent)% from subagent-heavy sessions").font(.caption)
            }
            if let largeContextPercent = period.largeContextPercent {
                Text("\(largeContextPercent)% at >150k context").font(.caption)
            }
            if let longSessionPercent = period.longSessionPercent {
                Text("\(longSessionPercent)% from sessions active 8+ hours").font(.caption)
            }
            if !period.topSkills.isEmpty {
                Text("Top skills: \(namedPercentList(period.topSkills))").font(.caption)
            }
            if !period.topSubagents.isEmpty {
                Text("Top subagents: \(namedPercentList(period.topSubagents))").font(.caption)
            }
        }
    }

    private func namedPercentList(_ items: [ClaudeUsageNamedPercent]) -> String {
        items.map { "\($0.name) \($0.percent)%" }.joined(separator: ", ")
    }
}
