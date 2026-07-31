//
//  swiss_barWidgetsBundle.swift
//  swiss_barWidgets
//

import WidgetKit
import SwiftUI

@main
struct swiss_barWidgetsBundle: WidgetBundle {
    var body: some Widget {
        AppGroupSpikeWidget()
    }
}

/// Phase 0 spike only - proves the App Group container is readable from this sandboxed extension
/// process, written by the unsandboxed host app. Replaced by the real `ClaudeUsageWidget` in
/// Phase 2 once the signing/entitlements path is confirmed end-to-end (see the plan's Phase 0 gate).
struct AppGroupSpikeWidget: Widget {
    let kind = "AppGroupSpikeWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: AppGroupSpikeProvider()) { entry in
            Text(entry.value)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("swiss_bar spike")
        .description("Temporary: proves App Group data sharing works.")
        .supportedFamilies([.systemSmall])
    }
}

struct AppGroupSpikeEntry: TimelineEntry {
    let date: Date
    let value: String
}

struct AppGroupSpikeProvider: TimelineProvider {
    private static let appGroupID = "group.com.MBI.swiss-bar"
    private static let fileName = "spike-test-string.txt"

    func placeholder(in context: Context) -> AppGroupSpikeEntry {
        AppGroupSpikeEntry(date: Date(), value: "…")
    }

    func getSnapshot(in context: Context, completion: @escaping (AppGroupSpikeEntry) -> Void) {
        completion(AppGroupSpikeEntry(date: Date(), value: readValue() ?? "(no snapshot)"))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<AppGroupSpikeEntry>) -> Void) {
        let entry = AppGroupSpikeEntry(date: Date(), value: readValue() ?? "(container unreadable)")
        completion(Timeline(entries: [entry], policy: .never))
    }

    private func readValue() -> String? {
        guard let dir = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Self.appGroupID) else {
            return nil
        }
        return try? String(contentsOf: dir.appendingPathComponent(Self.fileName), encoding: .utf8)
    }
}
