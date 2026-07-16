//
//  OverlayController.swift
//  swiss_bar
//

import AppKit
import SwiftUI

final class OverlayController: NSWindowController {
    private let viewModel: SwitcherViewModel

    private static let tileWidth: CGFloat = 116
    private static let panelHeight: CGFloat = 140

    init(viewModel: SwitcherViewModel) {
        self.viewModel = viewModel

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: Self.panelHeight),
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

        super.init(window: panel)

        panel.contentView = NSHostingView(rootView: SwitcherOverlayView(viewModel: viewModel))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func show(with candidates: [CandidateWindow]) {
        viewModel.candidates = candidates
        guard let panel = window, let screen = NSScreen.main else { return }

        let width = min(900, CGFloat(max(candidates.count, 1)) * Self.tileWidth + 40)
        var frame = panel.frame
        frame.size = CGSize(width: width, height: Self.panelHeight)
        frame.origin.x = screen.frame.midX - frame.width / 2
        frame.origin.y = screen.frame.midY - frame.height / 2
        panel.setFrame(frame, display: true)

        panel.orderFrontRegardless()
    }

    func updateSelection(_ index: Int) {
        viewModel.selectedIndex = index
    }

    func hide() {
        window?.orderOut(nil)
    }
}
