//
//  EventTapManager.swift
//  swiss_bar
//

import AppKit
import CoreGraphics
import os

protocol EventTapManagerDelegate: AnyObject {
    func switcherDidActivate()
    func switcherDidAdvance(forward: Bool)
    func switcherDidCommit()
    func switcherDidCancel()
}

/// Intercepts Cmd+Tab / Cmd+Shift+Tab system-wide and consumes it before the Dock's own switcher sees it.
/// Knows nothing about windows or UI - reports intents to `delegate`.
final class EventTapManager {

    /// What a raw key/flags event means to the switcher, independent of `CGEvent`/`CFMachPort` -
    /// kept pure and `nonisolated` so it's testable without a real event tap.
    enum SwitcherIntent: Equatable {
        case activate
        case advance(forward: Bool)
        case commit
        case cancel
    }

    weak var delegate: EventTapManagerDelegate?

    private static let logger = Logger(subsystem: "com.MBI.swiss-bar", category: "EventTapManager")

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
            Self.logger.warning("Event tap creation failed - Accessibility permission likely not granted yet")
            return false
        }

        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        Self.logger.info("Event tap installed")
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

    /// Pure decision logic: given the current active state and a raw key/flags event, decide what
    /// the switcher should do. No `CGEvent`/`CFMachPort` dependency - testable in isolation.
    ///
    /// - `consume`: whether the event should be swallowed (return `nil` from the tap callback) so
    ///   the Dock's own switcher never sees it. `flagsChanged` events are never consumed - only
    ///   `keyDown` can be swallowed without breaking modifier-key tracking system-wide.
    nonisolated static func decide(
        eventType: CGEventType,
        keyCode: CGKeyCode,
        flags: CGEventFlags,
        isSwitcherActive: Bool
    ) -> (intent: SwitcherIntent?, consume: Bool, isSwitcherActive: Bool) {
        if eventType == .flagsChanged {
            if isSwitcherActive && !flags.contains(.maskCommand) {
                return (.commit, false, false)
            }
            return (nil, false, isSwitcherActive)
        }

        guard eventType == .keyDown else {
            return (nil, false, isSwitcherActive)
        }

        if isSwitcherActive, keyCode == escKeyCode {
            return (.cancel, true, false)
        }

        guard flags.contains(.maskCommand), keyCode == tabKeyCode else {
            return (nil, false, isSwitcherActive)
        }

        let forward = !flags.contains(.maskShift)
        if isSwitcherActive {
            return (.advance(forward: forward), true, true)
        } else {
            return (.activate, true, true)
        }
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            Self.logger.notice("Event tap disabled (timeout or user input) - re-enabling")
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        Self.logger.notice("handle: type=\(type.rawValue) keyCode=\(keyCode) flags=\(event.flags.rawValue) isActive=\(self.isSwitcherActive)")
        let (intent, consume, newIsActive) = Self.decide(
            eventType: type,
            keyCode: keyCode,
            flags: event.flags,
            isSwitcherActive: isSwitcherActive
        )
        isSwitcherActive = newIsActive

        switch intent {
        case .activate:
            delegate?.switcherDidActivate()
        case .advance(let forward):
            delegate?.switcherDidAdvance(forward: forward)
        case .commit:
            delegate?.switcherDidCommit()
        case .cancel:
            delegate?.switcherDidCancel()
        case nil:
            break
        }

        return consume ? nil : Unmanaged.passUnretained(event)
    }
}
