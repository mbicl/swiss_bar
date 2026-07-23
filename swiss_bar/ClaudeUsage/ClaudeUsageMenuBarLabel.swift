//
//  ClaudeUsageMenuBarLabel.swift
//  swiss_bar
//

import SwiftUI

/// The status-bar label for the Claude usage `MenuBarExtra` - displays the bitmap that
/// `ClaudeUsageMenuBarImageRenderer` pre-renders on each poll/setting update. Deliberately does no
/// rendering work itself (see `ClaudeUsageMenuBarImageRenderer`'s doc comment for why calling
/// `ImageRenderer` directly from this `body` would freeze the app).
struct ClaudeUsageMenuBarLabel: View {
    @ObservedObject var imageRenderer: ClaudeUsageMenuBarImageRenderer

    var body: some View {
        if let image = imageRenderer.image {
            Image(nsImage: image)
                .renderingMode(.original)
                .accessibilityLabel(imageRenderer.accessibilityDescription)
        } else {
            // Never collapse to EmptyView: a zero-width status item breaks menu bar hit-testing
            // (observed as a phantom hover highlight) - true from launch until the first
            // successful CLI poll, and permanently whenever the CLI fails.
            Image(systemName: "gauge.with.needle")
                .accessibilityLabel("Claude usage unavailable")
        }
    }
}
