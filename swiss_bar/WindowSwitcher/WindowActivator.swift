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
            //
            // Always try SkyLight focus-by-ID first: it's the only mechanism that can
            // disambiguate between multiple fullscreen Spaces of the *same* app - plain
            // activate() has no way to say which Space/window to land on, and macOS's
            // activation heuristic just jumps to whichever fullscreen Space it last
            // considered "current" for that app, not necessarily the requested one. Fall
            // back to plain activation only when SkyLight genuinely couldn't be used.
            let usedSkyLight = focusBySkyLight(window)
            if !usedSkyLight {
                NSRunningApplication(processIdentifier: window.pid)?.activate(options: [])
            }
            logger.notice("fullscreen activation path: \(usedSkyLight ? "skylight" : "plain-activate", privacy: .public) for '\(window.title, privacy: .public)'")
            // Poll for the transition to land rather than waiting on
            // `NSWorkspace.activeSpaceDidChangeNotification`: confirmed empirically that it never
            // fires for a SkyLight-triggered fullscreen crossing (every activation was hitting the
            // full fixed-delay fallback, never the notification), so a fixed wait before the first
            // AX check only added latency - polling resolves as soon as the transition actually
            // finishes instead of always waiting the worst-case duration.
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 100_000_000)
                finishFullscreenActivation(window, axElement: axElement, retriesLeft: 9)
            }
            return
        }

        // Normal → normal. AX can't see (or raise) a window on a non-visible Space and SkyLight
        // focus-by-ID doesn't switch Spaces on its own, so move the display to the window's Space
        // first. No-op when it's already on a current Space.
        var spaceSwitchSucceeded = true
        if let windowID = window.windowID {
            spaceSwitchSucceeded = SpaceSwitcher.switchToSpace(of: windowID)
            if !spaceSwitchSucceeded {
                logger.notice("switchToSpace did not switch for wid=\(windowID) - AX/raise retries are unlikely to find the window")
            }
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
        _ = focusBySkyLight(window)
        activateAppAndRetryRaise(window, spaceSwitchSucceeded: spaceSwitchSucceeded)
    }

    /// Finishes a fullscreen-crossing activation once the Space transition has landed: resolves an
    /// AX element for the window (it may not have been AX-visible before the transition), then
    /// un-minimizes/raises/focuses it. `kAXWindowsAttribute` only reports windows on the
    /// currently-displayed Space, so a match here is a reliable signal the transition has actually
    /// completed - safe to poll for aggressively rather than waiting a fixed duration up front.
    /// Retries every 100ms (9 retries ≈ 1s total, matching the previous fixed-wait ceiling) before
    /// falling back to app activation alone - matches the "no AX element" behavior of the
    /// normal-window path.
    private static func finishFullscreenActivation(_ window: CandidateWindow, axElement: AXUIElement?, retriesLeft: Int) {
        let resolved = axElement
            ?? window.windowID.flatMap { WindowTracker.shared.element(for: $0) }
            ?? WindowEnumerator.axWindows(for: window.pid).flatMap { matchingAXElement(for: window, in: $0) }

        guard let resolved else {
            guard retriesLeft > 0 else {
                logger.notice("finishFullscreenActivation: no AX element for '\(window.title, privacy: .public)' after retries - app activated only")
                NSRunningApplication(processIdentifier: window.pid)?.activate(options: [])
                return
            }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 100_000_000)
                finishFullscreenActivation(window, axElement: nil, retriesLeft: retriesLeft - 1)
            }
            return
        }
        logger.notice("finishFullscreenActivation: AX element resolved for '\(window.title, privacy: .public)' - raising")

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
    /// Returns `false` when the window ID, process serial number, or SkyLight itself is
    /// unavailable, or when `_SLPSSetFrontProcessWithOptions` itself reports failure - callers
    /// needing a Space-jump guarantee should fall back to plain app activation in that case.
    @discardableResult
    private static func focusBySkyLight(_ window: CandidateWindow) -> Bool {
        guard let windowID = window.windowID else {
            logger.notice("focusBySkyLight: no windowID for '\(window.title, privacy: .public)'")
            return false
        }
        guard let setFrontProcess = slpsSetFrontProcessWithOptions else {
            logger.notice("focusBySkyLight: _SLPSSetFrontProcessWithOptions symbol unavailable")
            return false
        }
        var psn = ProcessSerialNumber()
        guard GetProcessForPID(window.pid, &psn) == noErr else {
            logger.notice("GetProcessForPID failed for pid \(window.pid)")
            return false
        }
        let result = setFrontProcess(&psn, windowID, kCPSUserGenerated)
        makeKeyWindow(&psn, windowID)
        logger.notice("focusBySkyLight: wid=\(windowID) psn=(\(psn.highLongOfPSN),\(psn.lowLongOfPSN)) result=\(result.rawValue)")
        if result != .success {
            return false
        }
        return true
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
    private static func activateAppAndRetryRaise(_ window: CandidateWindow, spaceSwitchSucceeded: Bool) {
        NSRunningApplication(processIdentifier: window.pid)?.activate(options: [])
        attemptRaise(window, retriesLeft: raiseRetryCount(spaceSwitchSucceeded: spaceSwitchSucceeded))
    }

    /// How many times to retry resolving an AX element after a Space-switch attempt. A failed
    /// switch means the window's Space almost certainly never became visible, so AX enumeration
    /// can never find it regardless of retry count - one cheap immediate check (not zero, in
    /// case the window was already AX-visible for an unrelated reason) beats burning 4×250ms
    /// against a doomed outcome. Pure - testable in isolation.
    nonisolated static func raiseRetryCount(spaceSwitchSucceeded: Bool) -> Int {
        spaceSwitchSucceeded ? 4 : 1
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
