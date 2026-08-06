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
/// Group container for this slot. `ClaudeUsageMonitor` pushes fresh data via
/// `WidgetCenter.reloadTimelines(ofKind:)` after every poll that actually changed something, so
/// that's the fast path for updates. Timeline policy is `.after(_:)` rather than `.never`, though,
/// as a self-healing fallback: a push can go undelivered (the widget added before the first poll
/// lands, the host app not running at poll time, the extension process having been evicted) with
/// no way to recover on its own under `.never` - `.after` makes WidgetKit itself re-invoke this
/// provider on a bounded cadence regardless, so a missed push heals within one cycle instead of
/// leaving the widget stuck indefinitely. Staleness is still visible between refreshes because
/// `ClaudeUsageWidgetView` shows `payload.lastUpdated` with `Text(_:style: .relative)`, which
/// self-updates.
struct ClaudeUsageTimelineProvider: TimelineProvider {
    /// Bounds worst-case staleness when a `reloadTimelines` push is missed - well above
    /// `ClaudeUsageMonitor`'s 5-minute poll interval so this scheduled pull doesn't add
    /// meaningful WidgetKit refresh pressure on top of the push path.
    private static let fallbackRefreshInterval: TimeInterval = 15 * 60

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
        let nextRefresh = Date().addingTimeInterval(Self.fallbackRefreshInterval)
        completion(Timeline(entries: [currentEntry()], policy: .after(nextRefresh)))
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
