//
//  ClipboardPickerViewModel.swift
//  swiss_bar
//

import AppKit
import Combine
import Foundation

/// Main-actor confined: mutated from the hotkey-tap delegate chain (guaranteed main-thread at
/// runtime) and read by SwiftUI.
@MainActor
final class ClipboardPickerViewModel: ObservableObject {
    @Published var items: [ClipboardItem] = []
    @Published var selectedIndex: Int = 0
    /// Downscaled thumbnails keyed by item ID, decoded lazily per row as it's about to be shown -
    /// the on-disk files are full resolution, so decoding whole PNGs just to draw a list row would
    /// waste memory/time for a picker that can hold hundreds of entries.
    @Published var thumbnails: [UUID: NSImage] = [:]

    func move(down: Bool) {
        guard !items.isEmpty else { return }
        let delta = down ? 1 : -1
        selectedIndex = (selectedIndex + delta + items.count) % items.count
    }
}
