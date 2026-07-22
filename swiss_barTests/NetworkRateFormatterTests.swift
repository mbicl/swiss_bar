//
//  NetworkRateFormatterTests.swift
//  swiss_barTests
//

import Testing
@testable import swiss_bar

struct NetworkRateFormatterTests {
    @Test func computesRateFromByteDelta() {
        let rate = NetworkRateFormatter.rate(currentBytes: 2000, previousBytes: 1000, elapsed: 2)
        #expect(rate == 500)
    }

    @Test func zeroElapsedClampsToZero() {
        let rate = NetworkRateFormatter.rate(currentBytes: 2000, previousBytes: 1000, elapsed: 0)
        #expect(rate == 0)
    }

    @Test func counterDecreaseClampsToZero() {
        let rate = NetworkRateFormatter.rate(currentBytes: 100, previousBytes: 1000, elapsed: 1)
        #expect(rate == 0)
    }

    @Test func formatsBytesPerSecond() {
        #expect(NetworkRateFormatter.string(forBytesPerSecond: 512) == "512 B/s")
    }

    @Test func formatsKilobytesPerSecond() {
        #expect(NetworkRateFormatter.string(forBytesPerSecond: 6900) == "6.74 KB/s")
    }

    @Test func formatsMegabytesPerSecond() {
        #expect(NetworkRateFormatter.string(forBytesPerSecond: 12_400_000) == "11.83 MB/s")
    }

    @Test func formatsGigabytesPerSecond() {
        #expect(NetworkRateFormatter.string(forBytesPerSecond: 2_147_483_648) == "2.00 GB/s")
    }
}
