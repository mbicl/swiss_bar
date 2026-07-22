//
//  ClaudeUsageMonitor.swift
//  swiss_bar
//

import Combine
import Foundation

/// Polls `claude -p "/usage"` on a timer and publishes the parsed result - the same `Timer`-driven
/// poll shape as `NetworkSpeedMonitor`, since there's no notification API for this either.
@MainActor
final class ClaudeUsageMonitor: ObservableObject {
    private static let pollInterval: TimeInterval = 300

    @Published private(set) var snapshot: ClaudeUsageSnapshot?

    private let settings: AppSettings
    private var timer: Timer?

    init(settings: AppSettings) {
        self.settings = settings
    }

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.poll()
            }
        }
        Task { @MainActor [weak self] in
            await self?.poll()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func poll() async {
        guard let raw = await ClaudeUsageCLIReader.readUsage(command: settings.claudeUsageCLICommand) else {
            // Leave the last-known-good snapshot displayed rather than blanking on one transient
            // failure (subprocess timeout, momentary network blip affecting the CLI, etc.).
            return
        }
        guard let parsed = ClaudeUsageParser.parse(raw) else { return }
        snapshot = parsed
    }
}
