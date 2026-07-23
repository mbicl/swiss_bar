//
//  NetworkSpeedMenuBarImageRenderer.swift
//  swiss_bar
//

import AppKit
import Combine
import SwiftUI

/// Pre-renders the menu bar's two-line colored upload/download text to a bitmap whenever the rate
/// or configured colors change, so `NetworkSpeedMenuBarLabel`'s `body` only ever displays an
/// already-rendered `NSImage` rather than calling `ImageRenderer` itself.
///
/// This split exists because calling `ImageRenderer` synchronously from inside a live SwiftUI
/// `View.body` re-enters the same view-graph update machinery that's already mid-update to
/// evaluate that very `body` - confirmed via a real freeze sample to spin forever inside
/// `ImageRendererHost.renderUntilStable()`, pegging the main thread and freezing the whole app
/// (not just this dropdown, since the main run loop never returns). Rendering here instead, from a
/// Combine `sink` driven by `NetworkSpeedMonitor`'s timer tick, happens on a separate call stack
/// that isn't nested inside any view update, which avoids the reentrant deadlock.
@MainActor
final class NetworkSpeedMenuBarImageRenderer: ObservableObject {
    @Published private(set) var image: NSImage?
    @Published private(set) var accessibilityDescription: String = ""

    private var cancellable: AnyCancellable?
    /// Skips re-rendering (and re-rastering via `ImageRenderer`) when nothing actually changed -
    /// an idle connection otherwise re-renders an identical "0 B/s"/"0 B/s" bitmap every second,
    /// forever, on the main thread of a background app.
    private var lastRenderKey: String?

    init(monitor: NetworkSpeedMonitor, settings: AppSettings) {
        cancellable = Publishers.CombineLatest4(
            monitor.$uploadBytesPerSecond,
            monitor.$downloadBytesPerSecond,
            settings.$networkSpeedUploadColor,
            settings.$networkSpeedDownloadColor
        )
        .sink { [weak self] upload, download, uploadColor, downloadColor in
            self?.render(upload: upload, download: download, uploadColor: uploadColor, downloadColor: downloadColor)
        }
    }

    private func render(upload: Double, download: Double, uploadColor: Color, downloadColor: Color) {
        let uploadText = "↑ " + NetworkRateFormatter.string(forBytesPerSecond: upload)
        let downloadText = "↓ " + NetworkRateFormatter.string(forBytesPerSecond: download)

        let key = "\(uploadText)|\(downloadText)|\(uploadColor)|\(downloadColor)"
        guard key != lastRenderKey else { return }

        let content = NetworkSpeedMenuBarLabelContent(
            uploadText: uploadText, downloadText: downloadText,
            uploadColor: uploadColor, downloadColor: downloadColor
        )
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
        accessibilityDescription = "Upload \(uploadText.dropFirst(2)), download \(downloadText.dropFirst(2))"
        lastRenderKey = key
    }
}

/// The actual two-line colored content, rendered to a bitmap by `NetworkSpeedMenuBarImageRenderer`.
/// Fixed frame so the bitmap's pixel size doesn't jump as the unit suffix changes length (e.g.
/// "B/s" -> "KB/s"), which would otherwise shift every menu bar icon to its left each time.
struct NetworkSpeedMenuBarLabelContent: View {
    let uploadText: String
    let downloadText: String
    let uploadColor: Color
    let downloadColor: Color

    var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            Text(uploadText).foregroundStyle(uploadColor)
            Text(downloadText).foregroundStyle(downloadColor)
        }
        .font(.system(size: 9, weight: .medium).monospacedDigit())
        .frame(width: 70, height: 24, alignment: .trailing)
    }
}
