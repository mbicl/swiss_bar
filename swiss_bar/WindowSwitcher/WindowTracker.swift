//
//  WindowTracker.swift
//  swiss_bar
//

import AppKit
import ApplicationServices
import os

/// Maintains a long-lived cache of AX window elements keyed by `CGWindowID`, populated at window
/// *creation* time via a per-app `AXObserver`. This is the key to activating windows on other
/// Spaces: `kAXWindowsAttribute` only ever lists windows on the currently-displayed Space, so a
/// cache built only during enumeration can never see a window parked on a Space you haven't
/// visited. Grabbing the element the moment the window is created sidesteps that - and a held AX
/// element stays valid and raisable across Space changes.
///
/// Same architecture as alt-tab-macos. Main-actor confined: AXObserver callbacks are delivered on
/// the main run loop, and the cache is read from the main actor during activation.
@MainActor
final class WindowTracker {
    static let shared = WindowTracker()

    private var elements: [CGWindowID: AXUIElement] = [:]
    private var observers: [pid_t: AXObserver] = [:]
    private static let logger = Logger(subsystem: "com.MBI.swiss-bar", category: "WindowTracker")

    private init() {}

    /// Begins tracking every regular running app and any that launch later. Idempotent.
    func start() {
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            observe(app)
        }

        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector: #selector(appLaunched(_:)), name: NSWorkspace.didLaunchApplicationNotification, object: nil)
        center.addObserver(self, selector: #selector(appTerminated(_:)), name: NSWorkspace.didTerminateApplicationNotification, object: nil)
    }

    /// The cached AX element for a window ID, if one has been captured.
    func element(for windowID: CGWindowID) -> AXUIElement? {
        elements[windowID]
    }

    @objc private func appLaunched(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              app.activationPolicy == .regular else { return }
        observe(app)
    }

    @objc private func appTerminated(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        observers[app.processIdentifier] = nil
    }

    private func observe(_ app: NSRunningApplication) {
        let pid = app.processIdentifier
        guard observers[pid] == nil else { return }

        var observer: AXObserver?
        let callback: AXObserverCallback = { _, element, _, refcon in
            guard let refcon else { return }
            let tracker = Unmanaged<WindowTracker>.fromOpaque(refcon).takeUnretainedValue()
            MainActor.assumeIsolated {
                tracker.cache(element)
            }
        }
        guard AXObserverCreate(pid, callback, &observer) == .success, let observer else { return }

        let appElement = AXUIElementCreateApplication(pid)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        AXObserverAddNotification(observer, appElement, kAXWindowCreatedNotification as CFString, refcon)
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        observers[pid] = observer

        // Seed with whatever is AX-visible right now (windows on the current Space) so we don't
        // wait for them to be recreated.
        cacheExistingWindows(of: pid)
    }

    private func cacheExistingWindows(of pid: pid_t) {
        guard let axWindows = WindowEnumerator.axWindows(for: pid) else { return }
        for axWindow in axWindows where WindowEnumerator.axString(axWindow, kAXRoleAttribute) == kAXWindowRole {
            cache(axWindow)
        }
    }

    private func cache(_ element: AXUIElement) {
        guard WindowEnumerator.axString(element, kAXRoleAttribute) == kAXWindowRole,
              let windowID = WindowEnumerator.windowID(of: element) else { return }
        elements[windowID] = element
    }
}
