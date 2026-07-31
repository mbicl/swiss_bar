//
//  ClaudeUsageWidgetView.swift
//  swiss_barWidgets
//

import SwiftUI
import WidgetKit

struct ClaudeUsageWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ClaudeUsageEntry

    var body: some View {
        content
            .containerBackground(.fill.tertiary, for: .widget)
    }

    @ViewBuilder
    private var content: some View {
        if let payload = entry.payload, let snapshot = payload.snapshot {
            switch family {
            case .systemSmall:
                smallView(snapshot: snapshot, payload: payload)
            default:
                mediumView(snapshot: snapshot, payload: payload)
            }
        } else {
            messageView("Open swiss_bar and enable account slot \(entry.accountID + 1) in Settings.")
        }
    }

    private func messageView(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func smallView(snapshot: ClaudeUsageSnapshot, payload: ClaudeUsageWidgetAccountPayload) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if !payload.displayName.isEmpty {
                Text(payload.displayName)
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Text("Session")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("\(snapshot.sessionPercent)%")
                .font(.system(size: 34, weight: .semibold, design: .rounded))
                .foregroundStyle(ClaudeUsageThreshold.severity(forPercent: snapshot.sessionPercent).color)
            Spacer()
            lastUpdated(payload.lastUpdated)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func mediumView(snapshot: ClaudeUsageSnapshot, payload: ClaudeUsageWidgetAccountPayload) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if !payload.displayName.isEmpty {
                Text(payload.displayName)
                    .font(.headline)
            }
            row(label: "Session", percent: snapshot.sessionPercent, resetDescription: snapshot.sessionResetDescription)
            ForEach(Array(snapshot.weeklyLines.enumerated()), id: \.offset) { _, line in
                row(label: "Week (\(line.label))", percent: line.percent, resetDescription: line.resetDescription)
            }
            Spacer(minLength: 0)
            lastUpdated(payload.lastUpdated)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row(label: String, percent: Int, resetDescription: String?) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack {
                Text(label).font(.subheadline)
                Spacer()
                Text("\(percent)%")
                    .font(.subheadline.bold())
                    .foregroundStyle(ClaudeUsageThreshold.severity(forPercent: percent).color)
            }
            Text(resetDescription.map { "Resets \($0)" } ?? "No active session yet")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func lastUpdated(_ date: Date) -> some View {
        Text("Updated \(date, style: .relative) ago")
            .font(.caption2)
            .foregroundStyle(.secondary)
    }
}
