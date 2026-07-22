//
//  KeyboardCleaningManagerTests.swift
//  swiss_barTests
//

import Testing
import CoreGraphics
@testable import swiss_bar

struct KeyboardCleaningManagerTests {

    @Test func keyDownWhileActiveIsConsumed() {
        #expect(KeyboardCleaningManager.shouldConsume(eventType: .keyDown, isActive: true) == true)
    }

    @Test func keyUpWhileActiveIsConsumed() {
        #expect(KeyboardCleaningManager.shouldConsume(eventType: .keyUp, isActive: true) == true)
    }

    @Test func flagsChangedWhileActiveIsConsumed() {
        #expect(KeyboardCleaningManager.shouldConsume(eventType: .flagsChanged, isActive: true) == true)
    }

    @Test func keyDownWhileInactivePassesThrough() {
        #expect(KeyboardCleaningManager.shouldConsume(eventType: .keyDown, isActive: false) == false)
    }

    @Test func keyUpWhileInactivePassesThrough() {
        #expect(KeyboardCleaningManager.shouldConsume(eventType: .keyUp, isActive: false) == false)
    }

    @Test func flagsChangedWhileInactivePassesThrough() {
        #expect(KeyboardCleaningManager.shouldConsume(eventType: .flagsChanged, isActive: false) == false)
    }

    @Test func tapDisabledByTimeoutIsNeverConsumedEvenWhileActive() {
        #expect(KeyboardCleaningManager.shouldConsume(eventType: .tapDisabledByTimeout, isActive: true) == false)
    }

    @Test func tapDisabledByUserInputIsNeverConsumedEvenWhileActive() {
        #expect(KeyboardCleaningManager.shouldConsume(eventType: .tapDisabledByUserInput, isActive: true) == false)
    }
}
