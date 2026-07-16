//
//  SwitcherViewModel.swift
//  swiss_bar
//

import Combine
import Foundation

final class SwitcherViewModel: ObservableObject {
    @Published var candidates: [CandidateWindow] = []
    @Published var selectedIndex: Int = 0

    func advance(forward: Bool) {
        guard !candidates.isEmpty else { return }
        let delta = forward ? 1 : -1
        selectedIndex = (selectedIndex + delta + candidates.count) % candidates.count
    }
}
