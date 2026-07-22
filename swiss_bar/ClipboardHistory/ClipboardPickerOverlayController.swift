//
//  ClipboardPickerOverlayController.swift
//  swiss_bar
//

import AppKit
import SwiftUI

/// Shows one HUD panel per connected screen, structurally a clone of the Window Switcher's
/// `OverlayController`. Two deliberate differences: rows are mouse-clickable (`ignoresMouseEvents
/// = false`), and a global mouse-down monitor cancels the picker when the user clicks outside it -
/// neither is needed by the switcher's keyboard-only tile grid.
@MainActor
final class ClipboardPickerOverlayController {
    private let viewModel: ClipboardPickerViewModel
    private let persistence: ClipboardHistoryPersistence
    private var panels: [NSPanel] = []
    private var outsideClickMonitor: Any?

    /// Fired when a row is clicked - index into `viewModel.items`.
    var onRowTapped: ((Int) -> Void)?
    var onOutsideClick: (() -> Void)?

    nonisolated private static let panelWidth: CGFloat = 420
    nonisolated private static let maxPanelHeightFraction: CGFloat = 0.7
    nonisolated private static let rowHeight: CGFloat = 42

    init(viewModel: ClipboardPickerViewModel, persistence: ClipboardHistoryPersistence) {
        self.viewModel = viewModel
        self.persistence = persistence
    }

    func show(with items: [ClipboardItem]) {
        viewModel.items = items
        viewModel.selectedIndex = 0
        viewModel.thumbnails = [:]

        rebuildPanels()

        for (panel, screen) in zip(panels, NSScreen.screens) {
            var frame = panel.frame
            frame.size = Self.panelSize(itemCount: items.count, available: screen.visibleFrame.size)
            frame.origin.x = screen.frame.midX - frame.width / 2
            frame.origin.y = screen.frame.midY - frame.height / 2
            panel.setFrame(frame, display: true)
            panel.orderFrontRegardless()
        }

        installOutsideClickMonitor()
    }

    nonisolated static func panelSize(itemCount: Int, available: CGSize) -> CGSize {
        let count = max(itemCount, 1)
        let maxHeight = available.height * maxPanelHeightFraction
        let height = min(maxHeight, CGFloat(count) * (rowHeight + 2) + 24)
        return CGSize(width: panelWidth, height: height)
    }

    func updateSelection(_ index: Int) {
        viewModel.selectedIndex = index
    }

    func hide() {
        removeOutsideClickMonitor()
        panels.forEach { $0.orderOut(nil) }
    }

    private func rebuildPanels() {
        panels.forEach { $0.orderOut(nil) }
        panels = NSScreen.screens.map { _ in makePanel() }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: Self.panelWidth, height: 200),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = false
        panel.contentView = NSHostingView(
            rootView: ClipboardPickerOverlayView(
                viewModel: viewModel,
                persistence: persistence,
                onRowTapped: { [weak self] index in self?.onRowTapped?(index) }
            )
        )
        return panel
    }

    /// Global monitor only: a click "outside" the picker necessarily lands in another app's window
    /// (our panels are the only windows this `.accessory` app has), so a global-only monitor -
    /// which observes without consuming - already covers every outside-click case.
    private func installOutsideClickMonitor() {
        removeOutsideClickMonitor()
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            Task { @MainActor in self?.onOutsideClick?() }
        }
    }

    private func removeOutsideClickMonitor() {
        if let outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
        }
        outsideClickMonitor = nil
    }
}
