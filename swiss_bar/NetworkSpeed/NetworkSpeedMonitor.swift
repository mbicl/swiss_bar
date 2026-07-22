//
//  NetworkSpeedMonitor.swift
//  swiss_bar
//

import Combine
import Foundation

/// Polls cumulative interface byte counters on a timer and derives an upload/download rate plus a
/// rolling history for the menu bar label and dropdown graph - the same `Timer`-driven poll shape
/// as `ClipboardMonitor`, since there's no notification API for interface traffic either.
@MainActor
final class NetworkSpeedMonitor: ObservableObject {
    private static let pollInterval: TimeInterval = 1.0
    private static let maxHistorySamples = 60

    @Published private(set) var uploadBytesPerSecond: Double = 0
    @Published private(set) var downloadBytesPerSecond: Double = 0
    @Published private(set) var history: [NetworkSpeedSample] = []

    private var timer: Timer?
    private var lastTotals: (inBytes: UInt64, outBytes: UInt64, date: Date)?

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.poll()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        // Dropped so the first poll after a later restart only re-baselines instead of computing
        // a rate across the stopped interval (which would read as an artificial near-zero rate).
        lastTotals = nil
    }

    private func poll() {
        let now = Date()
        let interfaces = NetworkInterfaceByteCounterReader.readAllInterfaces()
        let totals = NetworkInterfaceByteCounterReader.totalBytes(from: interfaces)
        defer { lastTotals = (totals.inBytes, totals.outBytes, now) }

        guard let last = lastTotals else { return }
        let elapsed = now.timeIntervalSince(last.date)
        let upload = NetworkRateFormatter.rate(currentBytes: totals.outBytes, previousBytes: last.outBytes, elapsed: elapsed)
        let download = NetworkRateFormatter.rate(currentBytes: totals.inBytes, previousBytes: last.inBytes, elapsed: elapsed)

        uploadBytesPerSecond = upload
        downloadBytesPerSecond = download
        let sample = NetworkSpeedSample(date: now, uploadBytesPerSecond: upload, downloadBytesPerSecond: download)
        history = Self.appending(sample, to: history, maxCount: Self.maxHistorySamples)
    }

    /// Appends a sample, trimming the oldest entries once over `maxCount` - the testable piece of
    /// the rolling-window buffer.
    nonisolated static func appending(_ sample: NetworkSpeedSample, to history: [NetworkSpeedSample], maxCount: Int) -> [NetworkSpeedSample] {
        var result = history
        result.append(sample)
        if result.count > maxCount {
            result.removeFirst(result.count - maxCount)
        }
        return result
    }
}
