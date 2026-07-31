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
    /// Skips re-rendering (and re-rastering via `ImageRenderer`) when nothing actually changed -
    /// see `NetworkSpeedMenuBarImageRenderer.lastRenderKey` for why this matters even at a slow
    /// (5-minute) poll cadence: every settings change re-publishes the same snapshot too. Includes
    /// `displayName` - omitting it would mean renaming an account never repaints its menu bar item.
    private var lastRenderKey: String?

    init(monitor: ClaudeUsageMonitor, settings: AppSettings, accountID: Int) {
        cancellable = Publishers.CombineLatest(monitor.$snapshot, settings.$claudeUsageAccounts)
            .sink { [weak self, accountID] snapshot, accounts in
                // Reads the *emitted* array, not `settings.claudeUsageAccounts` - `@Published`
                // fires from `willSet`, so the stored property would still show the old value.
                guard accounts.indices.contains(accountID) else { return }
                let account = accounts[accountID]
                self?.render(snapshot: snapshot, style: account.menuBarStyle, showWeekly: account.showWeeklyInMenuBar, displayName: account.displayName)
            }
    }

    private func render(snapshot: ClaudeUsageSnapshot?, style: ClaudeUsageMenuBarStyle, showWeekly: Bool, displayName: String) {
        guard let snapshot else {
            image = nil
            accessibilityDescription = displayName.isEmpty ? "Claude usage unavailable" : "\(displayName) Claude usage unavailable"
            lastRenderKey = nil
            return
        }

        let weeklyPercent = snapshot.weeklyLines.first(where: { $0.label.lowercased() == "all models" })?.percent
            ?? snapshot.weeklyLines.first?.percent
        let displayedWeeklyPercent = showWeekly ? weeklyPercent : nil

        let key = "\(snapshot.sessionPercent)|\(String(describing: displayedWeeklyPercent))|\(style.rawValue)|\(displayName)"
        guard key != lastRenderKey else { return }

        let content: AnyView
        switch style {
        case .numbers:
            content = AnyView(ClaudeUsageMenuBarNumbersContent(sessionPercent: snapshot.sessionPercent, weeklyPercent: displayedWeeklyPercent, label: displayName))
        case .progressBars:
            content = AnyView(ClaudeUsageMenuBarProgressBarsContent(sessionPercent: snapshot.sessionPercent, weeklyPercent: displayedWeeklyPercent, label: displayName))
        }

        let renderer = ImageRenderer(content: content)
        // NSScreen.main follows the key window, which this LSUIElement app rarely has - it can
        // silently fall back to the primary display, rendering blurry/oversized on a secondary
        // display with a different scale factor. Render at the sharpest display's scale; AppKit
        // downsamples cleanly for lower-DPI displays.
        renderer.scale = NSScreen.screens.map(\.backingScaleFactor).max() ?? 2
        guard let nsImage = renderer.nsImage else { return }
        // The actual flag AppKit's status bar button consults - belt-and-suspenders alongside
        // `.renderingMode(.original)` on the `Image` that displays it.
        nsImage.isTemplate = false
        image = nsImage

        var description = displayName.isEmpty ? "Claude" : displayName
        description += " session usage \(snapshot.sessionPercent) percent"
        if let displayedWeeklyPercent {
            description += ", weekly usage \(displayedWeeklyPercent) percent"
        }
        accessibilityDescription = description
        lastRenderKey = key
    }
}

/// A short leading label column distinguishing one account's status item from another's -
/// occupies a fixed-width slot so the two content types below stay pixel-identical to their
/// pre-multi-account layout when `label` is empty (the common single-account case), rather than
/// growing a 3rd stacked line into the already-tight 24pt-tall menu bar.
private struct ClaudeUsageMenuBarAccountLabel: View {
    let label: String

    var body: some View {
        if !label.isEmpty {
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: 30, height: 24, alignment: .leading)
        }
    }
}

/// Two lines of colored percentage text. Fixed frame so the bitmap's pixel size doesn't jump as
/// digit widths change - matches `NetworkSpeedMenuBarLabelContent`'s convention.
struct ClaudeUsageMenuBarNumbersContent: View {
    let sessionPercent: Int
    let weeklyPercent: Int?
    var label: String = ""

    var body: some View {
        HStack(spacing: 3) {
            ClaudeUsageMenuBarAccountLabel(label: label)
            VStack(alignment: .trailing, spacing: 0) {
                Text("Session \(sessionPercent)%")
                    .foregroundStyle(ClaudeUsageThreshold.severity(forPercent: sessionPercent).color)
                if let weeklyPercent {
                    Text("Week \(weeklyPercent)%")
                        .foregroundStyle(ClaudeUsageThreshold.severity(forPercent: weeklyPercent).color)
                }
            }
            .frame(width: 74, height: 24, alignment: .trailing)
        }
        .font(.system(size: 9, weight: .medium).monospacedDigit())
    }
}

/// Two small horizontal progress bars, session on top and weekly on bottom (weekly omitted when
/// hidden via Settings).
struct ClaudeUsageMenuBarProgressBarsContent: View {
    let sessionPercent: Int
    let weeklyPercent: Int?
    var label: String = ""

    private static let barWidth: CGFloat = 40
    private static let barHeight: CGFloat = 6

    var body: some View {
        HStack(spacing: 3) {
            ClaudeUsageMenuBarAccountLabel(label: label)
            VStack(alignment: .leading, spacing: 3) {
                bar(percent: sessionPercent)
                if let weeklyPercent {
                    bar(percent: weeklyPercent)
                }
            }
            .frame(width: Self.barWidth, height: 24, alignment: .center)
        }
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
