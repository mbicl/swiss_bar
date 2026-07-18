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
            WindowEnumerator.refreshCache()
        }

        // Cache AX elements for the windows visible right now, and again on every Space change -
        // a window can only be focused later (once it's on a non-visible Space) if we grabbed its
        // AX element while its Space was displayed.
        if permissionManager.isAccessibilityTrusted {
            WindowEnumerator.warmElementCache()
            WindowEnumerator.refreshCache()
        }

        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in
                WindowEnumerator.warmElementCache()
                WindowEnumerator.refreshCache()
                WindowTracker.shared.prune()
            }
        }
        // Keeps the candidate cache from going stale between ⌘Tab presses, so `switcherDidActivate`
        // never has to run a live (AX-heavy) enumeration on the event-tap callback itself.
        center.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in WindowEnumerator.refreshCache() }
        }
        center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in WindowEnumerator.refreshCache() }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        eventTapManager.uninstall()
    }
}

extension AppDelegate: EventTapManagerDelegate {
    func switcherDidActivate() {
        // Cheap, AX-free re-order of the already-cached list - shows instantly and never risks
        // blocking the event-tap callback on a live AX enumeration (see WindowEnumerator.refreshCache).
        let candidates = WindowEnumerator.reorderedCache()
        overlayController.show(with: candidates)
        overlayController.updateSelection(candidates.count > 1 ? 1 : 0)

        // Bring the list up to full accuracy (new/closed windows) in the background; deferred via
        // Task so it runs after this callback returns, off the tap's synchronous call stack.
        Task { @MainActor [weak self] in
            let fresh = WindowEnumerator.refreshCache()
            guard let self, Self.identityKey(fresh) != Self.identityKey(switcherViewModel.candidates) else { return }
            switcherViewModel.candidates = fresh
        }
    }

    func switcherDidAdvance(forward: Bool) {
        switcherViewModel.advance(forward: forward)
    }

    func switcherDidCommit() {
        overlayController.hide()
        guard switcherViewModel.candidates.indices.contains(switcherViewModel.selectedIndex) else { return }
        WindowActivator.activate(switcherViewModel.candidates[switcherViewModel.selectedIndex])
        Task { @MainActor in WindowEnumerator.refreshCache() }
    }

    func switcherDidCancel() {
        overlayController.hide()
        Task { @MainActor in WindowEnumerator.refreshCache() }
    }

    /// Lightweight identity for change detection between the fast cached list and a fresh
    /// enumeration - `CandidateWindow` isn't `Equatable` and doesn't need to be just for this.
    private static func identityKey(_ candidates: [CandidateWindow]) -> [String] {
        candidates.map { "\($0.pid)|\($0.windowID ?? 0)|\($0.title)" }
    }
}
