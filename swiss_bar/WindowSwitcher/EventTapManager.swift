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

    // Read only from the `nonisolated` decide(...) below (kept nonisolated for testability
    // without a real event tap) - nonisolated themselves so that access type-checks.
    nonisolated private static let tabKeyCode: CGKeyCode = 48
    nonisolated private static let escKeyCode: CGKeyCode = 53
    nonisolated private static let leftArrowKeyCode: CGKeyCode = 123
    nonisolated private static let rightArrowKeyCode: CGKeyCode = 124
    nonisolated private static let downArrowKeyCode: CGKeyCode = 125
    nonisolated private static let upArrowKeyCode: CGKeyCode = 126

    private enum ArrowKey {
        case left, right, up, down
    }

    nonisolated private static func arrowKey(for keyCode: CGKeyCode) -> ArrowKey? {
        switch keyCode {
        case leftArrowKeyCode: return .left
        case rightArrowKeyCode: return .right
        case upArrowKeyCode: return .up
        case downArrowKeyCode: return .down
        default: return nil
        }
    }

    /// Which arrow keys navigate depends on the switcher's visual layout - left/right in the
    /// horizontal row of tiles, up/down in the vertical list - since those are the only ones that
    /// correspond to a visible direction in that layout. Returns nil for the other axis's arrows,
    /// which are still consumed (Step 5's catch-all) but don't move the selection.
    nonisolated private static func advanceDirection(for arrow: ArrowKey, style: SwitcherStyle) -> Bool? {
        switch (style, arrow) {
        case (.horizontal, .left): return false
        case (.horizontal, .right): return true
        case (.vertical, .up): return false
        case (.vertical, .down): return true
        default: return nil
        }
    }

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
        isSwitcherActive: Bool,
        style: SwitcherStyle = .horizontal
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

        if isSwitcherActive, let arrow = arrowKey(for: keyCode) {
            if let forward = advanceDirection(for: arrow, style: style) {
                return (.advance(forward: forward), true, true)
            }
            // Wrong-axis arrow for this style: consumed like any other key while active, no-op.
            return (nil, true, true)
        }

        guard flags.contains(.maskCommand), keyCode == tabKeyCode else {
            // While the switcher is active, swallow every other keyDown (⌘Q, ⌘H, typing, ...) so
            // nothing leaks to the frontmost app while the HUD is up. Inactive: pass through as normal.
            return (nil, isSwitcherActive, isSwitcherActive)
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
            isSwitcherActive: isSwitcherActive,
            style: SwitcherStyle.current
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
