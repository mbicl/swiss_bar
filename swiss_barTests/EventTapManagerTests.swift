//
//  EventTapManagerTests.swift
//  swiss_barTests
//

import Testing
import CoreGraphics
@testable import swiss_bar

struct EventTapManagerTests {

    private static let tabKeyCode: CGKeyCode = 48
    private static let escKeyCode: CGKeyCode = 53
    private static let unrelatedKeyCode: CGKeyCode = 0 // kVK_ANSI_A
    private static let qKeyCode: CGKeyCode = 12 // kVK_ANSI_Q
    private static let leftArrowKeyCode: CGKeyCode = 123
    private static let rightArrowKeyCode: CGKeyCode = 124
    private static let downArrowKeyCode: CGKeyCode = 125
    private static let upArrowKeyCode: CGKeyCode = 126

    @Test func cmdTabWhileInactiveActivatesAndConsumes() {
        let result = EventTapManager.decide(
            eventType: .keyDown, keyCode: Self.tabKeyCode, flags: .maskCommand, isSwitcherActive: false
        )
        #expect(result.intent == .activate)
        #expect(result.consume == true)
        #expect(result.isSwitcherActive == true)
    }

    @Test func cmdTabWhileActiveAdvancesForwardAndConsumes() {
        let result = EventTapManager.decide(
            eventType: .keyDown, keyCode: Self.tabKeyCode, flags: .maskCommand, isSwitcherActive: true
        )
        #expect(result.intent == .advance(forward: true))
        #expect(result.consume == true)
        #expect(result.isSwitcherActive == true)
    }

    @Test func cmdShiftTabWhileActiveAdvancesBackward() {
        let result = EventTapManager.decide(
            eventType: .keyDown, keyCode: Self.tabKeyCode, flags: [.maskCommand, .maskShift], isSwitcherActive: true
        )
        #expect(result.intent == .advance(forward: false))
        #expect(result.consume == true)
        #expect(result.isSwitcherActive == true)
    }

    @Test func escWhileActiveCancelsAndConsumes() {
        let result = EventTapManager.decide(
            eventType: .keyDown, keyCode: Self.escKeyCode, flags: [], isSwitcherActive: true
        )
        #expect(result.intent == .cancel)
        #expect(result.consume == true)
        #expect(result.isSwitcherActive == false)
    }

    @Test func escWhileInactivePassesThrough() {
        let result = EventTapManager.decide(
            eventType: .keyDown, keyCode: Self.escKeyCode, flags: [], isSwitcherActive: false
        )
        #expect(result.intent == nil)
        #expect(result.consume == false)
        #expect(result.isSwitcherActive == false)
    }

    @Test func commandReleaseWhileActiveCommitsWithoutConsuming() {
        let result = EventTapManager.decide(
            eventType: .flagsChanged, keyCode: 0, flags: [], isSwitcherActive: true
        )
        #expect(result.intent == .commit)
        #expect(result.consume == false)
        #expect(result.isSwitcherActive == false)
    }

    @Test func flagsChangedWithCommandStillHeldPassesThroughUnchanged() {
        let result = EventTapManager.decide(
            eventType: .flagsChanged, keyCode: 0, flags: .maskCommand, isSwitcherActive: true
        )
        #expect(result.intent == nil)
        #expect(result.consume == false)
        #expect(result.isSwitcherActive == true)
    }

    @Test func flagsChangedWhileInactivePassesThrough() {
        let result = EventTapManager.decide(
            eventType: .flagsChanged, keyCode: 0, flags: [], isSwitcherActive: false
        )
        #expect(result.intent == nil)
        #expect(result.consume == false)
        #expect(result.isSwitcherActive == false)
    }

    @Test func bareKeyDownPassesThroughUnconsumed() {
        let result = EventTapManager.decide(
            eventType: .keyDown, keyCode: Self.unrelatedKeyCode, flags: [], isSwitcherActive: false
        )
        #expect(result.intent == nil)
        #expect(result.consume == false)
        #expect(result.isSwitcherActive == false)
    }

    @Test func tabWithoutCommandPassesThrough() {
        let result = EventTapManager.decide(
            eventType: .keyDown, keyCode: Self.tabKeyCode, flags: [], isSwitcherActive: false
        )
        #expect(result.intent == nil)
        #expect(result.consume == false)
    }

