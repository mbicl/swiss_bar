//
//  ClipboardHotkeyTapManagerTests.swift
//  swiss_barTests
//

import Testing
import CoreGraphics
@testable import swiss_bar

struct ClipboardHotkeyTapManagerTests {

    private static let vKeyCode: CGKeyCode = 9
    private static let escKeyCode: CGKeyCode = 53
    private static let returnKeyCode: CGKeyCode = 36
    private static let keypadEnterKeyCode: CGKeyCode = 76
    private static let upArrowKeyCode: CGKeyCode = 126
    private static let downArrowKeyCode: CGKeyCode = 125
    private static let unrelatedKeyCode: CGKeyCode = 0 // kVK_ANSI_A

    @Test func cmdShiftVWhileInactiveActivatesAndConsumes() {
        let result = ClipboardHotkeyTapManager.decide(
            eventType: .keyDown, keyCode: Self.vKeyCode, flags: [.maskCommand, .maskShift], isPickerActive: false
        )
        #expect(result.intent == .activate)
        #expect(result.consume == true)
        #expect(result.isPickerActive == true)
    }

    @Test func cmdVWithoutShiftWhileInactivePassesThrough() {
        let result = ClipboardHotkeyTapManager.decide(
            eventType: .keyDown, keyCode: Self.vKeyCode, flags: .maskCommand, isPickerActive: false
        )
        #expect(result.intent == nil)
        #expect(result.consume == false)
        #expect(result.isPickerActive == false)
    }

    @Test func escWhileActiveCancelsAndConsumes() {
        let result = ClipboardHotkeyTapManager.decide(
            eventType: .keyDown, keyCode: Self.escKeyCode, flags: [], isPickerActive: true
        )
        #expect(result.intent == .cancel)
        #expect(result.consume == true)
        #expect(result.isPickerActive == false)
    }

    @Test func escWhileInactivePassesThrough() {
        let result = ClipboardHotkeyTapManager.decide(
            eventType: .keyDown, keyCode: Self.escKeyCode, flags: [], isPickerActive: false
        )
        #expect(result.intent == nil)
        #expect(result.consume == false)
        #expect(result.isPickerActive == false)
    }

    @Test func returnWhileActiveCommitsAndConsumes() {
        let result = ClipboardHotkeyTapManager.decide(
            eventType: .keyDown, keyCode: Self.returnKeyCode, flags: [], isPickerActive: true
        )
        #expect(result.intent == .commit)
        #expect(result.consume == true)
        #expect(result.isPickerActive == false)
    }

    @Test func keypadEnterWhileActiveCommitsAndConsumes() {
        let result = ClipboardHotkeyTapManager.decide(
            eventType: .keyDown, keyCode: Self.keypadEnterKeyCode, flags: [], isPickerActive: true
        )
        #expect(result.intent == .commit)
        #expect(result.consume == true)
        #expect(result.isPickerActive == false)
    }

    @Test func downArrowWhileActiveMovesDown() {
        let result = ClipboardHotkeyTapManager.decide(
            eventType: .keyDown, keyCode: Self.downArrowKeyCode, flags: [], isPickerActive: true
        )
        #expect(result.intent == .move(down: true))
        #expect(result.consume == true)
        #expect(result.isPickerActive == true)
    }

    @Test func upArrowWhileActiveMovesUp() {
        let result = ClipboardHotkeyTapManager.decide(
            eventType: .keyDown, keyCode: Self.upArrowKeyCode, flags: [], isPickerActive: true
        )
        #expect(result.intent == .move(down: false))
        #expect(result.consume == true)
        #expect(result.isPickerActive == true)
    }

    @Test func unrelatedKeyWhileActiveIsConsumedWithNoIntent() {
        let result = ClipboardHotkeyTapManager.decide(
            eventType: .keyDown, keyCode: Self.unrelatedKeyCode, flags: [], isPickerActive: true
        )
        #expect(result.intent == nil)
        #expect(result.consume == true)
        #expect(result.isPickerActive == true)
    }

    @Test func unrelatedKeyWhileInactivePassesThrough() {
        let result = ClipboardHotkeyTapManager.decide(
            eventType: .keyDown, keyCode: Self.unrelatedKeyCode, flags: [], isPickerActive: false
        )
        #expect(result.intent == nil)
        #expect(result.consume == false)
        #expect(result.isPickerActive == false)
    }

    @Test func flagsChangedWhileActivePassesThroughUnchanged() {
        let result = ClipboardHotkeyTapManager.decide(
            eventType: .flagsChanged, keyCode: 0, flags: [], isPickerActive: true
        )
        #expect(result.intent == nil)
        #expect(result.consume == false)
        #expect(result.isPickerActive == true)
    }

    @Test func nonKeyEventTypePassesThroughUnchanged() {
        let result = ClipboardHotkeyTapManager.decide(
            eventType: .mouseMoved, keyCode: Self.vKeyCode, flags: [.maskCommand, .maskShift], isPickerActive: false
        )
        #expect(result.intent == nil)
        #expect(result.consume == false)
        #expect(result.isPickerActive == false)
    }
}
