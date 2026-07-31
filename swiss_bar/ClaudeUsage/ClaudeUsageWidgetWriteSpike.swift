//
//  ClaudeUsageWidgetWriteSpike.swift
//  swiss_bar
//

import Foundation
import os

/// Phase 0 spike only - writes a timestamped string into the shared App Group container so
/// `AppGroupSpikeWidget` (swiss_barWidgets target) can prove it can read data the unsandboxed host
/// app wrote. Deleted once Phase 1 lands the real `ClaudeUsageSharedStore` - see the plan's Phase 0
/// gate in /Users/mbi/.claude/plans/groovy-imagining-leaf.md.
enum ClaudeUsageWidgetWriteSpike {
    private static let logger = Logger(subsystem: "com.MBI.swiss-bar", category: "WidgetWriteSpike")
    private static let appGroupID = "group.com.MBI.swiss-bar"
    private static let fileName = "spike-test-string.txt"

    static func writeNow() {
        guard let dir = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else {
            logger.error("containerURL(forSecurityApplicationGroupIdentifier:) returned nil - App Group entitlement not effective")
            return
        }
        let value = "Hello from swiss_bar host app at \(Date())"
        do {
            try value.write(to: dir.appendingPathComponent(fileName), atomically: true, encoding: .utf8)
            logger.notice("wrote spike test string to \(dir.path, privacy: .public)")
        } catch {
            logger.error("write failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
