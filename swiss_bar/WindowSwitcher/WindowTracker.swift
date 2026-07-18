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
    private var runLoopSources: [pid_t: CFRunLoopSource] = [:]

    /// Most-recently-focused window IDs, front = most recent. Populated only by real focus
    /// events (window created, window focused within an app, app activated) - never inferred
    /// from Quartz z-order, which is ambiguous once two windows of the same app have near-
    /// identical bounds (e.g. two maximized windows), causing the switcher list to visibly
    /// reorder itself at random. Promoting only the one window that actually changed focus
    /// keeps every other window's relative order untouched, matching what a switcher list is
    /// expected to do.
    private var mruOrder: [CGWindowID] = []

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
        center.addObserver(self, selector: #selector(appActivated(_:)), name: NSWorkspace.didActivateApplicationNotification, object: nil)
    }

    /// The cached AX element for a window ID, if one has been captured.
    func element(for windowID: CGWindowID) -> AXUIElement? {
        elements[windowID]
    }

    /// The current MRU order, most-recent first. Windows never seen by a focus/creation/app-
    /// activation notification (e.g. right after launch, before the user has done anything)
    /// simply aren't present - callers fall back to another ordering for those.
    func mruOrderSnapshot() -> [CGWindowID] {
        mruOrder
    }

    /// Explicitly promotes a window the switcher just activated to the front of the MRU order.
    /// Doesn't rely on the async system notifications (app activation, AX focus-changed) that
    /// would normally do this shortly afterward - keeps the very next switcher invocation
    /// accurate even if those haven't landed yet.
    func markFocused(_ windowID: CGWindowID) {
        promote(windowID)
    }

    /// Backfills the MRU order with any of `ids` (front-to-back Quartz z-order) not already
    /// present, appended after the existing MRU-known windows in that same relative order -
    /// never reorders entries the MRU order already has real focus history for. Without this,
    /// every window is unranked right after launch (before any focus event has fired), so the
    /// very first switcher invocation of a session falls back to the ambiguous bounds-matching
    /// z-order heuristic that caused the original "list reorders at random" symptom whenever two
    /// windows of the same app share near-identical bounds. Call with
    /// `WindowEnumerator.onScreenWindowIDsFrontToBack()` at launch and on every Space change.
    func seedMRU(_ ids: [CGWindowID]) {
        var known = Set(mruOrder)
        for id in ids where !known.contains(id) {
            mruOrder.append(id)
            known.insert(id)
        }
    }

    /// Drops cached elements for windows that no longer exist anywhere on the system. Without
    /// this, closed windows' elements (and their possibly-recycled `CGWindowID`s) linger forever
    /// and can be preferred over fresher state during activation. No-op if the live ID lookup
    /// comes back empty (transient Quartz failure), matching `WindowEnumerator`'s cache pruning.
    func prune() {
        let liveIDs = WindowEnumerator.allWindowIDs()
        guard !liveIDs.isEmpty else { return }
        elements = elements.filter { liveIDs.contains($0.key) }
        mruOrder.removeAll { !liveIDs.contains($0) }
    }

    @objc private func appLaunched(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              app.activationPolicy == .regular else { return }
        observe(app)
    }

    @objc private func appTerminated(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        let pid = app.processIdentifier
        if let source = runLoopSources[pid] {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .defaultMode)
        }
        runLoopSources[pid] = nil
        observers[pid] = nil
    }

    /// Catches app-level activation (Dock click, macOS's own Cmd+Tab, etc.) that doesn't
    /// necessarily fire `kAXFocusedWindowChangedNotification` on the newly-front app (that
    /// notification is about focus changing *within* an already-active app). Promotes whichever
    /// window the app itself currently considers focused.
    @objc private func appActivated(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              app.activationPolicy == .regular else { return }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(appElement, 0.25)
        var focusedWindow: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &focusedWindow) == .success,
              let focusedWindow else { return }
        handleWindowNotification(focusedWindow as! AXUIElement)
    }

    private func observe(_ app: NSRunningApplication) {
        let pid = app.processIdentifier
        guard observers[pid] == nil else { return }

        var observer: AXObserver?
        let callback: AXObserverCallback = { _, element, _, refcon in
            guard let refcon else { return }
            let tracker = Unmanaged<WindowTracker>.fromOpaque(refcon).takeUnretainedValue()
            MainActor.assumeIsolated {
                tracker.handleWindowNotification(element)
            }
        }
        guard AXObserverCreate(pid, callback, &observer) == .success, let observer else { return }

        let appElement = AXUIElementCreateApplication(pid)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        AXObserverAddNotification(observer, appElement, kAXWindowCreatedNotification as CFString, refcon)
        AXObserverAddNotification(observer, appElement, kAXFocusedWindowChangedNotification as CFString, refcon)
        let source = AXObserverGetRunLoopSource(observer)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        observers[pid] = observer
        runLoopSources[pid] = source

        // Seed with whatever is AX-visible right now (windows on the current Space) so we don't
        // wait for them to be recreated. Deliberately doesn't promote into the MRU order - that
        // would scramble the starting order using AX's arbitrary enumeration order instead of
        // leaving it to build up from real focus events.
        cacheExistingWindows(of: pid)
    }

    private func cacheExistingWindows(of pid: pid_t) {
        guard let axWindows = WindowEnumerator.axWindows(for: pid) else { return }
        for axWindow in axWindows where WindowEnumerator.axString(axWindow, kAXRoleAttribute) == kAXWindowRole {
            cache(axWindow)
        }
    }

    /// Handles a live "window created" or "window focused" notification: caches the element and
    /// promotes it to the front of the MRU order.
    private func handleWindowNotification(_ element: AXUIElement) {
        if let windowID = cache(element) {
            promote(windowID)
        }
    }

    private func promote(_ windowID: CGWindowID) {
        mruOrder.removeAll { $0 == windowID }
        mruOrder.insert(windowID, at: 0)
    }

    @discardableResult
    private func cache(_ element: AXUIElement) -> CGWindowID? {
        guard WindowEnumerator.axString(element, kAXRoleAttribute) == kAXWindowRole,
              let windowID = WindowEnumerator.windowID(of: element) else { return nil }
        elements[windowID] = element
        return windowID
    }
}
