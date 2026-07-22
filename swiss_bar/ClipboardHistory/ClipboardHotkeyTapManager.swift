//
//  ClipboardHotkeyTapManager.swift
//  swiss_bar
//

import AppKit
import CoreGraphics
import os

protocol ClipboardHotkeyTapDelegate: AnyObject {
    func clipboardPickerDidActivate()
    func clipboardPickerDidMove(down: Bool)
    func clipboardPickerDidCommit()
    func clipboardPickerDidCancel()
}

/// Intercepts Cmd+Shift+V system-wide and consumes it before the frontmost app sees it (which
/// would otherwise treat it as "paste and match style" or similar). Independent of
/// `EventTapManager` - with only two stateful tap consumers in the codebase, sharing the ~40 lines
/// of `CGEvent.tapCreate`/`CFMachPort` lifecycle plumbing would be premature abstraction. The state
/// machine itself mirrors `EventTapManager`'s hold/cycle/release chord exactly (hold Cmd+Shift,
/// press V repeatedly to cycle through history, release either modifier to paste the current
/// selection) - just adapted for a two-modifier chord instead of Cmd alone.
final class ClipboardHotkeyTapManager {

    enum PickerIntent: Equatable {
        case activate
        case move(down: Bool)
        case commit
        case cancel
    }

    weak var delegate: ClipboardHotkeyTapDelegate?

    private static let logger = Logger(subsystem: "com.MBI.swiss-bar", category: "ClipboardHotkeyTapManager")

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isPickerActive = false

    nonisolated private static let vKeyCode: CGKeyCode = 9
    nonisolated private static let escKeyCode: CGKeyCode = 53
    nonisolated private static let upArrowKeyCode: CGKeyCode = 126
    nonisolated private static let downArrowKeyCode: CGKeyCode = 125

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
                let manager = Unmanaged<ClipboardHotkeyTapManager>.fromOpaque(refcon).takeUnretainedValue()
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
        Self.logger.info("Clipboard hotkey tap installed")
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
        isPickerActive = false
    }

    /// Resets the "picker is up" state from outside the keyboard path. Required because the picker
    /// can be dismissed by mouse (row click, click-outside) or refused (e.g. empty history) - without
    /// this, the tap's internal state would stay "active" and keep swallowing all keyboard input.
    func deactivate() {
        isPickerActive = false
    }

    /// Pure decision logic: given the current active state and a raw key/flags event, decide what
    /// the picker should do. No `CGEvent`/`CFMachPort` dependency - testable in isolation.
    ///
    /// Commit is triggered by releasing either chord modifier (Cmd or Shift), not by a keypress -
    /// mirrors `EventTapManager.decide()`'s `flagsChanged`-triggers-commit pattern for Cmd+Tab,
    /// adapted for a two-modifier chord. `consume: false` on commit: a modifier key-up carries no
    /// meaning worth swallowing and must propagate normally for system-wide modifier tracking.
    nonisolated static func decide(
        eventType: CGEventType,
        keyCode: CGKeyCode,
        flags: CGEventFlags,
        isPickerActive: Bool
    ) -> (intent: PickerIntent?, consume: Bool, isPickerActive: Bool) {
        if eventType == .flagsChanged {
            if isPickerActive, !(flags.contains(.maskCommand) && flags.contains(.maskShift)) {
                return (.commit, false, false)
            }
            return (nil, false, isPickerActive)
        }

        guard eventType == .keyDown else {
            return (nil, false, isPickerActive)
        }

        if isPickerActive, keyCode == escKeyCode {
            return (.cancel, true, false)
        }
        if isPickerActive, keyCode == upArrowKeyCode {
            return (.move(down: false), true, true)
        }
        if isPickerActive, keyCode == downArrowKeyCode {
            return (.move(down: true), true, true)
        }

        guard flags.contains(.maskCommand), flags.contains(.maskShift), keyCode == vKeyCode else {
            // Swallow everything else while the HUD is up (Return included - release is the only
            // commit trigger now) so nothing leaks to the frontmost app. Inactive: pass through.
            return (nil, isPickerActive, isPickerActive)
        }

        // Repeated V while already active cycles forward, same as EventTapManager's repeated-Tab.
        return isPickerActive ? (.move(down: true), true, true) : (.activate, true, true)
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
        let (intent, consume, newIsActive) = Self.decide(
            eventType: type, keyCode: keyCode, flags: event.flags, isPickerActive: isPickerActive
        )
        isPickerActive = newIsActive

        switch intent {
        case .activate:
            delegate?.clipboardPickerDidActivate()
        case .move(let down):
            delegate?.clipboardPickerDidMove(down: down)
        case .commit:
            delegate?.clipboardPickerDidCommit()
        case .cancel:
            delegate?.clipboardPickerDidCancel()
        case nil:
            break
        }

        return consume ? nil : Unmanaged.passUnretained(event)
    }
}
