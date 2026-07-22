//
//  ColorHexTests.swift
//  swiss_barTests
//

import SwiftUI
import Testing
@testable import swiss_bar

struct ColorHexTests {
    @Test func roundTripsThroughHexString() {
        let hex = ColorHex.hexString(from: .red)
        let color = ColorHex.color(fromHex: hex)

        #expect(color != nil)
        #expect(color.map(ColorHex.hexString) == hex)
    }

    @Test func malformedHexReturnsNil() {
        #expect(ColorHex.color(fromHex: "not-a-color") == nil)
    }

    @Test func hexStringHasExpectedFormat() {
        let hex = ColorHex.hexString(from: .yellow)
        #expect(hex.hasPrefix("#"))
        #expect(hex.count == 9)
    }
}
