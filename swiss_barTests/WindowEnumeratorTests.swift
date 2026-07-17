//
//  WindowEnumeratorTests.swift
//  swiss_barTests
//

import Testing
import CoreGraphics
import ApplicationServices
@testable import swiss_bar

@MainActor
struct WindowEnumeratorTests {

    private func makeCandidate(_ title: String) -> CandidateWindow {
        CandidateWindow(
            axElement: AXUIElementCreateApplication(0),
            windowID: nil,
            title: title,
            appName: "App",
            appIcon: nil,
            pid: 0,
            isMinimized: false
        )
    }

    // MARK: - boundsMatch

    @Test func boundsMatchExactRectsMatch() {
        let rect = CGRect(x: 0, y: 0, width: 100, height: 100)
        #expect(WindowEnumerator.boundsMatch(rect, rect))
    }

    @Test func boundsMatchWithinToleranceMatches() {
        let a = CGRect(x: 0, y: 0, width: 100, height: 100)
        let b = CGRect(x: 1, y: 1, width: 101, height: 101)
        #expect(WindowEnumerator.boundsMatch(a, b))
    }

    @Test func boundsMatchAtToleranceBoundaryDoesNotMatch() {
        let a = CGRect(x: 0, y: 0, width: 100, height: 100)
        let b = CGRect(x: 2, y: 0, width: 100, height: 100)
        #expect(!WindowEnumerator.boundsMatch(a, b))
    }

    @Test func boundsMatchDiffersOnEachDimension() {
        let a = CGRect(x: 0, y: 0, width: 100, height: 100)
        #expect(!WindowEnumerator.boundsMatch(a, CGRect(x: 0, y: 5, width: 100, height: 100)))
        #expect(!WindowEnumerator.boundsMatch(a, CGRect(x: 0, y: 0, width: 105, height: 100)))
        #expect(!WindowEnumerator.boundsMatch(a, CGRect(x: 0, y: 0, width: 100, height: 105)))
    }

    @Test func boundsMatchNilComparisonNeverMatches() {
        #expect(!WindowEnumerator.boundsMatch(.zero, nil))
    }

    // MARK: - isDuplicate

    @Test func isDuplicateTrueForKnownWindowID() {
        // Window ID match must win even when bounds don't match anything known.
        #expect(WindowEnumerator.isDuplicate(
            windowID: 101, pid: 42, bounds: .zero,
            knownIDs: [101], knownBounds: []
        ))
    }

    @Test func isDuplicateTrueForMatchingPidAndBounds() {
        let pid: pid_t = 42
        let bounds = CGRect(x: 0, y: 0, width: 100, height: 100)
        #expect(WindowEnumerator.isDuplicate(
            windowID: 999, pid: pid, bounds: bounds,
            knownIDs: [], knownBounds: [(pid: pid, bounds: bounds)]
        ))
    }

    @Test func isDuplicateFalseForDifferentPid() {
        let bounds = CGRect(x: 0, y: 0, width: 100, height: 100)
        let otherPid: pid_t = 7
        #expect(!WindowEnumerator.isDuplicate(
            windowID: 999, pid: 42, bounds: bounds,
            knownIDs: [], knownBounds: [(pid: otherPid, bounds: bounds)]
        ))
    }

    @Test func isDuplicateFalseForDifferentBounds() {
        let pid: pid_t = 42
        let a = CGRect(x: 0, y: 0, width: 100, height: 100)
        let b = CGRect(x: 500, y: 500, width: 100, height: 100)
        #expect(!WindowEnumerator.isDuplicate(
            windowID: 999, pid: pid, bounds: b,
            knownIDs: [], knownBounds: [(pid: pid, bounds: a)]
        ))
    }

    @Test func isDuplicateFalseForUnknownIDWithNothingKnown() {
        let known: [(pid: pid_t, bounds: CGRect)] = []
        #expect(!WindowEnumerator.isDuplicate(
            windowID: 999, pid: 42, bounds: .zero,
            knownIDs: [], knownBounds: known
        ))
    }

    // MARK: - merge

    @Test func mergeOrdersVisibleByZOrderIndex() {
        let front = makeCandidate("front")
        let back = makeCandidate("back")
        let result = WindowEnumerator.merge(
            visible: [(order: 3, window: back), (order: 0, window: front)],
            offSpace: [],
            minimized: []
        )
        #expect(result.map(\.title) == ["front", "back"])
    }

    @Test func mergePlacesMinimizedAfterAllVisible() {
        let visible = makeCandidate("visible")
        let minimized = makeCandidate("minimized")
        let result = WindowEnumerator.merge(
            visible: [(order: 0, window: visible)],
            offSpace: [],
            minimized: [minimized]
        )
        #expect(result.map(\.title) == ["visible", "minimized"])
    }

    @Test func mergePlacesUnmatchedVisibleWindowsLastAmongVisibles() {
        let matched = makeCandidate("matched")
        let unmatched = makeCandidate("unmatched")
        let result = WindowEnumerator.merge(
            visible: [(order: Int.max, window: unmatched), (order: 0, window: matched)],
            offSpace: [],
            minimized: []
        )
        #expect(result.map(\.title) == ["matched", "unmatched"])
    }

    @Test func mergePlacesOffSpaceBetweenVisibleAndMinimized() {
        let visible = makeCandidate("visible")
        let offSpace = makeCandidate("offSpace")
        let minimized = makeCandidate("minimized")
        let result = WindowEnumerator.merge(
            visible: [(order: 0, window: visible)],
            offSpace: [offSpace],
            minimized: [minimized]
        )
        #expect(result.map(\.title) == ["visible", "offSpace", "minimized"])
    }

    @Test func mergeWithNoWindowsReturnsEmpty() {
        #expect(WindowEnumerator.merge(visible: [], offSpace: [], minimized: []).isEmpty)
    }
}
