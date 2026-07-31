//
//  ClaudeUsageTimelineProvider.swift
//  swiss_barWidgets
//

import WidgetKit

struct ClaudeUsageEntry: TimelineEntry {
    let date: Date
    let accountID: Int
    let payload: ClaudeUsageWidgetAccountPayload?
}

/// A plain `TimelineProvider` (not `AppIntentTimelineProvider`) - see the doc comment on
/// `ClaudeUsageSharedStore.widgetKind(forSlot:)` for why this widget is one static type per
/// account slot rather than a single `AppIntentConfiguration`-based widget with an in-gallery
/// picker.
///
/// This widget never polls the Claude CLI itself (sandboxed extensions can't reliably spawn it);
/// it only renders whatever `ClaudeUsageMonitor` (running in the host app) last wrote to the App
/// Group container for this slot. Timeline policy is `.never` - `ClaudeUsageMonitor` pushes fresh
/// data via `WidgetCenter.reloadTimelines(ofKind:)` after every poll that actually changed
/// something, and a periodic reload here would just re-render unchanged data against WidgetKit's
/// reload budget for no benefit. Staleness is still visible with zero reloads because
/// `ClaudeUsageWidgetView` shows `payload.lastUpdated` with `Text(_:style: .relative)`, which
/// self-updates.
struct ClaudeUsageTimelineProvider: TimelineProvider {
    let accountID: Int

    func placeholder(in context: Context) -> ClaudeUsageEntry {
        ClaudeUsageEntry(date: Date(), accountID: accountID, payload: Self.samplePayload(accountID: accountID))
    }

    func getSnapshot(in context: Context, completion: @escaping (ClaudeUsageEntry) -> Void) {
        // The gallery preview shows sample data rather than "never polled yet" - a blank/error
        // state there reads as broken, not as "add this widget".
        completion(context.isPreview ? placeholder(in: context) : currentEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ClaudeUsageEntry>) -> Void) {
        completion(Timeline(entries: [currentEntry()], policy: .never))
    }

    private func currentEntry() -> ClaudeUsageEntry {
        let payload = ClaudeUsageSharedStore().readAll().first { $0.id == accountID }
        return ClaudeUsageEntry(date: Date(), accountID: accountID, payload: payload)
    }

    private static func samplePayload(accountID: Int) -> ClaudeUsageWidgetAccountPayload {
        ClaudeUsageWidgetAccountPayload(
            id: accountID,
            displayName: "Claude",
            snapshot: ClaudeUsageSnapshot(
                sessionPercent: 42,
                sessionResetDescription: "5pm",
                weeklyLines: [ClaudeUsageWeeklyLine(label: "all models", percent: 18, resetDescription: "Monday")],
                contributing: nil
            ),
            lastUpdated: Date()
        )
    }
}
