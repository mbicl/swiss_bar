//
//  SwitcherViewModelTests.swift
//  swiss_barTests
//

import Testing
import ApplicationServices
@testable import swiss_bar

@MainActor
struct SwitcherViewModelTests {

    private func makeCandidates(_ count: Int) -> [CandidateWindow] {
        (0..<count).map { i in
            CandidateWindow(
                axElement: AXUIElementCreateApplication(pid_t(i)),
                windowID: nil,
                title: "Window \(i)",
                appName: "App \(i)",
                appIcon: nil,
                pid: pid_t(i),
                isMinimized: false
            )
        }
    }

    @Test func advanceOnEmptyListIsNoOp() {
        let viewModel = SwitcherViewModel()
        viewModel.advance(forward: true)
        #expect(viewModel.selectedIndex == 0)
    }

    @Test func advanceForwardWrapsFromLastToFirst() {
        let viewModel = SwitcherViewModel()
        viewModel.candidates = makeCandidates(3)
        viewModel.selectedIndex = 2
        viewModel.advance(forward: true)
        #expect(viewModel.selectedIndex == 0)
    }

    @Test func advanceBackwardWrapsFromFirstToLast() {
        let viewModel = SwitcherViewModel()
        viewModel.candidates = makeCandidates(3)
        viewModel.selectedIndex = 0
        viewModel.advance(forward: false)
        #expect(viewModel.selectedIndex == 2)
    }

    @Test func advanceForwardStepsToNextIndex() {
        let viewModel = SwitcherViewModel()
        viewModel.candidates = makeCandidates(3)
        viewModel.selectedIndex = 0
        viewModel.advance(forward: true)
        #expect(viewModel.selectedIndex == 1)
    }

    @Test func advanceBackwardStepsToPreviousIndex() {
        let viewModel = SwitcherViewModel()
        viewModel.candidates = makeCandidates(3)
        viewModel.selectedIndex = 1
        viewModel.advance(forward: false)
        #expect(viewModel.selectedIndex == 0)
    }

    @Test func advanceWithSingleCandidateStaysAtZero() {
        let viewModel = SwitcherViewModel()
        viewModel.candidates = makeCandidates(1)
        viewModel.selectedIndex = 0

        viewModel.advance(forward: true)
        #expect(viewModel.selectedIndex == 0)

        viewModel.advance(forward: false)
        #expect(viewModel.selectedIndex == 0)
    }
}
