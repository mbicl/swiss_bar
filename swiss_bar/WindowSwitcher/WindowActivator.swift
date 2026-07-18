//
//  WindowActivator.swift
//  swiss_bar
//

import AppKit
import ApplicationServices
import os

// MARK: - SkyLight private APIs
// The only reliable way to focus a specific window by ID - including windows on other Spaces,
// where no AX element is obtainable up front. Same approach as alt-tab-macos; fine for
// Developer ID distribution (not App Store), and this app is unsandboxed. Resolved via dlsym
// because SkyLight is a private framework outside the SDK link path - and so the app degrades
// gracefully (AX-only activation) if a future macOS drops the symbols.

@_silgen_name("GetProcessForPID")
private func GetProcessForPID(_ pid: pid_t, _ psn: inout ProcessSerialNumber) -> OSStatus

private typealias SLPSSetFrontProcessWithOptionsFunc = @convention(c) (UnsafeMutablePointer<ProcessSerialNumber>, CGWindowID, UInt32) -> CGError
private typealias SLPSPostEventRecordToFunc = @convention(c) (UnsafeMutablePointer<ProcessSerialNumber>, UnsafeMutablePointer<UInt8>) -> CGError

private let skyLightHandle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)

private let slpsSetFrontProcessWithOptions: SLPSSetFrontProcessWithOptionsFunc? = {
    guard let handle = skyLightHandle, let symbol = dlsym(handle, "_SLPSSetFrontProcessWithOptions") else { return nil }
    return unsafeBitCast(symbol, to: SLPSSetFrontProcessWithOptionsFunc.self)
}()

private let slpsPostEventRecordTo: SLPSPostEventRecordToFunc? = {
    guard let handle = skyLightHandle, let symbol = dlsym(handle, "SLPSPostEventRecordTo") else { return nil }
    return unsafeBitCast(symbol, to: SLPSPostEventRecordToFunc.self)
}()

/// `kCPSUserGenerated`: treat the focus switch as user-initiated so macOS honors it (and switches
/// Space) instead of silently ignoring a programmatic request from a background process.
private let kCPSUserGenerated: UInt32 = 0x200

/// Main-actor confined: reads `WindowTracker.shared` (itself `@MainActor`) and is only ever
/// invoked from the main-thread event-tap delegate chain.
@MainActor
enum WindowActivator {

    private static let logger = Logger(subsystem: "com.MBI.swiss-bar", category: "WindowActivator")

    static func activate(_ window: CandidateWindow) {
        let axElement = window.axElement ?? window.windowID.flatMap { WindowTracker.shared.element(for: $0) }
        let fullscreen = window.windowID.map { SpaceSwitcher.involvesFullscreen(windowID: $0) } ?? false
        logger.notice("activate '\(window.title, privacy: .public)' (\(window.appName, privacy: .public), pid \(window.pid), ax=\(axElement != nil), wid=\(window.windowID ?? 0), fullscreen=\(fullscreen))")

        if fullscreen {
            // Crossing into or out of a fullscreen Space: let macOS do it. Both a CGS display
            // switch and an AX raise composite the target window onto the *currently visible*
            // Space (dragging it on top of the fullscreen app and corrupting its UI) if done
            // beforehand - so no AX call happens here until the transition has actually
            // finished. Trigger the transition, then finish the raise once it lands.
            let isFrontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier == window.pid
            if isFrontmost || SpaceSwitcher.hasWindowOnActiveSpace(pid: window.pid) {
                // Plain activation is a no-op here (app's already frontmost, or already has a
                // window on the visible Space so macOS won't jump Spaces on its own) - force the
                // transition the same way off-Space windows are focused: a user-generated
                // SkyLight focus-by-ID.
                focusBySkyLight(window)
            } else {
                NSRunningApplication(processIdentifier: window.pid)?.activate(options: [])
            }
            afterSpaceChange {
                finishFullscreenActivation(window, axElement: axElement)
            }
            return
        }

        // Normal → normal. AX can't see (or raise) a window on a non-visible Space and SkyLight
        // focus-by-ID doesn't switch Spaces on its own, so move the display to the window's Space
        // first. No-op when it's already on a current Space.
        if let windowID = window.windowID {
            SpaceSwitcher.switchToSpace(of: windowID)
        }

        if let axElement {
            // Pure AX path: rewrite the app's own idea of its main/focused window so the
            // asynchronous app activation can't stomp the raise, then raise and activate. This
            // also handles the multiple-windows-per-app case. No SkyLight force-front here - it
            // composites across Spaces.
            if window.isMinimized {
                AXUIElementSetAttributeValue(axElement, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
            }
            AXUIElementSetAttributeValue(axElement, kAXMainAttribute as CFString, kCFBooleanTrue)
            let appElement = AXUIElementCreateApplication(window.pid)
            AXUIElementSetMessagingTimeout(appElement, 0.25)
            AXUIElementSetAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, axElement)
            AXUIElementPerformAction(axElement, kAXRaiseAction as CFString)
            NSRunningApplication(processIdentifier: window.pid)?.activate(options: [])
            return
        }

        // No AX element even after the Space switch. SkyLight focus-by-ID plus app activation,
        // then poll for the window to become AX-visible now that we're (hopefully) on its Space.
        focusBySkyLight(window)
        activateAppAndRetryRaise(window)
    }

