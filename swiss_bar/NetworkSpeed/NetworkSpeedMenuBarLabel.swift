//
//  NetworkSpeedMenuBarLabel.swift
//  swiss_bar
//

import SwiftUI

/// The status-bar label for the network speed `MenuBarExtra` - displays the bitmap that
/// `NetworkSpeedMenuBarImageRenderer` pre-renders on each rate/color update. Deliberately does no
/// rendering work itself (see `NetworkSpeedMenuBarImageRenderer`'s doc comment for why calling
/// `ImageRenderer` directly from this `body` froze the app).
struct NetworkSpeedMenuBarLabel: View {
    @ObservedObject var imageRenderer: NetworkSpeedMenuBarImageRenderer

    var body: some View {
        if let image = imageRenderer.image {
            Image(nsImage: image)
                .renderingMode(.original)
                .accessibilityLabel(imageRenderer.accessibilityDescription)
        }
    }
}
