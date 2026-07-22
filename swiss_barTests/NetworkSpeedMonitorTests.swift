//
//  NetworkSpeedMonitorTests.swift
//  swiss_barTests
//

import Foundation
import Testing
@testable import swiss_bar

struct NetworkSpeedMonitorTests {
    @Test func appendsUnderCap() {
        let history = [NetworkSpeedSample(date: Date(), uploadBytesPerSecond: 1, downloadBytesPerSecond: 1)]
        let sample = NetworkSpeedSample(date: Date(), uploadBytesPerSecond: 2, downloadBytesPerSecond: 2)

        let result = NetworkSpeedMonitor.appending(sample, to: history, maxCount: 60)

        #expect(result.count == 2)
        #expect(result.last?.uploadBytesPerSecond == 2)
    }

    @Test func trimsOldestWhenOverCap() {
        let history = (0..<60).map {
            NetworkSpeedSample(date: Date(), uploadBytesPerSecond: Double($0), downloadBytesPerSecond: Double($0))
        }
        let sample = NetworkSpeedSample(date: Date(), uploadBytesPerSecond: 999, downloadBytesPerSecond: 999)

        let result = NetworkSpeedMonitor.appending(sample, to: history, maxCount: 60)

        #expect(result.count == 60)
        #expect(result.first?.uploadBytesPerSecond == 1)
        #expect(result.last?.uploadBytesPerSecond == 999)
    }

    @Test func noOpWhenUnderCap() {
        let history: [NetworkSpeedSample] = []
        let sample = NetworkSpeedSample(date: Date(), uploadBytesPerSecond: 5, downloadBytesPerSecond: 5)

        let result = NetworkSpeedMonitor.appending(sample, to: history, maxCount: 60)

        #expect(result.count == 1)
    }
}
