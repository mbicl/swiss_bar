//
//  ClaudeUsageThresholdTests.swift
//  swiss_barTests
//

import Testing
@testable import swiss_bar

struct ClaudeUsageThresholdTests {
    @Test func boundaryValues() {
        #expect(ClaudeUsageThreshold.severity(forPercent: 0) == .good)
        #expect(ClaudeUsageThreshold.severity(forPercent: 75) == .good)
        #expect(ClaudeUsageThreshold.severity(forPercent: 76) == .warning)
        #expect(ClaudeUsageThreshold.severity(forPercent: 90) == .warning)
        #expect(ClaudeUsageThreshold.severity(forPercent: 91) == .critical)
        #expect(ClaudeUsageThreshold.severity(forPercent: 100) == .critical)
    }
}
