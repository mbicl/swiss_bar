//
//  LaunchAtLoginManager.swift
//  swiss_bar
//

import Combine
import ServiceManagement
import os

/// Matches SMAppService's own register()/unregister()/status members exactly, so the real class
/// conforms with no shim code - only exists so tests can inject a fake instead of touching a real
/// login item.
protocol LoginItemService {
    var status: SMAppService.Status { get }
    func register() throws
    func unregister() throws
}

extension SMAppService: LoginItemService {}

/// Wraps `SMAppService.mainApp` - registers/unregisters swiss_bar as a login item without a
/// separate helper-app bundle (the pre-macOS 13 `SMLoginItemSetEnabled` approach needed one).
/// Off by default on a fresh install: a never-registered app reports `.notRegistered`, so there's
/// nothing extra to do to satisfy "disabled by default".
@MainActor
final class LaunchAtLoginManager: ObservableObject {
    @Published private(set) var isEnabled = false
    @Published private(set) var requiresApproval = false

    private static let logger = Logger(subsystem: "com.MBI.swiss-bar", category: "LaunchAtLoginManager")
    private let service: LoginItemService

    init(service: LoginItemService = SMAppService.mainApp) {
        self.service = service
        refresh()
    }

    func refresh() {
        let status = service.status
        isEnabled = status == .enabled
        requiresApproval = status == .requiresApproval
    }

    /// Errors (e.g. sandboxing/signing issues) are logged, not surfaced as UI alerts - `refresh()`
    /// after either branch means the toggle always reflects what actually happened, not what was
    /// requested, mirroring how the permission toggles in MenuBarMenuView work.
    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try service.register()
            } else {
                try service.unregister()
            }
        } catch {
            Self.logger.error("Failed to \(enabled ? "register" : "unregister", privacy: .public) login item: \(error.localizedDescription, privacy: .public)")
        }
        refresh()
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
