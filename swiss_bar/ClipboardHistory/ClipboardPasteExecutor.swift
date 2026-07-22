//
//  ClipboardPasteExecutor.swift
//  swiss_bar
//

import AppKit
import CoreGraphics
import os

/// Writes a history item back onto the general pasteboard and synthesizes a Cmd+V keystroke so it
/// lands in whatever app was frontmost when the picker was invoked. No existing code in the repo
/// posts synthetic `CGEvent`s (`WindowActivator` only taps/activates) - this is the first.
@MainActor
enum ClipboardPasteExecutor {
    private static let logger = Logger(subsystem: "com.MBI.swiss-bar", category: "ClipboardPasteExecutor")
    private static let vKeyCode: CGKeyCode = 9

    static func paste(_ item: ClipboardItem, monitor: ClipboardMonitor, persistence: ClipboardHistoryPersistence) {
        writeToPasteboard(item, persistence: persistence)
        // Must happen before anything else so the poll timer's next tick sees "no change" instead
        // of re-capturing this write as a new/duplicate history entry.
        monitor.syncAfterSelfWrite()

        waitForModifierRelease {
            postCommandV()
        }
    }

    private static func writeToPasteboard(_ item: ClipboardItem, persistence: ClipboardHistoryPersistence) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        switch item.kind {
        case .text(let text):
            pasteboard.setString(text, forType: .string)
        case .image(let fileName, _):
            guard let image = persistence.loadImage(fileName: fileName) else {
                logger.error("paste: image file missing for \(fileName, privacy: .public)")
                return
            }
            pasteboard.writeObjects([image])
        }
    }

    /// If the user commits while still physically holding Cmd/Shift (they just typed Cmd+Shift+V),
    /// the real modifier state can interfere with the synthetic Cmd+V in some apps. Polls the
    /// hardware modifier state until they're released, capped so a stuck/misreported flag can never
    /// hang the paste indefinitely.
    private static func waitForModifierRelease(then action: @escaping () -> Void) {
        let deadline = Date().addingTimeInterval(0.5)
        func poll() {
            let flags = CGEventSource.flagsState(.hidSystemState)
            let stillHeld = flags.contains(.maskCommand) || flags.contains(.maskShift)
            if !stillHeld || Date() >= deadline {
                action()
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { poll() }
        }
        poll()
    }

    private static func postCommandV() {
        guard let source = CGEventSource(stateID: .hidSystemState) else { return }
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false) else {
            return
        }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cgSessionEventTap)
        keyUp.post(tap: .cgSessionEventTap)
    }
}
