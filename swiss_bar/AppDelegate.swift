//
//  AppDelegate.swift
//  swiss_bar
//

import AppKit
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate {
    let permissionManager = AccessibilityPermissionManager()
    let keyboardCleaningManager = KeyboardCleaningManager()

    private let settings = AppSettings.shared
    private let switcherViewModel = SwitcherViewModel()
    private lazy var overlayController = OverlayController(viewModel: switcherViewModel)
    private let eventTapManager = EventTapManager()
    private var cancellables: Set<AnyCancellable> = []

    private let clipboardHistoryPersistence = ClipboardHistoryPersistence()
    private lazy var clipboardHistoryStore = ClipboardHistoryStore(
        persistence: clipboardHistoryPersistence, capacity: settings.clipboardHistoryCapacity
    )
    private lazy var clipboardMonitor = ClipboardMonitor(store: clipboardHistoryStore, persistence: clipboardHistoryPersistence)
    private let clipboardPickerViewModel = ClipboardPickerViewModel()
    private lazy var clipboardOverlayController = ClipboardPickerOverlayController(
        viewModel: clipboardPickerViewModel, persistence: clipboardHistoryPersistence
    )
    private let clipboardHotkeyTap = ClipboardHotkeyTapManager()
    /// Tracks whether the Window Switcher HUD is currently up - ⌘ is held throughout a ⌘Tab
    /// session, so ⌘⇧V is physically typeable mid-switch, and the clipboard picker must not open
    /// on top of it.
    private var isSwitcherActive = false

    /// Coalesces Space-change refreshes. `activeSpaceDidChangeNotification` fires when the
    /// transition begins, while AX window visibility is still in flux (the outgoing Space's
    /// windows are gone, the incoming Space's haven't arrived), so an immediate enumeration
    /// captures an unrepresentative slice - and a fullscreen or multi-display transition emits a
    /// burst of these. Re-arming on each notification collapses the burst and lands one refresh
    /// after it settles.
    private var spaceChangeRefresh: Task<Void, Never>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        eventTapManager.delegate = self
        clipboardHotkeyTap.delegate = self
        clipboardOverlayController.onRowTapped = { [weak self] index in
            self?.commitClipboardSelection(at: index)
        }
        clipboardOverlayController.onOutsideClick = { [weak self] in
            self?.cancelClipboardPicker()
        }

        // Emits the current value on subscribe, so this also performs the initial install.
        settings.$clipboardHistoryEnabled
            .removeDuplicates()
            .sink { [weak self] enabled in
                guard let self else { return }
                if enabled {
                    clipboardHotkeyTap.install()
                    clipboardMonitor.start()
                } else {
                    clipboardHotkeyTap.uninstall()
                    clipboardMonitor.stop()
                }
            }
            .store(in: &cancellables)

        settings.$clipboardHistoryCapacity
            .removeDuplicates()
            .sink { [weak self] capacity in
                self?.clipboardHistoryStore.setCapacity(capacity)
            }
            .store(in: &cancellables)

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
            guard let self else { return }
            if settings.windowSwitcherEnabled {
                eventTapManager.install()
                WindowEnumerator.warmElementCache()
                WindowEnumerator.refreshCache()
                WindowTracker.shared.seedMRU(WindowEnumerator.onScreenWindowIDsFrontToBack())
            }
            if settings.clipboardHistoryEnabled {
                clipboardHotkeyTap.install()
            }
        }

        // Cache AX elements for the windows visible right now, and again on every Space change -
        // a window can only be focused later (once it's on a non-visible Space) if we grabbed its
        // AX element while its Space was displayed. Also seed the MRU order with the current
        // z-order so the very first switcher invocation of a session has a deterministic list
        // instead of falling back to the ambiguous bounds-matching heuristic.
        if permissionManager.isAccessibilityTrusted {
            WindowEnumerator.warmElementCache()
            WindowEnumerator.refreshCache()
            WindowTracker.shared.seedMRU(WindowEnumerator.onScreenWindowIDsFrontToBack())
        }

        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.scheduleSpaceChangeRefresh()
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
        keyboardCleaningManager.stop()
        clipboardHotkeyTap.uninstall()
        clipboardMonitor.stop()
        spaceChangeRefresh?.cancel()
    }

    private func commitClipboardSelection(at index: Int) {
        clipboardHotkeyTap.deactivate()
        clipboardOverlayController.hide()
        guard clipboardPickerViewModel.items.indices.contains(index) else { return }
        let selected = clipboardPickerViewModel.items[index]
        if settings.clipboardHistoryReorderOnPaste {
            clipboardHistoryStore.promoteToTop(selected)
        }
        ClipboardPasteExecutor.paste(selected, monitor: clipboardMonitor, persistence: clipboardHistoryPersistence)
    }

    private func cancelClipboardPicker() {
        clipboardHotkeyTap.deactivate()
        clipboardOverlayController.hide()
    }

    private func scheduleSpaceChangeRefresh() {
        spaceChangeRefresh?.cancel()
        spaceChangeRefresh = Task { @MainActor in
            // Roughly the length of a fullscreen Space transition; shorter and the enumeration
            // still lands mid-animation, longer and a ⌘Tab right after a Space change sees a
            // stale ordering (the list itself stays complete thanks to refreshCache's carry-over).
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            WindowEnumerator.warmElementCache()
            WindowEnumerator.refreshCache()
            WindowTracker.shared.prune()
            WindowTracker.shared.seedMRU(WindowEnumerator.onScreenWindowIDsFrontToBack())
        }
    }
}

