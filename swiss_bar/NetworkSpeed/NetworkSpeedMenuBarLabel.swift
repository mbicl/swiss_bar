//
//  NetworkSpeedMenuBarLabel.swift
//  swiss_bar
//

import SwiftUI

/// The status-bar label for the network speed `MenuBarExtra` - two lines of small colored text,
/// upload above download, matching the app's other menu bar icon in restraint (no custom chrome).
struct NetworkSpeedMenuBarLabel: View {
    @ObservedObject var monitor: NetworkSpeedMonitor
    @ObservedObject var settings: AppSettings

    var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            Text("↑ " + NetworkRateFormatter.string(forBytesPerSecond: monitor.uploadBytesPerSecond))
                .foregroundStyle(settings.networkSpeedUploadColor)
            Text("↓ " + NetworkRateFormatter.string(forBytesPerSecond: monitor.downloadBytesPerSecond))
                .foregroundStyle(settings.networkSpeedDownloadColor)
        }
        // Monospaced digits keep the status item's width stable between poll ticks - without it,
        // every menu bar icon to its left would shift as digit widths change.
        .font(.system(size: 9, weight: .medium).monospacedDigit())
    }
}
