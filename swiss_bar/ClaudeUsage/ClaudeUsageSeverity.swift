//
//  ClaudeUsageSeverity.swift
//  swiss_bar
//

import Foundation

/// Kept separate from `Color` since SwiftUI `Color` equality is unreliable for unit testing
/// (confirmed the hard way while building the network speed indicator) - map to an actual `Color`
/// only at the view layer.
enum ClaudeUsageSeverity: Equatable {
    case good, warning, critical
}

enum ClaudeUsageThreshold {
    nonisolated static func severity(forPercent percent: Int) -> ClaudeUsageSeverity {
        if percent <= 75 {
            return .good
        } else if percent <= 80 {
            return .warning
        } else {
            return .critical
        }
    }
}
