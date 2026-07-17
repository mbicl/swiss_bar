//
//  SwitcherViewModel.swift
//  swiss_bar
//

import AppKit
import Combine
import CoreGraphics
import Foundation

final class SwitcherViewModel: ObservableObject {
    @Published var candidates: [CandidateWindow] = []
    @Published var selectedIndex: Int = 0
    /// Window thumbnails keyed by window ID, populated only when the horizontal style is in
    /// preview mode. Tiles fall back to the app icon when their window has no entry.
    @Published var previews: [CGWindowID: NSImage] = [:]

    func advance(forward: Bool) {
        guard !candidates.isEmpty else { return }
        let delta = forward ? 1 : -1
        selectedIndex = (selectedIndex + delta + candidates.count) % candidates.count
    }
}
