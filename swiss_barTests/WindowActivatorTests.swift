//
//  WindowActivatorTests.swift
//  swiss_barTests
//

import Testing
@testable import swiss_bar

@MainActor
struct WindowActivatorTests {

    // MARK: - raiseRetryCount

    @Test func retriesFourTimesWhenSpaceSwitchSucceeded() {
        #expect(WindowActivator.raiseRetryCount(spaceSwitchSucceeded: true) == 4)
    }

    @Test func retriesOnceWhenSpaceSwitchFailed() {
        #expect(WindowActivator.raiseRetryCount(spaceSwitchSucceeded: false) == 1)
    }
}
