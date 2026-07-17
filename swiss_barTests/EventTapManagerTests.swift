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

    @Test func nonKeyEventTypePassesThroughUnchanged() {
        let result = EventTapManager.decide(
            eventType: .mouseMoved, keyCode: Self.tabKeyCode, flags: .maskCommand, isSwitcherActive: true
        )
        #expect(result.intent == nil)
        #expect(result.consume == false)
        #expect(result.isSwitcherActive == true)
    }
}
