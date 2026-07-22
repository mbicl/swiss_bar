//
//  KeyboardCleaningManager.swift
//  swiss_bar
//

import AppKit
import Combine
import CoreGraphics
import os

/// Global `CGEventTap` that, while active, swallows every keyboard event system-wide so the
/// keyboard can be physically cleaned without triggering keystrokes. Not driven by `AppSettings` -
/// there's no persisted "enabled" flag; `start()`/`stop()` are called directly from the menu-bar
/// toggle, and state always resets to inactive on relaunch.
final class KeyboardCleaningManager: ObservableObject {
    @Published private(set) var isActive = false

    private static let logger = Logger(subsystem: "com.MBI.swiss-bar", category: "KeyboardCleaningManager")

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    /// Pure decision logic: should this event be swallowed? Kept `nonisolated` and free of
    /// `CGEvent`/`CFMachPort` dependencies so it's testable without a real event tap. The
    /// tap-disabled sentinel types must never be swallowed - the callback re-enables the tap on
    /// those instead of forwarding a decision here.
    nonisolated static func shouldConsume(eventType: CGEventType, isActive: Bool) -> Bool {
        switch eventType {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            return false
        default:
            return isActive
        }
    }

    /// Returns false if the tap couldn't be created (e.g. Accessibility not yet granted) - safe to call again later.
    @discardableResult
    func start() -> Bool {
        guard eventTap == nil else { return true }

        let eventMask = (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)
        let refcon = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let manager = Unmanaged<KeyboardCleaningManager>.fromOpaque(refcon).takeUnretainedValue()
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
        isActive = true
        Self.logger.info("Keyboard cleaning mode started")
        return true
    }

    func stop() {
        guard let tap = eventTap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        isActive = false
        Self.logger.info("Keyboard cleaning mode stopped")
    }

    func toggle() {
        if isActive {
            stop()
        } else {
            start()
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

        let consume = Self.shouldConsume(eventType: type, isActive: isActive)
        return consume ? nil : Unmanaged.passUnretained(event)
    }
}
