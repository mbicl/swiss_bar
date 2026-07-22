//
//  NetworkSpeedChartScaleTests.swift
//  swiss_barTests
//

import Testing
@testable import swiss_bar

struct NetworkSpeedChartScaleTests {
    @Test func roundsUpToNearestNiceStep() {
        #expect(NetworkSpeedChartScale.niceUpperBound(forMaxValue: 73) == 100)
        #expect(NetworkSpeedChartScale.niceUpperBound(forMaxValue: 340) == 500)
        #expect(NetworkSpeedChartScale.niceUpperBound(forMaxValue: 12_400_000) == 20_000_000)
    }

    @Test func idempotentOnAlreadyNiceValue() {
        #expect(NetworkSpeedChartScale.niceUpperBound(forMaxValue: 500) == 500)
    }

    @Test func nonPositiveValueFallsBackToMinimum() {
        #expect(NetworkSpeedChartScale.niceUpperBound(forMaxValue: 0) == 1024)
        #expect(NetworkSpeedChartScale.niceUpperBound(forMaxValue: -5) == 1024)
    }

    @Test func customMinimumUpperBoundHonoredForNonPositiveInput() {
        #expect(NetworkSpeedChartScale.niceUpperBound(forMaxValue: 0, minimumUpperBound: 2048) == 2048)
        #expect(NetworkSpeedChartScale.niceUpperBound(forMaxValue: -1, minimumUpperBound: 2048) == 2048)
    }

    @Test func smallPositiveValueRoundsWithoutBeingForcedToMinimum() {
        // Below `minimumUpperBound` but still a legitimate, meaningfully-rounded scale - the floor
        // only exists to avoid a degenerate `0...0` domain when there's no traffic at all.
        #expect(NetworkSpeedChartScale.niceUpperBound(forMaxValue: 1) == 1)
    }
}
