//
//  WindowEnumerator.swift
//  swiss_bar
//

import AppKit
import ApplicationServices
import CoreGraphics

enum WindowEnumerator {

    /// Ordered front-to-back across apps: on-screen windows first (matching Quartz z-order), then minimized windows.
    static func enumerate() -> [CandidateWindow] {
        let onScreen = onScreenWindows()

        var visible: [(order: Int, window: CandidateWindow)] = []
        var minimized: [CandidateWindow] = []

        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            let pid = app.processIdentifier
            let appElement = AXUIElementCreateApplication(pid)
            // Hung apps otherwise block AX calls for ~6s each, freezing the switcher on first Tab.
            AXUIElementSetMessagingTimeout(appElement, 0.25)

            guard let axWindows = axArrayValue(appElement, kAXWindowsAttribute) else { continue }

            for axWindow in axWindows {
                guard axString(axWindow, kAXRoleAttribute) == kAXWindowRole else { continue }
                let title = axString(axWindow, kAXTitleAttribute) ?? ""
                guard !title.isEmpty else { continue }
                let isMinimized = axBool(axWindow, kAXMinimizedAttribute) ?? false

                let candidate = CandidateWindow(
                    axElement: axWindow,
                    windowID: nil,
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

        let orderedVisible = visible.sorted { $0.order < $1.order }.map(\.window)
        return orderedVisible + minimized
    }

    // MARK: - On-screen window z-order (front to back) from Quartz

    private struct OnScreenWindow {
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

    private static func boundsMatch(_ a: CGRect, _ b: CGRect?) -> Bool {
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

    private static func axValue(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value
    }

    private static func axArrayValue(_ element: AXUIElement, _ attribute: String) -> [AXUIElement]? {
        axValue(element, attribute) as? [AXUIElement]
    }

    private static func axString(_ element: AXUIElement, _ attribute: String) -> String? {
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