    /// Finishes a fullscreen-crossing activation after the Space transition has landed: resolves
    /// an AX element for the window (it may not have been AX-visible before the transition), then
    /// un-minimizes/raises/focuses it. Falls back to app activation alone if no element can be
    /// found - matches the "no AX element" behavior of the normal-window path.
    private static func finishFullscreenActivation(_ window: CandidateWindow, axElement: AXUIElement?) {
        let resolved = axElement
            ?? window.windowID.flatMap { WindowTracker.shared.element(for: $0) }
            ?? WindowEnumerator.axWindows(for: window.pid).flatMap { matchingAXElement(for: window, in: $0) }

        guard let resolved else {
            logger.notice("finishFullscreenActivation: no AX element for '\(window.title, privacy: .public)' - app activated only")
            NSRunningApplication(processIdentifier: window.pid)?.activate(options: [])
            return
        }

        if window.isMinimized {
            AXUIElementSetAttributeValue(resolved, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        }
        AXUIElementSetAttributeValue(resolved, kAXMainAttribute as CFString, kCFBooleanTrue)
        let appElement = AXUIElementCreateApplication(window.pid)
        AXUIElementSetMessagingTimeout(appElement, 0.25)
        AXUIElementSetAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, resolved)
        AXUIElementPerformAction(resolved, kAXRaiseAction as CFString)
        NSRunningApplication(processIdentifier: window.pid)?.activate(options: [])
    }

    /// Runs `body` once the active Space changes (`NSWorkspace.activeSpaceDidChangeNotification`)
    /// or after `timeout` elapses, whichever comes first - exactly once. Used to defer AX work
    /// until a fullscreen-crossing transition has actually completed, since neither the
    /// notification alone (may not fire if the transition doesn't happen) nor a fixed delay alone
    /// (races the animation) is sufficient by itself.
    private static func afterSpaceChange(timeout: TimeInterval = 1.0, _ body: @escaping () -> Void) {
        var completed = false
        var observer: NSObjectProtocol?
        let complete = {
            guard !completed else { return }
            completed = true
            if let observer { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
            body()
        }
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { _ in complete() }
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { complete() }
    }

    /// Matches a `CandidateWindow` against a live AX window list: by window ID when resolvable,
    /// falling back to title comparison (can miss if the title changed since enumeration).
    private static func matchingAXElement(for window: CandidateWindow, in axWindows: [AXUIElement]) -> AXUIElement? {
        axWindows.first { element in
            if let wid = window.windowID, WindowEnumerator.windowID(of: element) == wid {
                return true
            }
            return WindowEnumerator.axString(element, kAXTitleAttribute) == window.title
        }
    }

    /// Best-effort focus of a specific window by ID (switching Space if needed) via SkyLight.
    /// No-op when the window ID, process serial number, or SkyLight itself is unavailable.
    private static func focusBySkyLight(_ window: CandidateWindow) {
        guard let windowID = window.windowID, let setFrontProcess = slpsSetFrontProcessWithOptions else { return }
        var psn = ProcessSerialNumber()
        guard GetProcessForPID(window.pid, &psn) == noErr else {
            logger.notice("GetProcessForPID failed for pid \(window.pid)")
            return
        }
        let result = setFrontProcess(&psn, windowID, kCPSUserGenerated)
        makeKeyWindow(&psn, windowID)
        if result != .success {
            logger.notice("_SLPSSetFrontProcessWithOptions failed: \(result.rawValue)")
        }
    }

    /// Posts a synthetic focus event pair directly to the owning process, telling it to make the
    /// given window key. Byte layout is the well-known SkyLight event record used by every
    /// window-switcher app; there is no public equivalent.
    private static func makeKeyWindow(_ psn: inout ProcessSerialNumber, _ windowID: CGWindowID) {
        guard let postEventRecord = slpsPostEventRecordTo else { return }
        var bytes = [UInt8](repeating: 0, count: 0xf8)
        bytes[0x04] = 0xf8
        bytes[0x3a] = 0x10
        withUnsafeBytes(of: windowID.littleEndian) { widBytes in
            for i in 0..<4 { bytes[0x3c + i] = widBytes[i] }
        }
        for i in 0x20..<0x30 { bytes[i] = 0xff }
        bytes[0x08] = 0x01
        _ = postEventRecord(&psn, &bytes)
        bytes[0x08] = 0x02
        _ = postEventRecord(&psn, &bytes)
    }

    /// Last-resort path when neither a window ID nor an AX element is available: activate the
    /// owning app, then poll briefly for the window to become AX-visible (activation is
    /// asynchronous, and a Space switch takes a few hundred ms). Matched by window ID when
    /// possible; title comparison is the final fallback and can miss (titles change - e.g.
    /// terminal spinner animations).
    private static func activateAppAndRetryRaise(_ window: CandidateWindow) {
        NSRunningApplication(processIdentifier: window.pid)?.activate(options: [])
        attemptRaise(window, retriesLeft: 4)
    }

    private static func attemptRaise(_ window: CandidateWindow, retriesLeft: Int) {
        if let axWindows = WindowEnumerator.axWindows(for: window.pid) {
            if let match = matchingAXElement(for: window, in: axWindows) {
                AXUIElementSetAttributeValue(match, kAXMainAttribute as CFString, kCFBooleanTrue)
                AXUIElementPerformAction(match, kAXRaiseAction as CFString)
                return
            }
        }

        guard retriesLeft > 0 else {
            logger.notice("fallback raise: couldn't resolve '\(window.title, privacy: .public)' (wid=\(window.windowID ?? 0)) after retries - app activated, window not raised")
            return
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 250_000_000)
            attemptRaise(window, retriesLeft: retriesLeft - 1)
        }
    }
}
