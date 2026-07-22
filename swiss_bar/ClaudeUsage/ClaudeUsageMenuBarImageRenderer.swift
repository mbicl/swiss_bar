//
//  ClaudeUsageMenuBarImageRenderer.swift
//  swiss_bar
//

import AppKit
import Combine
import SwiftUI

/// Pre-renders the menu bar's Claude usage label to a bitmap whenever the snapshot or configured
/// display settings change, so `ClaudeUsageMenuBarLabel`'s `body` only ever displays an
/// already-rendered `NSImage` rather than calling `ImageRenderer` itself.
///
/// This split exists because calling `ImageRenderer` synchronously from inside a live SwiftUI
/// `View.body` re-enters the same view-graph update machinery that's already mid-update to
/// evaluate that very `body` - confirmed via a real freeze sample (see
/// `NetworkSpeedMenuBarImageRenderer`) to spin forever inside `ImageRendererHost.renderUntilStable()`,
/// pegging the main thread and freezing the whole app. Rendering here instead, from a Combine
/// `sink` driven by `ClaudeUsageMonitor`'s timer tick, happens on a separate call stack that isn't
/// nested inside any view update, which avoids the reentrant deadlock.
@MainActor
final class ClaudeUsageMenuBarImageRenderer: ObservableObject {
    @Published private(set) var image: NSImage?
    @Published private(set) var accessibilityDescription: String = ""

    private var cancellable: AnyCancellable?

    init(monitor: ClaudeUsageMonitor, settings: AppSettings) {
        cancellable = Publishers.CombineLatest3(
            monitor.$snapshot,
            settings.$claudeUsageMenuBarStyle,
            settings.$claudeUsageShowWeeklyInMenuBar
        )
        .sink { [weak self] snapshot, style, showWeekly in
            self?.render(snapshot: snapshot, style: style, showWeekly: showWeekly)
        }
    }

    private func render(snapshot: ClaudeUsageSnapshot?, style: ClaudeUsageMenuBarStyle, showWeekly: Bool) {
        guard let snapshot else {
            image = nil
            accessibilityDescription = "Claude usage unavailable"
            return
        }

        let weeklyPercent = snapshot.weeklyLines.first(where: { $0.label.lowercased() == "all models" })?.percent
            ?? snapshot.weeklyLines.first?.percent
        let displayedWeeklyPercent = showWeekly ? weeklyPercent : nil

        let content: AnyView
        switch style {
        case .numbers:
            content = AnyView(ClaudeUsageMenuBarNumbersContent(sessionPercent: snapshot.sessionPercent, weeklyPercent: displayedWeeklyPercent))
        case .progressBars:
            content = AnyView(ClaudeUsageMenuBarProgressBarsContent(sessionPercent: snapshot.sessionPercent, weeklyPercent: displayedWeeklyPercent))
        }

        let renderer = ImageRenderer(content: content)
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        guard let nsImage = renderer.nsImage else { return }
        // The actual flag AppKit's status bar button consults - belt-and-suspenders alongside
        // `.renderingMode(.original)` on the `Image` that displays it.
        nsImage.isTemplate = false
        image = nsImage

        var description = "Claude session usage \(snapshot.sessionPercent) percent"
        if let displayedWeeklyPercent {
            description += ", weekly usage \(displayedWeeklyPercent) percent"
        }
        accessibilityDescription = description
    }
}

extension ClaudeUsageSeverity {
    var color: Color {
        switch self {
        case .good: return .green
        case .warning: return .yellow
        case .critical: return .red
        }
    }
}

/// Two lines of colored percentage text. Fixed frame so the bitmap's pixel size doesn't jump as
/// digit widths change - matches `NetworkSpeedMenuBarLabelContent`'s convention.
struct ClaudeUsageMenuBarNumbersContent: View {
    let sessionPercent: Int
    let weeklyPercent: Int?

    var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            Text("Session \(sessionPercent)%")
                .foregroundStyle(ClaudeUsageThreshold.severity(forPercent: sessionPercent).color)
            if let weeklyPercent {
                Text("Week \(weeklyPercent)%")
                    .foregroundStyle(ClaudeUsageThreshold.severity(forPercent: weeklyPercent).color)
            }
        }
        .font(.system(size: 9, weight: .medium).monospacedDigit())
        .frame(width: 74, height: 24, alignment: .trailing)
    }
}

/// Two small horizontal progress bars, session on top and weekly on bottom (weekly omitted when
/// hidden via Settings).
struct ClaudeUsageMenuBarProgressBarsContent: View {
    let sessionPercent: Int
    let weeklyPercent: Int?

    private static let barWidth: CGFloat = 40
    private static let barHeight: CGFloat = 6

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            bar(percent: sessionPercent)
            if let weeklyPercent {
                bar(percent: weeklyPercent)
            }
        }
        .frame(width: Self.barWidth, height: 24, alignment: .center)
    }

    private func bar(percent: Int) -> some View {
        let clamped = min(max(percent, 0), 100)
        let color = ClaudeUsageThreshold.severity(forPercent: percent).color
        return ZStack(alignment: .leading) {
            Capsule().fill(Color.gray.opacity(0.3))
            Capsule().fill(color)
                .frame(width: Self.barWidth * CGFloat(clamped) / 100)
        }
        .frame(width: Self.barWidth, height: Self.barHeight)
    }
}
