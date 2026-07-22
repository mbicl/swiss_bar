//
//  ClaudeUsageParserTests.swift
//  swiss_barTests
//

import Testing
@testable import swiss_bar

struct ClaudeUsageParserTests {
    /// A real `claude -p "/usage"` capture, used verbatim.
    private static let realOutput = """
    You are currently using your subscription to power your Claude Code usage

    Current session: 56% used · resets Jul 22 at 8:20pm (Asia/Samarkand)
    Current week (all models): 46% used · resets Jul 24 at 8am (Asia/Samarkand)

    What's contributing to your limits usage?
    Approximate, based on local sessions on this machine — does not include other devices or claude.ai. Behaviors are independent characteristics, not a breakdown.

    Last 24h · 693 requests · 3 sessions
      100% of your usage came from subagent-heavy sessions
      84% of your usage was at >150k context
      Top skills: /run 13%, /claude-api 4%
      Top subagents: Plan 2%, Explore 1%

    Last 7d · 1551 requests · 9 sessions
      84% of your usage came from subagent-heavy sessions
      80% of your usage was at >150k context
      34% of your usage came from sessions active for 8+ hours
      Top skills: /run 5%, /claude-api 2%
      Top subagents: Plan 1%, Explore 1%
    """

    @Test func parsesHeadlinePercentagesAndResets() {
        let snapshot = ClaudeUsageParser.parse(Self.realOutput)
        #expect(snapshot?.sessionPercent == 56)
        #expect(snapshot?.sessionResetDescription == "Jul 22 at 8:20pm (Asia/Samarkand)")
        #expect(snapshot?.weeklyLines.count == 1)
        #expect(snapshot?.weeklyLines.first?.label == "all models")
        #expect(snapshot?.weeklyLines.first?.percent == 46)
        #expect(snapshot?.weeklyLines.first?.resetDescription == "Jul 24 at 8am (Asia/Samarkand)")
    }

    @Test func parsesContributingBreakdownForBothPeriods() throws {
        let snapshot = ClaudeUsageParser.parse(Self.realOutput)
        let contributing = try #require(snapshot?.contributing)

        #expect(contributing.last24h.requestCount == 693)
        #expect(contributing.last24h.sessionCount == 3)
        #expect(contributing.last24h.subagentHeavyPercent == 100)
        #expect(contributing.last24h.largeContextPercent == 84)
        #expect(contributing.last24h.longSessionPercent == nil)
        #expect(contributing.last24h.topSkills.map(\.name) == ["/run", "/claude-api"])
        #expect(contributing.last24h.topSkills.map(\.percent) == [13, 4])
        #expect(contributing.last24h.topSubagents.map(\.name) == ["Plan", "Explore"])
        #expect(contributing.last24h.topSubagents.map(\.percent) == [2, 1])

        #expect(contributing.last7d.requestCount == 1551)
        #expect(contributing.last7d.sessionCount == 9)
        #expect(contributing.last7d.subagentHeavyPercent == 84)
        #expect(contributing.last7d.largeContextPercent == 80)
        #expect(contributing.last7d.longSessionPercent == 34)
        #expect(contributing.last7d.topSkills.map(\.name) == ["/run", "/claude-api"])
    }

    @Test func parsesAnAdditionalPerModelWeeklyLineWhenPresent() {
        let withFableLine = """
        Current session: 20% used · resets Jul 22 at 8:20pm (Asia/Samarkand)
        Current week (all models): 30% used · resets Jul 24 at 8am (Asia/Samarkand)
        Current week (Claude Fable 5): 10% used · resets Jul 24 at 8am (Asia/Samarkand)
        """
        let snapshot = ClaudeUsageParser.parse(withFableLine)
        #expect(snapshot?.weeklyLines.count == 2)
        #expect(snapshot?.weeklyLines.last?.label == "Claude Fable 5")
        #expect(snapshot?.weeklyLines.last?.percent == 10)
    }

    @Test func missingHeadlineLinesReturnsNil() {
        #expect(ClaudeUsageParser.parse("some unrelated reworded output") == nil)
    }

    @Test func missingWeeklyLineReturnsNil() {
        #expect(ClaudeUsageParser.parse("Current session: 20% used · resets Jul 22 at 8:20pm (Asia/Samarkand)") == nil)
    }

    @Test func missingContributingSectionLeavesHeadlinePercentagesIntact() {
        let noBreakdown = """
        Current session: 20% used · resets Jul 22 at 8:20pm (Asia/Samarkand)
        Current week (all models): 30% used · resets Jul 24 at 8am (Asia/Samarkand)
        """
        let snapshot = ClaudeUsageParser.parse(noBreakdown)
        #expect(snapshot?.sessionPercent == 20)
        #expect(snapshot?.contributing == nil)
    }
}
