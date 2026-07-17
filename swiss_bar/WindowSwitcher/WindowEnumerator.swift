//
//  WindowEnumerator.swift
//  swiss_bar
//

import AppKit
import ApplicationServices
import CoreGraphics
import os

/// Maps an AX window element to its `CGWindowID`. Private API, but the de-facto standard bridge
/// between the Accessibility and Quartz window worlds (used by alt-tab-macos, yabai, etc.) -
/// fine for Developer ID distribution (not App Store), and this app is unsandboxed.
@_silgen_name("_AXUIElementGetWindow")
@discardableResult
private func _AXUIElementGetWindow(_ element: AXUIElement, _ identifier: inout CGWindowID) -> AXError

enum WindowEnumerator {

    private static let logger = Logger(subsystem: "com.MBI.swiss-bar", category: "WindowEnumerator")

    /// AX elements stay valid (and raisable) after their window moves to another Space - only
    /// `kAXWindowsAttribute` stops listing them. Caching every element we've ever seen, keyed by
    /// window ID, lets the activator raise an off-Space window directly instead of falling back
    /// to blind app activation. Pruned against the live Quartz window list on each enumeration.
    private static var axElementCache: [CGWindowID: AXUIElement] = [:]

    /// Ordered front-to-back: on-screen windows first (matching Quartz z-order), then windows on
    /// other Spaces (Screen Recording permission required to see these - see `offSpaceCandidates`),
    /// then minimized windows.
    static func enumerate() -> [CandidateWindow] {
        let onScreen = onScreenWindows()

        var visible: [(order: Int, window: CandidateWindow)] = []
        var minimized: [CandidateWindow] = []
        var knownIDs: Set<CGWindowID> = []
        var knownBounds: [(pid: pid_t, bounds: CGRect)] = []

        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            let pid = app.processIdentifier
            guard let axWindows = axWindows(for: pid) else { continue }

            for axWindow in axWindows {
                guard axString(axWindow, kAXRoleAttribute) == kAXWindowRole else { continue }
                let title = axString(axWindow, kAXTitleAttribute) ?? ""
                guard !title.isEmpty else { continue }
                let isMinimized = axBool(axWindow, kAXMinimizedAttribute) ?? false

                let wid = windowID(of: axWindow)
                if let wid {
                    knownIDs.insert(wid)
                    axElementCache[wid] = axWindow
                }
                if let bounds = axFrame(axWindow) {
                    knownBounds.append((pid: pid, bounds: bounds))
                }

                let candidate = CandidateWindow(
                    axElement: axWindow,
                    windowID: wid,
                    title: title,
                    appName: app.localizedName ?? "",
                    appIcon: app.icon,
                    pid: pid,
                    isMinimized: isMinimized
                )

                if isMinimized {
                    minimized.append(candidate)
                    continue
                }

                if let match = onScreen.first(where: { $0.pid == pid && boundsMatch($0.bounds, axFrame(axWindow)) }) {
                    visible.append((order: match.index, window: candidate))
                } else {
                    // Visible per AX but absent from the on-screen list (e.g. a different Space) - keep, ordered last.
                    visible.append((order: Int.max, window: candidate))
                }
            }
        }

        let offSpace = offSpaceCandidates(knownIDs: knownIDs, knownBounds: knownBounds)

