//
//  ClaudeUsageWidget.swift
//  swiss_barWidgets
//

import SwiftUI
import WidgetKit

/// One static `Widget` per `ClaudeUsageAccountSettings` slot rather than a single
/// `AppIntentConfiguration`-based widget with an in-gallery account picker - see the doc comment
/// on `ClaudeUsageSharedStore.widgetKind(forSlot:)` for why. `Widget` requires a parameterless
/// `init()` (WidgetKit instantiates conforming types itself), so the slot index can't be injected
/// via an initializer parameter the way `ClaudeUsageMonitor` takes `accountID` - each slot needs
/// its own concrete type. The three bodies are identical apart from the slot index; not factored
/// into a shared helper since that's what triggered this doc comment's toolchain issue.
struct ClaudeUsageWidgetSlot0: Widget {
    let kind = ClaudeUsageSharedStore.widgetKind(forSlot: 0)
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ClaudeUsageTimelineProvider(accountID: 0)) { entry in
            ClaudeUsageWidgetView(entry: entry)
        }
        .configurationDisplayName("Claude Usage (Slot 1)")
        .description("Shows session and weekly Claude usage for account slot 1 - configure which account that is in swiss_bar's Settings.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct ClaudeUsageWidgetSlot1: Widget {
    let kind = ClaudeUsageSharedStore.widgetKind(forSlot: 1)
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ClaudeUsageTimelineProvider(accountID: 1)) { entry in
            ClaudeUsageWidgetView(entry: entry)
        }
        .configurationDisplayName("Claude Usage (Slot 2)")
        .description("Shows session and weekly Claude usage for account slot 2 - configure which account that is in swiss_bar's Settings.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct ClaudeUsageWidgetSlot2: Widget {
    let kind = ClaudeUsageSharedStore.widgetKind(forSlot: 2)
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ClaudeUsageTimelineProvider(accountID: 2)) { entry in
            ClaudeUsageWidgetView(entry: entry)
        }
        .configurationDisplayName("Claude Usage (Slot 3)")
        .description("Shows session and weekly Claude usage for account slot 3 - configure which account that is in swiss_bar's Settings.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
