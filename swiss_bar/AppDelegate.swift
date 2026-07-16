//
//  AppDelegate.swift
//  swiss_bar
//

import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    let permissionManager = AccessibilityPermissionManager()

    private let switcherViewModel = SwitcherViewModel()
    private lazy var overlayController = OverlayController(viewModel: switcherViewModel)
    private let eventTapManager = EventTapManager()

    func applicationDidFinishLaunching(_ notification: Notification) {
        eventTapManager.delegate = self
        eventTapManager.install()

        permissionManager.onAccessibilityGranted = { [weak self] in
            self?.eventTapManager.install()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        eventTapManager.uninstall()
    }
}

extension AppDelegate: EventTapManagerDelegate {
    func switcherDidActivate() {
        let candidates = WindowEnumerator.enumerate()
        overlayController.show(with: candidates)
        overlayController.updateSelection(candidates.count > 1 ? 1 : 0)
    }

    func switcherDidAdvance(forward: Bool) {
        switcherViewModel.advance(forward: forward)
    }

    func switcherDidCommit() {
        overlayController.hide()
        guard switcherViewModel.candidates.indices.contains(switcherViewModel.selectedIndex) else { return }
        WindowActivator.activate(switcherViewModel.candidates[switcherViewModel.selectedIndex])
    }

    func switcherDidCancel() {
        overlayController.hide()
    }
}
