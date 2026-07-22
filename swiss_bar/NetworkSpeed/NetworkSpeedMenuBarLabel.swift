//
//  NetworkSpeedMenuBarLabel.swift
//  swiss_bar
//

import AppKit
import SwiftUI

/// The status-bar label for the network speed `MenuBarExtra` - two lines of small colored text,
/// upload above download. `MenuBarExtra`'s `label:` closure flattens custom `Text` styling (color,
/// multi-line layout) when rendering the status item's button image - a documented limitation -
/// so this pre-renders the styled content to a bitmap via `ImageRenderer` and hands that back
/// instead of live SwiftUI content, which is the standard workaround.
struct NetworkSpeedMenuBarLabel: View {
    @ObservedObject var monitor: NetworkSpeedMonitor
    @ObservedObject var settings: AppSettings

    var body: some View {
        if let image = Self.renderImage(monitor: monitor, settings: settings) {
            Image(nsImage: image)
                .renderingMode(.original)
                .accessibilityLabel(
                    "Upload \(NetworkRateFormatter.string(forBytesPerSecond: monitor.uploadBytesPerSecond)), "
                    + "download \(NetworkRateFormatter.string(forBytesPerSecond: monitor.downloadBytesPerSecond))"
                )
        }
    }

    @MainActor
    private static func renderImage(monitor: NetworkSpeedMonitor, settings: AppSettings) -> NSImage? {
        let renderer = ImageRenderer(content: NetworkSpeedMenuBarLabelContent(monitor: monitor, settings: settings))
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        guard let image = renderer.nsImage else { return nil }
        // The actual flag AppKit's status bar button consults - belt-and-suspenders alongside
        // `.renderingMode(.original)` above, since relying on only one is the kind of thing that
        // silently regresses on an OS point release.
        image.isTemplate = false
        return image
    }
}

/// The actual two-line colored content, pre-rendered to a bitmap by `NetworkSpeedMenuBarLabel`.
/// Fixed frame so the bitmap's pixel size doesn't jump as the unit suffix changes length (e.g.
/// "B/s" -> "KB/s"), which would otherwise shift every menu bar icon to its left each time.
private struct NetworkSpeedMenuBarLabelContent: View {
    @ObservedObject var monitor: NetworkSpeedMonitor
    @ObservedObject var settings: AppSettings

    var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            Text("↑ " + NetworkRateFormatter.string(forBytesPerSecond: monitor.uploadBytesPerSecond))
                .foregroundStyle(settings.networkSpeedUploadColor)
            Text("↓ " + NetworkRateFormatter.string(forBytesPerSecond: monitor.downloadBytesPerSecond))
                .foregroundStyle(settings.networkSpeedDownloadColor)
        }
        .font(.system(size: 9, weight: .medium).monospacedDigit())
        .frame(width: 70, height: 24, alignment: .trailing)
    }
}
