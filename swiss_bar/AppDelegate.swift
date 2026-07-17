//
//  AppDelegate.swift
//  swiss_bar
//

import AppKit
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate {
    let permissionManager = AccessibilityPermissionManager()

    private let settings = AppSettings.shared
    private let switcherViewModel = SwitcherViewModel()
    private lazy var overlayController = OverlayController(viewModel: switcherViewModel)
    private let eventTapManager = EventTapManager()
    private var cancellables: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        eventTapManager.delegate = self

        // Start capturing window AX elements at creation time so windows on other Spaces stay
        // activatable regardless of whether their Space has been displayed.
        WindowTracker.shared.start()

        // Emits the current value on subscribe, so this also performs the initial install.
        settings.$windowSwitcherEnabled
            .removeDuplicates()
            .sink { [weak self] enabled in
                guard let self else { return }
                if enabled {
                    eventTapManager.install()
                } else {
                    eventTapManager.uninstall()
                }
            }
            .store(in: &cancellables)

        permissionManager.onAccessibilityGranted = { [weak self] in
            guard let self, settings.windowSwitcherEnabled else { return }
            eventTapManager.install()
            WindowEnumerator.warmElementCache()
        }

        // Cache AX elements for the windows visible right now, and again on every Space change -
        // a window can only be focused later (once it's on a non-visible Space) if we grabbed its
        // AX element while its Space was displayed.
        if permissionManager.isAccessibilityTrusted {
            WindowEnumerator.warmElementCache()
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                WindowEnumerator.warmElementCache()
            }
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
