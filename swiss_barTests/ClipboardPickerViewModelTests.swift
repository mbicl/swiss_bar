//
//  ClipboardPickerViewModelTests.swift
//  swiss_barTests
//

import Foundation
import Testing
@testable import swiss_bar

@MainActor
struct ClipboardPickerViewModelTests {

    private func makeItems(_ count: Int) -> [ClipboardItem] {
        (0..<count).map { i in
            ClipboardItem(id: UUID(), date: Date(), contentHash: "hash\(i)", kind: .text("item\(i)"))
        }
    }

    @Test func moveOnEmptyListIsNoOp() {
        let viewModel = ClipboardPickerViewModel()
        viewModel.move(down: true)
        #expect(viewModel.selectedIndex == 0)
    }

    @Test func moveDownWrapsFromLastToFirst() {
        let viewModel = ClipboardPickerViewModel()
        viewModel.items = makeItems(3)
        viewModel.selectedIndex = 2
        viewModel.move(down: true)
        #expect(viewModel.selectedIndex == 0)
    }

    @Test func moveUpWrapsFromFirstToLast() {
        let viewModel = ClipboardPickerViewModel()
        viewModel.items = makeItems(3)
        viewModel.selectedIndex = 0
        viewModel.move(down: false)
        #expect(viewModel.selectedIndex == 2)
    }

    @Test func moveDownStepsToNextIndex() {
        let viewModel = ClipboardPickerViewModel()
        viewModel.items = makeItems(3)
        viewModel.selectedIndex = 0
        viewModel.move(down: true)
        #expect(viewModel.selectedIndex == 1)
    }

    @Test func moveWithSingleItemStaysAtZero() {
        let viewModel = ClipboardPickerViewModel()
        viewModel.items = makeItems(1)
        viewModel.selectedIndex = 0

        viewModel.move(down: true)
        #expect(viewModel.selectedIndex == 0)

        viewModel.move(down: false)
        #expect(viewModel.selectedIndex == 0)
    }
}
