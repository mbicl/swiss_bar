//
//  OverlayController.swift
//  swiss_bar
//

import AppKit
import SwiftUI

/// Shows one HUD panel per connected screen (all bound to the same `viewModel`, so they stay in
/// sync) so the switcher is visible regardless of which monitor the user is currently looking at.
final class OverlayController {
    private let viewModel: SwitcherViewModel
    private var panels: [NSPanel] = []
    private var previewTask: Task<Void, Never>?

    init(viewModel: SwitcherViewModel) {
        self.viewModel = viewModel
    }

    func show(with candidates: [CandidateWindow]) {
        viewModel.candidates = candidates

        let style = SwitcherStyle.current
        let size = SwitcherSize.current
        let tileContent = SwitcherTileContent.current

        previewTask?.cancel()
        if style == .horizontal, tileContent == .windowPreview {
            // Keep previews from the previous activation while fresh ones stream in - a slightly
            // stale thumbnail beats flashing back to the app icon on every ⌘Tab.
            let windowIDs = candidates.compactMap(\.windowID)
            previewTask = Task { [viewModel] in
                await WindowPreviewCapturer.capturePreviews(for: windowIDs) { windowID, image in
                    viewModel.previews[windowID] = image
                }
            }
        } else {
            viewModel.previews = [:]
        }

        rebuildPanels(style: style, size: size, tileContent: tileContent)

        // Sized per screen: the same window count can fit one row on a wide monitor and need
        // three on a laptop panel.
        for (panel, screen) in zip(panels, NSScreen.screens) {
            var frame = panel.frame
            frame.size = Self.panelSize(
                style: style,
                size: size,
                tileContent: tileContent,
                candidateCount: candidates.count,
                available: screen.visibleFrame.size
            )
            frame.origin.x = screen.frame.midX - frame.width / 2
            frame.origin.y = screen.frame.midY - frame.height / 2
            panel.setFrame(frame, display: true)
            panel.orderFrontRegardless()
        }
    }

    private static let tileSpacing: CGFloat = 16
    private static let rowSpacing: CGFloat = 12
    private static let outerPadding: CGFloat = 40

    nonisolated static func panelSize(
        style: SwitcherStyle,
        size: SwitcherSize,
        tileContent: SwitcherTileContent,
        candidateCount: Int,
        available: CGSize
    ) -> CGSize {
        let count = max(candidateCount, 1)
        switch style {
        case .horizontal:
            let m = HorizontalSwitcherMetrics.metrics(size: size, content: tileContent)
            let usableWidth = available.width * 0.92
            let tilesPerRow = max(1, Int((usableWidth - outerPadding + tileSpacing) / (m.tileWidth + tileSpacing)))
            let columns = min(count, tilesPerRow)
            let rows = Int(ceil(Double(count) / Double(tilesPerRow)))
            let width = CGFloat(columns) * m.tileWidth + CGFloat(columns - 1) * tileSpacing + outerPadding
            let height = CGFloat(rows) * m.tileHeight + CGFloat(rows - 1) * rowSpacing + outerPadding
            return CGSize(width: width, height: min(height, available.height * 0.9))
        case .vertical:
            let m = VerticalSwitcherMetrics.metrics(size: size)
            let maxHeight = min(m.maxPanelHeight, available.height * 0.9)
            return CGSize(width: m.panelWidth, height: min(maxHeight, CGFloat(count) * (m.rowHeight + 2) + 24))
        }
    }

    func updateSelection(_ index: Int) {
        viewModel.selectedIndex = index
    }

    func hide() {
        previewTask?.cancel()
        panels.forEach { $0.orderOut(nil) }
    }

    /// Rebuilds from scratch on every show() - cheap for a handful of panels, and avoids stale
    /// panels/positions if a monitor was connected or disconnected (or an appearance setting
    /// changed) since the last activation.
    private func rebuildPanels(style: SwitcherStyle, size: SwitcherSize, tileContent: SwitcherTileContent) {
        panels.forEach { $0.orderOut(nil) }
        panels = NSScreen.screens.map { _ in makePanel(style: style, size: size, tileContent: tileContent) }
    }

    private func makePanel(style: SwitcherStyle, size: SwitcherSize, tileContent: SwitcherTileContent) -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 140),
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
        panel.ignoresMouseEvents = true
        panel.contentView = NSHostingView(
            rootView: SwitcherOverlayView(viewModel: viewModel, style: style, size: size, tileContent: tileContent)
        )
        return panel
    }
}
