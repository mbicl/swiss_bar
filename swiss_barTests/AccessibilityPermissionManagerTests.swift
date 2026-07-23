//
//  AccessibilityPermissionManagerTests.swift
//  swiss_barTests
//

import Testing
@testable import swiss_bar

@MainActor
struct AccessibilityPermissionManagerTests {

    private final class FakeTrustChecker: TrustChecking {
        var isProcessTrustedValue = false
        var isInputMonitoringGrantedValue = false
        var isScreenRecordingGrantedValue = false

        func isProcessTrusted() -> Bool { isProcessTrustedValue }
        func isInputMonitoringGranted() -> Bool { isInputMonitoringGrantedValue }
        func isScreenRecordingGranted() -> Bool { isScreenRecordingGrantedValue }
    }

    @Test func onAccessibilityGrantedFiresOnFalseToTrueTransition() {
        let checker = FakeTrustChecker()
        let manager = AccessibilityPermissionManager(trustChecker: checker)
        var grantedCallCount = 0
        manager.onAccessibilityGranted = { grantedCallCount += 1 }

        checker.isProcessTrustedValue = true
        manager.refresh()

        #expect(grantedCallCount == 1)
        #expect(manager.isAccessibilityTrusted == true)
    }

    @Test func onAccessibilityGrantedDoesNotRefireOnRepeatedTrue() {
        let checker = FakeTrustChecker()
        checker.isProcessTrustedValue = true
        // init() already runs refresh() once, consuming the false -> true edge.
        let manager = AccessibilityPermissionManager(trustChecker: checker)
        var grantedCallCount = 0
        manager.onAccessibilityGranted = { grantedCallCount += 1 }

        manager.refresh()

        #expect(grantedCallCount == 0)
    }

    @Test func onAccessibilityGrantedDoesNotFireWhileStillNotTrusted() {
        let checker = FakeTrustChecker()
        let manager = AccessibilityPermissionManager(trustChecker: checker)
        var grantedCallCount = 0
        manager.onAccessibilityGranted = { grantedCallCount += 1 }

        manager.refresh()

        #expect(grantedCallCount == 0)
        #expect(manager.isAccessibilityTrusted == false)
    }

    @Test func refreshReflectsInputMonitoringState() {
        let checker = FakeTrustChecker()
        checker.isInputMonitoringGrantedValue = true
        let manager = AccessibilityPermissionManager(trustChecker: checker)

        #expect(manager.isInputMonitoringGranted == true)
    }

    @Test func refreshReflectsScreenRecordingState() {
        let checker = FakeTrustChecker()
        checker.isScreenRecordingGrantedValue = true
        let manager = AccessibilityPermissionManager(trustChecker: checker)

        #expect(manager.isScreenRecordingGranted == true)
    }

    @Test func pollIntervalIsFastWhileAnyGrantIsMissing() {
        let checker = FakeTrustChecker()
        let manager = AccessibilityPermissionManager(trustChecker: checker)

        #expect(manager.currentPollInterval == 2)
    }

    @Test func pollIntervalSlowsToSixtySecondsOnceEverythingIsGranted() {
        let checker = FakeTrustChecker()
        checker.isProcessTrustedValue = true
        checker.isInputMonitoringGrantedValue = true
        checker.isScreenRecordingGrantedValue = true
        let manager = AccessibilityPermissionManager(trustChecker: checker)

        #expect(manager.currentPollInterval == 60)
    }

    @Test func pollIntervalReturnsToFastWhenAGrantIsLost() {
        let checker = FakeTrustChecker()
        checker.isProcessTrustedValue = true
        checker.isInputMonitoringGrantedValue = true
        checker.isScreenRecordingGrantedValue = true
        let manager = AccessibilityPermissionManager(trustChecker: checker)
        #expect(manager.currentPollInterval == 60)

        checker.isScreenRecordingGrantedValue = false
        manager.refresh()

        #expect(manager.currentPollInterval == 2)
    }
}
