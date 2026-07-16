//
//  WindowActivator.swift
//  swiss_bar
//

import AppKit
import ApplicationServices

enum WindowActivator {

    static func activate(_ window: CandidateWindow) {
        if window.isMinimized {
            AXUIElementSetAttributeValue(window.axElement, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        }
        AXUIElementPerformAction(window.axElement, kAXRaiseAction as CFString)
        NSRunningApplication(processIdentifier: window.pid)?.activate(options: [])
    }
}
