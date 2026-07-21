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

    private func makeCandidate(_ title: String, windowID: CGWindowID? = nil, isMinimized: Bool = false) -> CandidateWindow {
        CandidateWindow(
            axElement: AXUIElementCreateApplication(0),
            windowID: windowID,
            title: title,
            appName: "App",
            appIcon: nil,
            pid: 0,
            isMinimized: isMinimized
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

    @Test func isDuplicateTrueForMatchingPidAndBoundsOfIDLessWindow() {
        // knownBounds only ever holds AX windows whose CGWindowID was unresolvable (see
        // dedupKeys) - for those, pid + frame is the only identity available.
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

    // MARK: - dedupKeys

    @Test func dedupKeysRecordsBoundsOnlyForIDLessWindows() {
        let full = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let keys = WindowEnumerator.dedupKeys(for: [
            .init(pid: 42, windowID: 101, bounds: full),
            .init(pid: 42, windowID: 102, bounds: full),
        ])
        #expect(keys.ids == [101, 102])
        #expect(keys.bounds.isEmpty)
    }

    @Test func dedupKeysFullscreenSiblingIsNotDroppedAsDuplicate() {
        // The reported bug: two fullscreen VSCode windows share the identical full-display
        // frame. The second arrives from Quartz with its own valid ID and must survive dedup.
        let full = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let keys = WindowEnumerator.dedupKeys(for: [.init(pid: 42, windowID: 101, bounds: full)])
        #expect(!WindowEnumerator.isDuplicate(
            windowID: 102, pid: 42, bounds: full,
            knownIDs: keys.ids, knownBounds: keys.bounds
        ))
    }

    @Test func dedupKeysKeepsBoundsForUnresolvableID() {
        let rect = CGRect(x: 10, y: 10, width: 400, height: 300)
        let keys = WindowEnumerator.dedupKeys(for: [.init(pid: 7, windowID: nil, bounds: rect)])
        #expect(keys.ids.isEmpty)
        #expect(keys.bounds.count == 1)
        #expect(keys.bounds[0].pid == 7)
    }

    @Test func dedupKeysSkipsIDLessWindowWithNoBounds() {
        #expect(WindowEnumerator.dedupKeys(for: [.init(pid: 7, windowID: nil, bounds: nil)]).bounds.isEmpty)
    }

    // MARK: - carryingOverStillLive

    @Test func carryOverKeepsWindowsAXStoppedReportingButQuartzStillLists() {
        let fresh = [makeCandidate("fullscreen", windowID: 1)]
        let previous = [makeCandidate("fullscreen", windowID: 1), makeCandidate("desktop", windowID: 2)]
        let result = WindowEnumerator.carryingOverStillLive(fresh: fresh, previous: previous, liveIDs: [1, 2])
        #expect(result.map(\.title) == ["fullscreen", "desktop"])
    }

    @Test func carryOverDropsWindowsThatNoLongerExist() {
        let fresh = [makeCandidate("a", windowID: 1)]
        let previous = [makeCandidate("a", windowID: 1), makeCandidate("closed", windowID: 2)]
        let result = WindowEnumerator.carryingOverStillLive(fresh: fresh, previous: previous, liveIDs: [1])
        #expect(result.map(\.title) == ["a"])
    }

    @Test func carryOverSkippedWhenLiveIDLookupFails() {
        let fresh = [makeCandidate("a", windowID: 1)]
        let previous = [makeCandidate("a", windowID: 1), makeCandidate("b", windowID: 2)]
        #expect(WindowEnumerator.carryingOverStillLive(fresh: fresh, previous: previous, liveIDs: []).count == 1)
    }

    @Test func carryOverIgnoresCandidatesWithoutWindowID() {
        let previous = [makeCandidate("noID", windowID: nil)]
        #expect(WindowEnumerator.carryingOverStillLive(fresh: [], previous: previous, liveIDs: [1]).isEmpty)
    }

    @Test func carryOverPlacesCarriedWindowsBeforeMinimizedOnes() {
        let fresh = [makeCandidate("visible", windowID: 1), makeCandidate("min", windowID: 3, isMinimized: true)]
        let previous = [makeCandidate("carried", windowID: 2)]
        let result = WindowEnumerator.carryingOverStillLive(fresh: fresh, previous: previous, liveIDs: [1, 2, 3])
        #expect(result.map(\.title) == ["visible", "carried", "min"])
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

    // MARK: - orderByMRU

    @Test func orderByMRUOnlyMovesThePromotedWindowOthersKeepRelativeOrder() {
        let a = makeCandidate("A", windowID: 1)
        let b = makeCandidate("B", windowID: 2)
        let c = makeCandidate("C", windowID: 3)
        // Simulates "C was just promoted to front" - A and B's relative order (A before B) is
        // unchanged even though their absolute rank shifted.
        let mruIndex: [CGWindowID: Int] = [3: 0, 1: 1, 2: 2]
        let result = WindowEnumerator.orderByMRU([a, b, c], mruIndex: mruIndex, unknownRank: mruIndex.count)
        #expect(result.map(\.title) == ["C", "A", "B"])
    }

    @Test func orderByMRUUnknownWindowsKeepCacheOrderAfterKnownOnes() {
        let unknown1 = makeCandidate("unknown1", windowID: 2)
        let known = makeCandidate("known", windowID: 1)
        let unknown2 = makeCandidate("unknown2", windowID: 3)
        let mruIndex: [CGWindowID: Int] = [1: 0]
        let result = WindowEnumerator.orderByMRU([unknown1, known, unknown2], mruIndex: mruIndex, unknownRank: mruIndex.count)
        #expect(result.map(\.title) == ["known", "unknown1", "unknown2"])
    }

    @Test func orderByMRUMinimizedAlwaysSortsLastRegardlessOfRank() {
        let minimized = makeCandidate("minimized", windowID: 1, isMinimized: true)
        let visible = makeCandidate("visible", windowID: 2)
        // minimized has the best possible MRU rank but must still sort after visible windows.
        let mruIndex: [CGWindowID: Int] = [1: 0]
        let result = WindowEnumerator.orderByMRU([minimized, visible], mruIndex: mruIndex, unknownRank: mruIndex.count)
        #expect(result.map(\.title) == ["visible", "minimized"])
    }

    @Test func orderByMRUCandidateWithNoWindowIDTreatedAsUnknown() {
        let noID = makeCandidate("noID", windowID: nil)
        let known = makeCandidate("known", windowID: 1)
        let mruIndex: [CGWindowID: Int] = [1: 0]
        let result = WindowEnumerator.orderByMRU([noID, known], mruIndex: mruIndex, unknownRank: mruIndex.count)
        #expect(result.map(\.title) == ["known", "noID"])
    }

    @Test func orderByMRUWithEmptyMRUIndexPreservesInputOrder() {
        let a = makeCandidate("A", windowID: 1)
        let b = makeCandidate("B", windowID: 2)
        let result = WindowEnumerator.orderByMRU([a, b], mruIndex: [:], unknownRank: 0)
        #expect(result.map(\.title) == ["A", "B"])
    }
}
