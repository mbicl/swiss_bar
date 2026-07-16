//
//  EventTapManager.swift
//  swiss_bar
//

import AppKit
import CoreGraphics

protocol EventTapManagerDelegate: AnyObject {
    func switcherDidActivate()
    func switcherDidAdvance(forward: Bool)
    func switcherDidCommit()
    func switcherDidCancel()
}

/// Intercepts Cmd+Tab / Cmd+Shift+Tab system-wide and consumes it before the Dock's own switcher sees it.
/// Knows nothing about windows or UI - reports intents to `delegate`.
final class EventTapManager {

    weak var delegate: EventTapManagerDelegate?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isSwitcherActive = false

    private static let tabKeyCode: CGKeyCode = 48
    private static let escKeyCode: CGKeyCode = 53

    /// Returns false if the tap couldn't be created (e.g. Accessibility not yet granted) - safe to call again later.
    @discardableResult
    func install() -> Bool {
        guard eventTap == nil else { return true }

        let eventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.flagsChanged.rawValue)
        let refcon = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let manager = Unmanaged<EventTapManager>.fromOpaque(refcon).takeUnretainedValue()
                return manager.handle(type: type, event: event)
            },
            userInfo: refcon
        ) else {
            return false
        }

        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func uninstall() {
        guard let tap = eventTap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        isSwitcherActive = false
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        if type == .flagsChanged {
            if isSwitcherActive && !event.flags.contains(.maskCommand) {
                isSwitcherActive = false
                delegate?.switcherDidCommit()
            }
            return Unmanaged.passUnretained(event)
        }

        guard type == .keyDown else {
            return Unmanaged.passUnretained(event)
        }

        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags

        if isSwitcherActive, keyCode == Self.escKeyCode {
            isSwitcherActive = false
            delegate?.switcherDidCancel()
            return nil
        }

        guard flags.contains(.maskCommand), keyCode == Self.tabKeyCode else {
            return Unmanaged.passUnretained(event)
        }

        let forward = !flags.contains(.maskShift)
        if isSwitcherActive {
            delegate?.switcherDidAdvance(forward: forward)
        } else {
            isSwitcherActive = true
            delegate?.switcherDidActivate()
        }
        return nil
    }
}