extension AppDelegate: EventTapManagerDelegate {
    func switcherDidActivate() {
        isSwitcherActive = true
        // Cheap, AX-free re-order of the already-cached list - shows instantly and never risks
        // blocking the event-tap callback on a live AX enumeration (see WindowEnumerator.refreshCache).
        let candidates = WindowEnumerator.reorderedCache()
        overlayController.show(with: candidates)
        overlayController.updateSelection(candidates.count > 1 ? 1 : 0)

        // Bring the *cache* up to full accuracy (new/closed windows) in the background, deferred
        // via Task so it runs after this callback returns, off the tap's synchronous call stack.
        // Deliberately does NOT touch `switcherViewModel.candidates` here: replacing the on-screen
        // list while the HUD is already up and the user is mid-Tab is what caused the list to
        // visibly reshuffle/jump. The list shown is frozen as of activation; refreshed cache state
        // is picked up on the *next* activation instead.
        Task { @MainActor in
            WindowEnumerator.refreshCache()
        }
    }

    func switcherDidAdvance(forward: Bool) {
        switcherViewModel.advance(forward: forward)
    }

    func switcherDidCommit() {
        isSwitcherActive = false
        overlayController.hide()
        guard switcherViewModel.candidates.indices.contains(switcherViewModel.selectedIndex) else { return }
        let selected = switcherViewModel.candidates[switcherViewModel.selectedIndex]
        WindowActivator.activate(selected)
        if let windowID = selected.windowID {
            WindowTracker.shared.markFocused(windowID)
        }
        Task { @MainActor in WindowEnumerator.refreshCache() }
    }

    func switcherDidCancel() {
        isSwitcherActive = false
        overlayController.hide()
        Task { @MainActor in WindowEnumerator.refreshCache() }
    }
}

extension AppDelegate: ClipboardHotkeyTapDelegate {
    func clipboardPickerDidActivate() {
        guard !isSwitcherActive, !clipboardHistoryStore.items.isEmpty else {
            clipboardHotkeyTap.deactivate()
            return
        }
        clipboardOverlayController.show(with: clipboardHistoryStore.items)
    }

    func clipboardPickerDidMove(down: Bool) {
        clipboardPickerViewModel.move(down: down)
    }

    func clipboardPickerDidCommit() {
        commitClipboardSelection(at: clipboardPickerViewModel.selectedIndex)
    }

    func clipboardPickerDidCancel() {
        cancelClipboardPicker()
    }
}
