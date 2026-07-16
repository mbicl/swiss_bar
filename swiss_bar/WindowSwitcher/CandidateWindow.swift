//
//  CandidateWindow.swift
//  swiss_bar
//

import ApplicationServices
import AppKit

struct CandidateWindow: Identifiable {
    let id = UUID()
    let axElement: AXUIElement
    let windowID: CGWindowID?
    let title: String
    let appName: String
    let appIcon: NSImage?
    let pid: pid_t
    let isMinimized: Bool
}
