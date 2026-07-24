//
//  LaunchAtLoginManagerTests.swift
//  swiss_barTests
//

import ServiceManagement
import Testing
@testable import swiss_bar

@MainActor
struct LaunchAtLoginManagerTests {
    private struct StubError: Error {}

    private final class FakeLoginItemService: LoginItemService {
        var status: SMAppService.Status
        private(set) var registerCallCount = 0
        private(set) var unregisterCallCount = 0
        var registerError: Error?
        var unregisterError: Error?

        init(status: SMAppService.Status = .notRegistered) {
            self.status = status
        }

        func register() throws {
            registerCallCount += 1
            if let registerError { throw registerError }
            status = .enabled
        }

        func unregister() throws {
            unregisterCallCount += 1
            if let unregisterError { throw unregisterError }
            status = .notRegistered
        }
    }

    @Test func defaultsToDisabledWhenNotRegistered() {
        let manager = LaunchAtLoginManager(service: FakeLoginItemService())
        #expect(manager.isEnabled == false)
        #expect(manager.requiresApproval == false)
    }

    @Test func enablingRegistersAndReflectsEnabledStatus() {
        let fake = FakeLoginItemService()
        let manager = LaunchAtLoginManager(service: fake)

        manager.setEnabled(true)

        #expect(fake.registerCallCount == 1)
        #expect(manager.isEnabled == true)
    }

    @Test func disablingUnregisters() {
        let fake = FakeLoginItemService(status: .enabled)
        let manager = LaunchAtLoginManager(service: fake)
        #expect(manager.isEnabled == true)

        manager.setEnabled(false)

        #expect(fake.unregisterCallCount == 1)
        #expect(manager.isEnabled == false)
    }

    @Test func requiresApprovalStatusIsSurfaced() {
        let fake = FakeLoginItemService(status: .requiresApproval)
        let manager = LaunchAtLoginManager(service: fake)
        #expect(manager.requiresApproval == true)
        #expect(manager.isEnabled == false)
    }

    @Test func failedRegisterLeavesStatusReflectingWhatActuallyHappened() {
        let fake = FakeLoginItemService()
        fake.registerError = StubError()
        let manager = LaunchAtLoginManager(service: fake)

        manager.setEnabled(true)

        #expect(fake.registerCallCount == 1)
        #expect(manager.isEnabled == false)
    }
}
