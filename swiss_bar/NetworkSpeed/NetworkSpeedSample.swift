//
//  NetworkSpeedSample.swift
//  swiss_bar
//

import Foundation

/// One point in `NetworkSpeedMonitor`'s rolling history buffer, plotted by `NetworkSpeedGraphView`.
struct NetworkSpeedSample: Identifiable {
    let id = UUID()
    let date: Date
    let uploadBytesPerSecond: Double
    let downloadBytesPerSecond: Double
}
