//
//  CandidateWindow.swift
//  swiss_bar
//

import ApplicationServices
import AppKit

struct CandidateWindow: Identifiable {
    let id = UUID()
    /// `nil` for windows on a Space other than the currently-visible one(s) - the Accessibility
    /// API doesn't report those until the owning app is activated. `WindowActivator` resolves a
    /// live element at activation time for these.
    let axElement: AXUIElement?
    let windowID: CGWindowID?
    let title: String
    let appName: String
    let appIcon: NSImage?
    let pid: pid_t
    let isMinimized: Bool
}
