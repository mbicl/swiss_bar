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
        .frame(width: 320)
    }
}

private struct NetworkSpeedGraphSection: View {
    let title: String
    let color: Color
    let currentRate: Double
    let samples: [NetworkSpeedSample]
    let rateKeyPath: KeyPath<NetworkSpeedSample, Double>

    private var upperBound: Double {
        NetworkSpeedChartScale.niceUpperBound(forMaxValue: samples.map { $0[keyPath: rateKeyPath] }.max() ?? 0)
    }

    private var xDomain: ClosedRange<Date> {
        let now = Date()
        return (samples.first?.date ?? now)...(samples.last?.date ?? now)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(title): \(NetworkRateFormatter.string(forBytesPerSecond: currentRate))")
                .font(.caption).bold()
                .foregroundStyle(color)
            // `samples` is already `Identifiable` (stable `UUID`), unlike a freshly-mapped tuple
            // array keyed on `Date` - Charts' diffing couldn't establish stable identity across
            // renders for the latter, which pegged the CPU in an unending re-layout loop.
            //
            // Both axis domains are pinned explicitly (rather than left to Charts' automatic "nice
            // bounds" inference) and implicit animation is disabled: with `samples` mutating every
            // second and the dropdown's first-ever open needing to lay out a full history backlog
            // at once, letting Charts re-solve bounds and animate mark transitions on every tick is
            // a well-documented cause of real-time-chart hangs.
            Chart(samples) { sample in
                AreaMark(x: .value("Time", sample.date), y: .value("Rate", sample[keyPath: rateKeyPath]))
                    .foregroundStyle(color.opacity(0.25))
                    .interpolationMethod(.catmullRom)
                LineMark(x: .value("Time", sample.date), y: .value("Rate", sample[keyPath: rateKeyPath]))
                    .foregroundStyle(color)
                    .interpolationMethod(.catmullRom)
            }
            .chartXAxis(.hidden)
            .chartXScale(domain: xDomain)
            .chartYScale(domain: 0...upperBound)
            .chartYAxis {
                AxisMarks(values: [0, upperBound / 2, upperBound]) { value in
                    AxisGridLine()
                    AxisTick()
                    AxisValueLabel {
                        if let raw = value.as(Double.self) {
                            Text(NetworkRateFormatter.string(forBytesPerSecond: raw, decimals: 0))
                        }
                    }
                }
            }
            .transaction { $0.animation = nil }
            .frame(height: 100)
        }
    }
}
