//
//  ClaudeUsageSeverityColor.swift
//  swiss_bar
//

import SwiftUI

/// Split out of `ClaudeUsageMenuBarImageRenderer.swift` (which is AppKit/`NSImage`-heavy and
/// shouldn't be compiled into the sandboxed `swiss_barWidgets` extension) so both the menu bar
/// renderer and the widget can share one severity-to-color mapping instead of drifting apart.
extension ClaudeUsageSeverity {
    var color: Color {
        switch self {
        case .good: return .green
        case .warning: return .yellow
        case .critical: return .red
        }
    }
}
