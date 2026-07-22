//
//  NetworkSpeedGraphView.swift
//  swiss_bar
//

import Charts
import SwiftUI

/// The network speed `MenuBarExtra`'s dropdown content - a rolling area graph per direction, each
/// colored to match its corresponding menu bar text.
struct NetworkSpeedGraphView: View {
    @ObservedObject var monitor: NetworkSpeedMonitor
    @ObservedObject var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            NetworkSpeedGraphSection(
                title: "Upload",
                color: settings.networkSpeedUploadColor,
                currentRate: monitor.uploadBytesPerSecond,
                samples: monitor.history,
                rateKeyPath: \.uploadBytesPerSecond
            )
            Divider()
            NetworkSpeedGraphSection(
                title: "Download",
                color: settings.networkSpeedDownloadColor,
                currentRate: monitor.downloadBytesPerSecond,
                samples: monitor.history,
                rateKeyPath: \.downloadBytesPerSecond
            )
        }
        .padding()
        .frame(width: 260)
    }
}

private struct NetworkSpeedGraphSection: View {
    let title: String
    let color: Color
    let currentRate: Double
    let samples: [NetworkSpeedSample]
    let rateKeyPath: KeyPath<NetworkSpeedSample, Double>

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(title): \(NetworkRateFormatter.string(forBytesPerSecond: currentRate))")
                .font(.caption).bold()
                .foregroundStyle(color)
            // `samples` is already `Identifiable` (stable `UUID`), unlike a freshly-mapped tuple
            // array keyed on `Date` - Charts' diffing couldn't establish stable identity across
            // renders for the latter, which pegged the CPU in an unending re-layout loop.
            Chart(samples) { sample in
                AreaMark(x: .value("Time", sample.date), y: .value("Rate", sample[keyPath: rateKeyPath]))
                    .foregroundStyle(color.opacity(0.25))
                LineMark(x: .value("Time", sample.date), y: .value("Rate", sample[keyPath: rateKeyPath]))
                    .foregroundStyle(color)
            }
            .chartXAxis(.hidden)
            .frame(height: 60)
        }
    }
}
