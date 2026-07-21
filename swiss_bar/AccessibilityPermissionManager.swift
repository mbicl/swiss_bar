//
//  AccessibilityPermissionManager.swift
//  swiss_bar
//

import AppKit
import ApplicationServices
import Combine
import IOKit.hidsystem
import os

/// Abstracts the three TCC trust checks so `AccessibilityPermissionManager`'s edge-trigger logic
/// can be tested without touching real system permission state.
protocol TrustChecking {
    func isProcessTrusted() -> Bool
    func isInputMonitoringGranted() -> Bool
    func isScreenRecordingGranted() -> Bool
}

struct RealTrustChecker: TrustChecking {
    func isProcessTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    func isInputMonitoringGranted() -> Bool {
        IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
    }

    func isScreenRecordingGranted() -> Bool {
        CGPreflightScreenCaptureAccess()
    }
}

/// Three separate TCC gates guard global keyboard interception and window enumeration:
/// Accessibility (required for an active event tap and AX window control), Input Monitoring
/// (checked as a belt-and-braces second gate), and Screen Recording (improves title fidelity for
/// windows on other Spaces that swiss_bar has never held an AX element for, via
/// `CGWindowListCopyWindowInfo`'s `kCGWindowName` - off-Space enumeration itself works without it,
/// falling back to a held AX element or the app name). Polls because there's no notification for
/// TCC grants changing at runtime.
final class AccessibilityPermissionManager: ObservableObject {
    @Published private(set) var isAccessibilityTrusted = false
    @Published private(set) var isInputMonitoringGranted = false
    @Published private(set) var isScreenRecordingGranted = false

    var onAccessibilityGranted: (() -> Void)?

    private static let logger = Logger(subsystem: "com.MBI.swiss-bar", category: "AccessibilityPermissionManager")

    private let trustChecker: TrustChecking
    private var pollTimer: Timer?

    init(trustChecker: TrustChecking = RealTrustChecker()) {
        self.trustChecker = trustChecker
        refresh()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    deinit {
        pollTimer?.invalidate()
    }

    func refresh() {
        let wasTrusted = isAccessibilityTrusted
        let wasInputMonitoringGranted = isInputMonitoringGranted
        let wasScreenRecordingGranted = isScreenRecordingGranted

        isAccessibilityTrusted = trustChecker.isProcessTrusted()
        isInputMonitoringGranted = trustChecker.isInputMonitoringGranted()
        isScreenRecordingGranted = trustChecker.isScreenRecordingGranted()

        if isAccessibilityTrusted != wasTrusted {
            Self.logger.notice("Accessibility trust changed: \(wasTrusted) -> \(self.isAccessibilityTrusted)")
        }
        if isInputMonitoringGranted != wasInputMonitoringGranted {
            Self.logger.notice("Input Monitoring grant changed: \(wasInputMonitoringGranted) -> \(self.isInputMonitoringGranted)")
        }
        if isScreenRecordingGranted != wasScreenRecordingGranted {
            Self.logger.notice("Screen Recording grant changed: \(wasScreenRecordingGranted) -> \(self.isScreenRecordingGranted)")
        }

        if isAccessibilityTrusted && !wasTrusted {
            onAccessibilityGranted?()
        }
    }

    /// Triggers the system prompt (or registers the app so it appears in Settings if the prompt
    /// doesn't render, which happens for ad-hoc/no-Team-signed dev builds). Brings the app to the
    /// foreground first since an `.accessory` app has no window to anchor the system dialog to -
    /// without this the dialog can end up hidden and look like a hang.
    ///
    /// Must run on the main thread: calling it from a background queue crashes
    /// (`EXC_BAD_ACCESS` inside `AXIsProcessTrustedWithOptions` itself).
    func requestAccessibilityAccess() {
        NSApp.activate(ignoringOtherApps: true)
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
        refresh()
    }

    /// `IOHIDRequestAccess` is what actually registers this app in Settings > Privacy & Security >
    /// Input Monitoring - `IOHIDCheckAccess` alone (used by `refresh()`) only reads existing state,
    /// it never causes the app to appear in the list. Kept on the main thread to match
    /// `requestAccessibilityAccess()`, since the sibling AX API crashes off-main.
    func requestInputMonitoringAccess() {
        NSApp.activate(ignoringOtherApps: true)
        _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        refresh()
    }

    /// `CGRequestScreenCaptureAccess` triggers the system prompt (or registers the app in Settings
    /// if already denied once). Unlike the AX/IOHID grants, this one takes effect only after the
    /// app relaunches, so `refresh()` here won't immediately flip to true post-grant.
    func requestScreenRecordingAccess() {
        NSApp.activate(ignoringOtherApps: true)
        _ = CGRequestScreenCaptureAccess()
        refresh()
    }

    func openAccessibilitySettings() {
        openSystemSettings(pane: "Privacy_Accessibility")
    }

    func openInputMonitoringSettings() {
        openSystemSettings(pane: "Privacy_ListenEvent")
    }

    func openScreenRecordingSettings() {
        openSystemSettings(pane: "Privacy_ScreenCapture")
    }

    private func openSystemSettings(pane: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") else { return }
        NSWorkspace.shared.open(url)
    }
}
