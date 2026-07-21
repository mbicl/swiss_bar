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

    /// The last full `enumerate()` result. Kept off the ⌘Tab hot path: `enumerate()` makes a
    /// synchronous, timeout-bounded AX call per running app, and running that inside the
    /// event-tap callback risks tripping the tap's own watchdog (`tapDisabledByTimeout`) if a few
    /// apps are slow to respond, silently leaking the next ⌘Tab to the Dock's switcher. Refreshed
    /// by `refreshCache()` from latency-insensitive call sites (launch, Space change, app
    /// launch/termination, switcher dismissal) - never from the tap callback itself.
    private static var cachedCandidates: [CandidateWindow] = []

    /// The current cached candidate list, without triggering a refresh.
    static func cached() -> [CandidateWindow] {
        cachedCandidates
    }

    /// Re-adds candidates from the previous cache that this enumeration didn't produce but that
    /// Quartz says still exist. AX visibility is not a statement about existence: inside a
    /// fullscreen Space `kAXWindowsAttribute` reports only the fullscreen app's own window, so an
    /// enumeration taken there can legitimately return a single candidate on a system with a
    /// dozen windows - and since `refreshCache` runs on entering a Space, that one-entry list
    /// would otherwise stick until the next Space change. Anything still in `liveIDs` is known to
    /// exist, so keep it. Candidates with no window ID can't be verified and are not carried
    /// over. Pure - testable in isolation.
    nonisolated static func carryingOverStillLive(
        fresh: [CandidateWindow],
        previous: [CandidateWindow],
        liveIDs: Set<CGWindowID>
    ) -> [CandidateWindow] {
        guard !liveIDs.isEmpty else { return fresh }
        let freshIDs = Set(fresh.compactMap(\.windowID))
        let carried = previous.filter { candidate in
            guard let wid = candidate.windowID else { return false }
            return !freshIDs.contains(wid) && liveIDs.contains(wid)
        }
        guard !carried.isEmpty else { return fresh }
        // Spliced before the freshly-seen minimized windows so merge()'s ordering contract
        // (minimized last) still holds for `cached()` readers; `reorderedCache()` re-sorts anyway.
        return fresh.filter { !$0.isMinimized } + carried + fresh.filter(\.isMinimized)
    }

    /// Runs a full `enumerate()` and stores the result as the new cache. AX-heavy - call only from
    /// contexts that aren't latency sensitive (never the event-tap callback).
    @discardableResult
    static func refreshCache() -> [CandidateWindow] {
        let fresh = enumerate()
        let result = carryingOverStillLive(fresh: fresh, previous: cachedCandidates, liveIDs: allWindowIDs())
        if result.count != fresh.count {
            logger.notice("refreshCache: carried over \(result.count - fresh.count) still-live windows AX didn't report")
        }
        cachedCandidates = result
        return result
    }

    /// Re-orders the cached candidates using `WindowTracker`'s MRU order - just an array lookup,
    /// cheap enough to run synchronously in the event-tap callback, unlike `enumerate()`. Windows
    /// with no MRU entry yet keep their existing relative position in the cache (stable sort ties
    /// on a shared fallback value) rather than triggering a fresh z-order pass; doesn't discover
    /// new windows or drop closed ones.
    static func reorderedCache() -> [CandidateWindow] {
        let mruIndex = mruIndexByWindowID()
        return orderByMRU(cachedCandidates, mruIndex: mruIndex, unknownRank: mruIndex.count)
    }

    /// Pure ordering step: ranks each candidate by its MRU position when known (0 = most recent -
    /// only the one window that actually gained focus ever moves), or by `unknownRank` when not
    /// (kept identical across every MRU-unknown candidate, so Swift's stable sort preserves their
    /// existing relative order in `candidates`). Minimized candidates always sort last, regardless
    /// of MRU rank. No AX/Quartz/WindowTracker dependency - testable in isolation.
    nonisolated static func orderByMRU(
        _ candidates: [CandidateWindow],
        mruIndex: [CGWindowID: Int],
        unknownRank: Int
    ) -> [CandidateWindow] {
        let indexed: [(order: Int, window: CandidateWindow)] = candidates.map { candidate in
            guard !candidate.isMinimized else { return (Int.max, candidate) }
            if let wid = candidate.windowID, let position = mruIndex[wid] {
                return (position, candidate)
            }
            return (unknownRank, candidate)
        }
        return indexed.sorted { $0.order < $1.order }.map(\.window)
    }

    /// `WindowTracker`'s MRU window-ID order as a lookup dictionary (ID -> rank, 0 = most recent).
    private static func mruIndexByWindowID() -> [CGWindowID: Int] {
        Dictionary(uniqueKeysWithValues: WindowTracker.shared.mruOrderSnapshot().enumerated().map { ($0.element, $0.offset) })
    }

    /// Ordered front-to-back: windows with a known focus history (`WindowTracker`'s MRU order)
    /// first - stable, since only the one window that actually gained focus ever moves - then any
    /// not yet in that history (freshly launched, before a focus event has landed) ordered by
    /// Quartz z-order, then windows on other Spaces (works without Screen Recording - see
    /// `offSpaceCandidates`), then minimized windows.
    static func enumerate() -> [CandidateWindow] {
        let onScreen = onScreenWindows()
        let mruIndex = mruIndexByWindowID()

        var visible: [(order: Int, window: CandidateWindow)] = []
        var minimized: [CandidateWindow] = []
        var axIdentities: [AXWindowIdentity] = []

        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            let pid = app.processIdentifier
            guard let axWindows = axWindows(for: pid) else {
                logger.debug("ax windows for \(app.localizedName ?? "?", privacy: .public): unavailable")
                continue
            }
            logger.debug("ax windows for \(app.localizedName ?? "?", privacy: .public): \(axWindows.count)")

            for axWindow in axWindows {
                guard axString(axWindow, kAXRoleAttribute) == kAXWindowRole else { continue }
                let rawTitle = axString(axWindow, kAXTitleAttribute) ?? ""
                let wid = windowID(of: axWindow)
                let bounds = axFrame(axWindow)
                // An untitled window is only shown if it also looks like a real, user-facing
                // window (resolvable ID + the standard-window subrole real top-level windows
                // report) - titled windows are trusted as-is. Chromium-based apps (Chrome,
                // Brave, ...) expose extra internal/phantom AXWindow elements - untitled,
                // non-standard subrole - only while frontmost; without this guard they show up
                // as duplicate "Google Chrome"/"Brave Browser" entries via the title fallback
                // below.
                guard !rawTitle.isEmpty || (wid != nil && axSubrole(axWindow) == kAXStandardWindowSubrole) else { continue }
                let title = rawTitle.isEmpty ? (app.localizedName ?? "") : rawTitle
                let isMinimized = axBool(axWindow, kAXMinimizedAttribute) ?? false

                if let wid {
                    axElementCache[wid] = axWindow
                }
                axIdentities.append(AXWindowIdentity(pid: pid, windowID: wid, bounds: bounds))

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

                if let wid, let mruPosition = mruIndex[wid] {
                    visible.append((order: mruPosition, window: candidate))
                } else if let match = onScreen.first(where: { $0.pid == pid && boundsMatch($0.bounds, bounds) }) {
                    // No focus history yet - fall back to Quartz z-order, ordered after every
                    // MRU-known window since those reflect actual usage rather than a heuristic.
                    visible.append((order: mruIndex.count + match.index, window: candidate))
                } else {
                    // Visible per AX but absent from the on-screen list (e.g. a different Space) - keep, ordered last.
                    visible.append((order: Int.max, window: candidate))
                }
            }
        }

        let keys = dedupKeys(for: axIdentities)
        let offSpace = offSpaceCandidates(knownIDs: keys.ids, knownBounds: keys.bounds)

        let result = merge(visible: visible, offSpace: offSpace, minimized: minimized)
        logger.notice("enumerate() -> \(visible.count) visible, \(offSpace.count) off-space, \(minimized.count) minimized, \(result.count) total (screenRecording=\(CGPreflightScreenCaptureAccess()))")
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

    /// One AX-enumerated window, reduced to what Quartz dedup needs. Pure value type so the key
    /// derivation below is testable without AX.
    struct AXWindowIdentity {
        let pid: pid_t
        let windowID: CGWindowID?
        let bounds: CGRect?
    }

    /// Derives the two dedup keys `isDuplicate` matches against. Window IDs are exact, so every
    /// AX window that resolved one contributes an ID. Bounds are only an *approximate* identity
    /// and are recorded exclusively for windows whose ID couldn't be resolved: every fullscreen
    /// window of one app occupies the exact same full-display rect, so recording bounds for
    /// ID-resolved windows too made each fullscreen sibling arriving from Quartz look like a
    /// duplicate of the first one and vanish from the list. Pure - testable in isolation.
    nonisolated static func dedupKeys(
        for windows: [AXWindowIdentity]
    ) -> (ids: Set<CGWindowID>, bounds: [(pid: pid_t, bounds: CGRect)]) {
        var ids: Set<CGWindowID> = []
        var bounds: [(pid: pid_t, bounds: CGRect)] = []
        for window in windows {
            if let wid = window.windowID {
                ids.insert(wid)
            } else if let rect = window.bounds {
                bounds.append((pid: window.pid, bounds: rect))
            }
        }
        return (ids, bounds)
    }

    /// True if a Quartz-listed window is already represented among the AX-enumerated windows.
    /// Primary key is the window ID (exact); bounds matching is the fallback for elements whose
    /// ID couldn't be resolved - `knownBounds` (built by `dedupKeys`) only ever contains such
    /// elements, which is what makes matching on pid + frame safe despite windows of the same app
    /// often sharing an identical frame (e.g. multiple fullscreen windows). Pure - testable in
    /// isolation.
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
        /// May be empty - `kCGWindowName` is redacted for other processes without Screen
        /// Recording. Resolved from a held AX element (or the app name) by `offSpaceCandidates`.
        let title: String
        let bounds: CGRect
    }

    /// `kAXWindowsAttribute` only reports windows on the currently-visible Space(s) - windows
    /// parked on other Spaces are invisible to Accessibility until their owning app is activated.
    /// `CGWindowListCopyWindowInfo(.optionAll)` is Space-agnostic and fills that gap. Titles come
    /// from `kCGWindowName` when available, or from a held AX element (`WindowTracker`/
    /// `axElementCache`) otherwise - so this works without Screen Recording; that grant only
    /// improves title fidelity for windows we've never held an element for.
    private static func offSpaceCandidates(
        knownIDs: Set<CGWindowID>,
        knownBounds: [(pid: pid_t, bounds: CGRect)]
    ) -> [CandidateWindow] {
        let runningApps = Dictionary(
            uniqueKeysWithValues: NSWorkspace.shared.runningApplications.map { ($0.processIdentifier, $0) }
        )

        let all = allWindows()
        // Prune against IDs alone, not the title-filtered list above: kCGWindowNumber is never
        // redacted (only kCGWindowName is, absent Screen Recording), so this can't spuriously
        // wipe the whole AX cache just because Screen Recording isn't granted. Also skip pruning
        // entirely if the ID set came back empty - that's a transient Quartz failure, not "no
        // windows exist".
        let liveIDs = allWindowIDs()
        if !liveIDs.isEmpty {
            axElementCache = axElementCache.filter { liveIDs.contains($0.key) }
        }

        var result: [CandidateWindow] = []
        var skippedUntitled = 0
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
            // windows too); fall back to the enumeration-time cache. A held element keeps
            // answering kAXTitleAttribute after its window leaves the current Space, which is
            // what makes titles work here without Screen Recording.
            let cachedElement = WindowTracker.shared.element(for: window.windowID) ?? axElementCache[window.windowID]
            let axTitle = cachedElement.flatMap { axString($0, kAXTitleAttribute) } ?? ""
            let resolvedTitle = !window.title.isEmpty ? window.title : axTitle

            // The Quartz-side equivalent of the AX path's Chromium ghost-window guard above: an
            // untitled window is only trusted when something vouches for it being a real
            // top-level window - here, a held AX element reporting the standard-window subrole.
            // A layer-0 window we've never held an element for and that has no title anywhere is
            // far more likely an app's internal host window than something the user can switch to.
            if resolvedTitle.isEmpty {
                guard let cachedElement, axSubrole(cachedElement) == kAXStandardWindowSubrole else {
                    skippedUntitled += 1
                    continue
                }
            }

            let isMinimized = cachedElement.flatMap { axBool($0, kAXMinimizedAttribute) } ?? false
            logger.debug("off-space window: \(app.localizedName ?? "?", privacy: .public) title=\(resolvedTitle, privacy: .public) cachedAX=\(cachedElement != nil)")
            result.append(CandidateWindow(
                axElement: cachedElement,
                windowID: window.windowID,
                title: resolvedTitle.isEmpty ? (app.localizedName ?? "") : resolvedTitle,
                appName: app.localizedName ?? "",
                appIcon: app.icon,
                pid: window.pid,
                isMinimized: isMinimized
            ))
        }
        logger.notice("offSpace: \(all.count) quartz layer-0 -> \(result.count) candidates (\(skippedUntitled) untitled + unvouched)")
        return result
    }

    /// Every layer-0 window ID across all Spaces, regardless of title visibility. Unlike
    /// `allWindows()`, doesn't require Screen Recording - `kCGWindowNumber` is never redacted,
    /// only `kCGWindowName` is - so it's safe to use as the source of truth for cache pruning.
    static func allWindowIDs() -> Set<CGWindowID> {
        guard let list = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: AnyObject]] else {
            return []
        }
        var ids: Set<CGWindowID> = []
        for info in list {
            guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0,
                  let windowNumber = info[kCGWindowNumber as String] as? Int else { continue }
            ids.insert(CGWindowID(windowNumber))
        }
        return ids
    }

    /// Minimum edge length for a Quartz window to be treated as user-facing. Untitled layer-0
    /// windows used to be filtered out implicitly by the non-empty-title requirement below; now
    /// that untitled windows are kept (they're the only way to see other Spaces without Screen
    /// Recording), tiny helper/host windows need an explicit filter.
    private static let minimumWindowEdge: CGFloat = 40

    private static func allWindows() -> [OffScreenWindow] {
        guard let list = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: AnyObject]] else {
            return []
        }
        var result: [OffScreenWindow] = []
        for info in list {
            guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0,
                  let ownerPID = info[kCGWindowOwnerPID as String] as? Int,
                  let windowNumber = info[kCGWindowNumber as String] as? Int,
                  let boundsDict = info[kCGWindowBounds as String] as? [String: AnyObject] else { continue }
            // kCGWindowName is redacted for other processes without Screen Recording. Requiring
            // it made this whole list come back empty on machines without that grant, leaving AX
            // - current-Space only - as the sole source of candidates: the "⌘Tab only shows this
            // Space / only the fullscreen app" bug. Treat a missing title as *unknown* and
            // resolve it from a held AX element in offSpaceCandidates instead of dropping the
            // window.
            let title = (info[kCGWindowName as String] as? String) ?? ""
            let alpha = (info[kCGWindowAlpha as String] as? CGFloat) ?? 1
            guard alpha > 0 else { continue }
            var rect = CGRect.zero
            guard CGRectMakeWithDictionaryRepresentation(boundsDict as CFDictionary, &rect) else { continue }
            guard rect.width >= minimumWindowEdge, rect.height >= minimumWindowEdge else { continue }
            result.append(OffScreenWindow(pid: pid_t(ownerPID), windowID: CGWindowID(windowNumber), title: title, bounds: rect))
        }
        return result
    }

    // MARK: - On-screen window z-order (front to back) from Quartz

    struct OnScreenWindow {
        let pid: pid_t
        let windowID: CGWindowID?
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
            let wid = (info[kCGWindowNumber as String] as? Int).map { CGWindowID($0) }
            result.append(OnScreenWindow(pid: pid_t(ownerPID), windowID: wid, bounds: rect, index: index))
        }
        return result
    }

    /// The current on-screen windows' IDs, front-to-back (index 0 = frontmost). `kCGWindowNumber`
    /// is never redacted (unlike `kCGWindowName`), so this works without Screen Recording. Used to
    /// seed `WindowTracker`'s MRU order with a real z-order snapshot at cold start, before any
    /// focus event has fired.
    static func onScreenWindowIDsFrontToBack() -> [CGWindowID] {
        onScreenWindows().compactMap(\.windowID)
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

    private static func axSubrole(_ element: AXUIElement) -> String? {
        axString(element, kAXSubroleAttribute)
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
