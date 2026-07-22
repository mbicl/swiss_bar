//
//  NetworkSpeedChartScale.swift
//  swiss_bar
//

import Foundation

/// Pure helpers for picking a stable, human-friendly Y-axis upper bound for the dropdown graph -
/// kept separate from `NetworkRateFormatter` (which only turns a rate into a display string) since
/// this is a distinct, axis-scaling concern.
enum NetworkSpeedChartScale {
    nonisolated private static let niceSteps: [Double] = [1, 2, 5, 10]

    /// Rounds `maxValue` up to a "nice" 1/2/5/10 x 10^n bound, so the axis doesn't need to re-solve
    /// arbitrary bounds on every tick and doesn't jitter for small fluctuations. Falls back to
    /// `minimumUpperBound` for a non-positive `maxValue` so an idle connection still gets a small
    /// legible scale instead of a degenerate `0...0` domain.
    nonisolated static func niceUpperBound(forMaxValue maxValue: Double, minimumUpperBound: Double = 1024) -> Double {
        guard maxValue > 0 else { return minimumUpperBound }
        let magnitude = pow(10, floor(log10(maxValue)))
        let normalized = maxValue / magnitude
        let step = niceSteps.first(where: { $0 >= normalized }) ?? niceSteps.last!
        return step * magnitude
    }
}
