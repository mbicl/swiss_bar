//
//  WindowPreviewCapturer.swift
//  swiss_bar
//

import AppKit
import CoreGraphics
import ScreenCaptureKit
import os

/// Captures window thumbnails for the horizontal switcher's preview tiles via ScreenCaptureKit
/// (`CGWindowListCreateImage` is removed from the current SDK). Capture is asynchronous: the HUD
/// shows app icons immediately and thumbnails stream in per-window as they complete, so ⌘Tab
/// responsiveness never waits on screenshots. Requires Screen Recording permission, which the
/// window switcher already needs for cross-Space enumeration.
enum WindowPreviewCapturer {

    private static let logger = Logger(subsystem: "com.MBI.swiss-bar", category: "WindowPreviewCapturer")

    /// Captures a thumbnail for each window ID, invoking `onCapture` on the main actor as each
    /// one lands. Windows that can't be captured are silently skipped (their tiles keep the app
    /// icon). Honors task cancellation between captures.
    static func capturePreviews(
        for windowIDs: [CGWindowID],
        onCapture: @escaping @MainActor (CGWindowID, NSImage) -> Void
    ) async {
        guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false) else {
            logger.warning("SCShareableContent unavailable - no previews (Screen Recording not granted?)")
            return
        }

        let wanted = Set(windowIDs)
        var captured = 0
        for window in content.windows where wanted.contains(window.windowID) {
            if Task.isCancelled { return }

            let filter = SCContentFilter(desktopIndependentWindow: window)
            let config = SCStreamConfiguration()
            // 1x (point) resolution - the HUD thumbnails are small, Retina captures are wasted work.
            config.width = Int(window.frame.width)
            config.height = Int(window.frame.height)
            config.showsCursor = false

            guard let cgImage = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config) else {
                continue
            }
            let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
            captured += 1
            await onCapture(window.windowID, image)
        }
        logger.debug("captured \(captured)/\(windowIDs.count) previews")
    }
}
