//
//  AccessibilityPermissionManager.swift
//  swiss_bar
//

import AppKit
import ApplicationServices
import Combine
import IOKit.hidsystem

/// Two separate TCC gates guard global keyboard interception: Accessibility (required for an
/// active event tap and AX window control) and Input Monitoring (checked as a belt-and-braces
/// second gate). Polls because there's no notification for TCC grants changing at runtime.
final class AccessibilityPermissionManager: ObservableObject {
    @Published private(set) var isAccessibilityTrusted = false
    @Published private(set) var isInputMonitoringGranted = false

    var onAccessibilityGranted: (() -> Void)?

    private var pollTimer: Timer?

    init() {
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
        isAccessibilityTrusted = AXIsProcessTrusted()
        isInputMonitoringGranted = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted

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
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt: true]
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

    func openAccessibilitySettings() {
        openSystemSettings(pane: "Privacy_Accessibility")
    }

    func openInputMonitoringSettings() {
        openSystemSettings(pane: "Privacy_ListenEvent")
    }

    private func openSystemSettings(pane: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") else { return }
        NSWorkspace.shared.open(url)
    }
}