    @Test func cmdQWhileActiveIsConsumedWithNoIntent() {
        // Nothing but Tab/Esc should reach the frontmost app while the HUD is up - otherwise
        // muscle-memory ⌘Q quits whatever app happens to be frontmost mid-switch.
        let result = EventTapManager.decide(
            eventType: .keyDown, keyCode: Self.qKeyCode, flags: .maskCommand, isSwitcherActive: true
        )
        #expect(result.intent == nil)
        #expect(result.consume == true)
        #expect(result.isSwitcherActive == true)
    }

    @Test func cmdQWhileInactivePassesThrough() {
        let result = EventTapManager.decide(
            eventType: .keyDown, keyCode: Self.qKeyCode, flags: .maskCommand, isSwitcherActive: false
        )
        #expect(result.intent == nil)
        #expect(result.consume == false)
        #expect(result.isSwitcherActive == false)
    }

    // MARK: - Arrow key navigation

    @Test func rightArrowWhileActiveHorizontalAdvancesForward() {
        let result = EventTapManager.decide(
            eventType: .keyDown, keyCode: Self.rightArrowKeyCode, flags: [], isSwitcherActive: true, style: .horizontal
        )
        #expect(result.intent == .advance(forward: true))
        #expect(result.consume == true)
        #expect(result.isSwitcherActive == true)
    }

    @Test func leftArrowWhileActiveHorizontalAdvancesBackward() {
        let result = EventTapManager.decide(
            eventType: .keyDown, keyCode: Self.leftArrowKeyCode, flags: [], isSwitcherActive: true, style: .horizontal
        )
        #expect(result.intent == .advance(forward: false))
        #expect(result.consume == true)
        #expect(result.isSwitcherActive == true)
    }

    @Test func downArrowWhileActiveVerticalAdvancesForward() {
        let result = EventTapManager.decide(
            eventType: .keyDown, keyCode: Self.downArrowKeyCode, flags: [], isSwitcherActive: true, style: .vertical
        )
        #expect(result.intent == .advance(forward: true))
        #expect(result.consume == true)
        #expect(result.isSwitcherActive == true)
    }

    @Test func upArrowWhileActiveVerticalAdvancesBackward() {
        let result = EventTapManager.decide(
            eventType: .keyDown, keyCode: Self.upArrowKeyCode, flags: [], isSwitcherActive: true, style: .vertical
        )
        #expect(result.intent == .advance(forward: false))
        #expect(result.consume == true)
        #expect(result.isSwitcherActive == true)
    }

    @Test func upDownArrowsWhileActiveHorizontalAreConsumedButNoOp() {
        // Wrong axis for this style - swallowed like any other key while active, but no navigation.
        for keyCode in [Self.upArrowKeyCode, Self.downArrowKeyCode] {
            let result = EventTapManager.decide(
                eventType: .keyDown, keyCode: keyCode, flags: [], isSwitcherActive: true, style: .horizontal
            )
            #expect(result.intent == nil)
            #expect(result.consume == true)
            #expect(result.isSwitcherActive == true)
        }
    }

    @Test func leftRightArrowsWhileActiveVerticalAreConsumedButNoOp() {
        for keyCode in [Self.leftArrowKeyCode, Self.rightArrowKeyCode] {
            let result = EventTapManager.decide(
                eventType: .keyDown, keyCode: keyCode, flags: [], isSwitcherActive: true, style: .vertical
            )
            #expect(result.intent == nil)
            #expect(result.consume == true)
            #expect(result.isSwitcherActive == true)
        }
    }

    @Test func rightArrowWhileInactivePassesThrough() {
        let result = EventTapManager.decide(
            eventType: .keyDown, keyCode: Self.rightArrowKeyCode, flags: [], isSwitcherActive: false, style: .horizontal
        )
        #expect(result.intent == nil)
        #expect(result.consume == false)
        #expect(result.isSwitcherActive == false)
    }

    @Test func nonKeyEventTypePassesThroughUnchanged() {
        let result = EventTapManager.decide(
            eventType: .mouseMoved, keyCode: Self.tabKeyCode, flags: .maskCommand, isSwitcherActive: true
        )
        #expect(result.intent == nil)
        #expect(result.consume == false)
        #expect(result.isSwitcherActive == true)
    }
}
