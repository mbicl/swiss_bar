//
//  NetworkRateFormatter.swift
//  swiss_bar
//

import Foundation

/// Pure helpers for turning raw byte counters into a displayable rate - kept free of
/// `NetworkSpeedMonitor`'s timer/state so they're directly unit-testable.
enum NetworkRateFormatter {
    /// Bytes/sec from a pair of cumulative counter reads. Clamped to zero when the counter went
    /// backwards (an interface reset/reconnect) or `elapsed` is non-positive (a spurious double-fire).
    nonisolated static func rate(currentBytes: UInt64, previousBytes: UInt64, elapsed: TimeInterval) -> Double {
        guard elapsed > 0, currentBytes >= previousBytes else { return 0 }
        return Double(currentBytes - previousBytes) / elapsed
    }

    nonisolated private static let units = ["B/s", "KB/s", "MB/s", "GB/s"]

    /// Auto-scales B/s up through GB/s (base-1024) so the string stays readable at any throughput,
    /// e.g. `"6.74 KB/s"`, `"11.83 MB/s"`. Pass `decimals` to override the default (0 for B/s, 2
    /// otherwise) - e.g. the graph's axis labels round to whole numbers.
    nonisolated static func string(forBytesPerSecond bytesPerSecond: Double, decimals: Int? = nil) -> String {
        var value = bytesPerSecond
        var unitIndex = 0
        while value >= 1024, unitIndex < units.count - 1 {
            value /= 1024
            unitIndex += 1
        }
        let resolvedDecimals = decimals ?? (unitIndex == 0 ? 0 : 2)
        return String(format: "%.\(resolvedDecimals)f %@", value, units[unitIndex])
    }
}