        let result = merge(visible: visible, offSpace: offSpace, minimized: minimized)
        logger.notice("enumerate() -> \(visible.count) visible, \(offSpace.count) off-space, \(minimized.count) minimized, \(result.count) total")
        let dump = result.enumerated().map { "[\($0.offset)] \($0.element.appName)|\($0.element.title.prefix(24))|wid=\($0.element.windowID ?? 0)" }.joined(separator: "  ")
        logger.notice("list: \(dump, privacy: .public)")
        return result
    }

    static func windowID(of element: AXUIElement) -> CGWindowID? {
        var wid: CGWindowID = 0
        guard _AXUIElementGetWindow(element, &wid) == .success, wid != 0 else { return nil }
        return wid
    }

    /// Proactively caches AX elements for every currently AX-visible window. Called at launch and
    /// on every Space change (not just during ⌘Tab) so that any window whose Space has been
    /// displayed at least once while the app is running stays activatable after it goes
    /// off-Space. Without this, off-Space windows never seen by an enumeration have no AX element
    /// and can't be reliably focused (the SkyLight by-ID focus is a silent no-op on this macOS,
    /// and app activation won't switch Space when the app has a window on the current one).
    static func warmElementCache() {
        var cached = 0
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            guard let axWindows = axWindows(for: app.processIdentifier) else { continue }
            for axWindow in axWindows {
                guard axString(axWindow, kAXRoleAttribute) == kAXWindowRole else { continue }
                if let wid = windowID(of: axWindow) {
                    axElementCache[wid] = axWindow
                    cached += 1
                }
            }
        }
        logger.debug("warmElementCache: \(cached) window elements cached")
    }

    /// Pure ordering step: visible windows front-to-back by z-order index (unmatched visible
    /// windows, order == Int.max, last among visibles), then off-space windows, then minimized
    /// windows last. No AX/Quartz dependency - testable in isolation.
    nonisolated static func merge(
        visible: [(order: Int, window: CandidateWindow)],
        offSpace: [CandidateWindow],
        minimized: [CandidateWindow]
    ) -> [CandidateWindow] {
        let orderedVisible = visible.sorted { $0.order < $1.order }.map(\.window)
        return orderedVisible + offSpace + minimized
    }

    /// True if a Quartz-listed window is already represented among the AX-enumerated windows.
    /// Primary key is the window ID (exact); bounds matching is the fallback for elements whose
    /// ID couldn't be resolved. Pure - testable in isolation.
    nonisolated static func isDuplicate(
        windowID: CGWindowID,
        pid: pid_t,
        bounds: CGRect,
        knownIDs: Set<CGWindowID>,
        knownBounds: [(pid: pid_t, bounds: CGRect)]
    ) -> Bool {
        knownIDs.contains(windowID) || knownBounds.contains { $0.pid == pid && boundsMatch($0.bounds, bounds) }
    }

    // MARK: - Off-Space windows (Quartz, all Spaces)

    struct OffScreenWindow {
        let pid: pid_t
        let windowID: CGWindowID
        let title: String
        let bounds: CGRect
    }

    /// `kAXWindowsAttribute` only reports windows on the currently-visible Space(s) - windows
    /// parked on other Spaces are invisible to Accessibility until their owning app is activated.
    /// `CGWindowListCopyWindowInfo(.optionAll)` is Space-agnostic and fills that gap, but reading
    /// `kCGWindowName` for windows owned by other processes requires Screen Recording permission -
    /// without it this silently returns an empty list (graceful degradation to AX-only behavior).
    private static func offSpaceCandidates(
        knownIDs: Set<CGWindowID>,
        knownBounds: [(pid: pid_t, bounds: CGRect)]
    ) -> [CandidateWindow] {
        let runningApps = Dictionary(
            uniqueKeysWithValues: NSWorkspace.shared.runningApplications.map { ($0.processIdentifier, $0) }
        )

        let all = allWindows()
        axElementCache = axElementCache.filter { cached in all.contains { $0.windowID == cached.key } }

        var result: [CandidateWindow] = []
        for window in all {
            guard let app = runningApps[window.pid], app.activationPolicy == .regular else { continue }
            guard !isDuplicate(
                windowID: window.windowID,
                pid: window.pid,
                bounds: window.bounds,
                knownIDs: knownIDs,
                knownBounds: knownBounds
            ) else { continue }

            // Prefer the tracker (captures elements at window-creation time, so it has off-Space
            // windows too); fall back to the enumeration-time cache.
            let cachedElement = WindowTracker.shared.element(for: window.windowID) ?? axElementCache[window.windowID]
            logger.debug("off-space window: \(app.localizedName ?? "?", privacy: .public) title=\(window.title, privacy: .public) cachedAX=\(cachedElement != nil)")
            result.append(CandidateWindow(
                axElement: cachedElement,
                windowID: window.windowID,
                title: window.title,
                appName: app.localizedName ?? "",
                appIcon: app.icon,
                pid: window.pid,
                isMinimized: false
            ))
        }
        return result
    }

    private static func allWindows() -> [OffScreenWindow] {
        guard let list = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: AnyObject]] else {
            return []
        }
        var result: [OffScreenWindow] = []
        for info in list {
            guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0,
                  let ownerPID = info[kCGWindowOwnerPID as String] as? Int,
                  let windowNumber = info[kCGWindowNumber as String] as? Int,
                  let title = info[kCGWindowName as String] as? String, !title.isEmpty,
                  let boundsDict = info[kCGWindowBounds as String] as? [String: AnyObject] else { continue }
            var rect = CGRect.zero
            guard CGRectMakeWithDictionaryRepresentation(boundsDict as CFDictionary, &rect) else { continue }
            result.append(OffScreenWindow(pid: pid_t(ownerPID), windowID: CGWindowID(windowNumber), title: title, bounds: rect))
        }
        return result
    }

    // MARK: - On-screen window z-order (front to back) from Quartz

    struct OnScreenWindow {
        let pid: pid_t
        let bounds: CGRect
        let index: Int
    }

    private static func onScreenWindows() -> [OnScreenWindow] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: AnyObject]] else {
            return []
        }
        var result: [OnScreenWindow] = []
        for (index, info) in list.enumerated() {
            guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0,
                  let ownerPID = info[kCGWindowOwnerPID as String] as? Int,
                  let boundsDict = info[kCGWindowBounds as String] as? [String: AnyObject] else { continue }
            var rect = CGRect.zero
            guard CGRectMakeWithDictionaryRepresentation(boundsDict as CFDictionary, &rect) else { continue }
            result.append(OnScreenWindow(pid: pid_t(ownerPID), bounds: rect, index: index))
        }
        return result
    }

    nonisolated static func boundsMatch(_ a: CGRect, _ b: CGRect?) -> Bool {
        guard let b else { return false }
        let tolerance: CGFloat = 2
        return abs(a.origin.x - b.origin.x) < tolerance
            && abs(a.origin.y - b.origin.y) < tolerance
            && abs(a.size.width - b.size.width) < tolerance
            && abs(a.size.height - b.size.height) < tolerance
    }

    private static func axFrame(_ axWindow: AXUIElement) -> CGRect? {
        guard let origin = axPoint(axWindow, kAXPositionAttribute),
              let size = axSize(axWindow, kAXSizeAttribute) else { return nil }
        return CGRect(origin: origin, size: size)
    }

    // MARK: - AX attribute helpers

    /// Fetches the current window list for `pid`, or `nil` if unavailable. Shared by `enumerate()`
    /// and `WindowActivator`'s off-Space raise fallback.
    static func axWindows(for pid: pid_t) -> [AXUIElement]? {
        let appElement = AXUIElementCreateApplication(pid)
        // Hung apps otherwise block AX calls for ~6s each, freezing the switcher on first Tab.
        AXUIElementSetMessagingTimeout(appElement, 0.25)
        return axArrayValue(appElement, kAXWindowsAttribute)
    }

    private static func axValue(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value
    }

    private static func axArrayValue(_ element: AXUIElement, _ attribute: String) -> [AXUIElement]? {
        axValue(element, attribute) as? [AXUIElement]
    }

    static func axString(_ element: AXUIElement, _ attribute: String) -> String? {
        axValue(element, attribute) as? String
    }

    private static func axBool(_ element: AXUIElement, _ attribute: String) -> Bool? {
        axValue(element, attribute) as? Bool
    }

    private static func axPoint(_ element: AXUIElement, _ attribute: String) -> CGPoint? {
        guard let value = axValue(element, attribute) else { return nil }
        var point = CGPoint.zero
        guard AXValueGetValue(value as! AXValue, .cgPoint, &point) else { return nil }
        return point
    }

    private static func axSize(_ element: AXUIElement, _ attribute: String) -> CGSize? {
        guard let value = axValue(element, attribute) else { return nil }
        var size = CGSize.zero
        guard AXValueGetValue(value as! AXValue, .cgSize, &size) else { return nil }
        return size
    }
}
