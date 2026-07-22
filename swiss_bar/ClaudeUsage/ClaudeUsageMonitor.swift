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
    @Published private(set) var isRefreshing = false

    private let settings: AppSettings
    private var timer: Timer?
    private var cancellables: Set<AnyCancellable> = []

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
        refreshNow()

        // Re-poll immediately when the CLI command changes, rather than waiting up to 5 minutes -
        // debounced since a `TextField` binding publishes on every keystroke, and firing a
        // subprocess per keystroke while typing a command name would be wasteful. `dropFirst()`
        // skips the emit-on-subscribe value so this doesn't double the `refreshNow()` call above.
        settings.$claudeUsageCLICommand
            .dropFirst()
            .removeDuplicates()
            .debounce(for: .seconds(1), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.refreshNow()
            }
            .store(in: &cancellables)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        cancellables.removeAll()
    }

    /// Triggers an immediate poll outside the regular timer cadence - used both for the CLI
    /// command changing and the dropdown's manual "Update Now" button.
    func refreshNow() {
        Task { @MainActor [weak self] in
            await self?.poll()
        }
    }

    private func poll() async {
        isRefreshing = true
        defer { isRefreshing = false }

        guard let raw = await ClaudeUsageCLIReader.readUsage(command: settings.claudeUsageCLICommand) else {
            // Leave the last-known-good snapshot displayed rather than blanking on one transient
            // failure (subprocess timeout, momentary network blip affecting the CLI, etc.).
            return
        }
        guard let parsed = ClaudeUsageParser.parse(raw) else { return }
        snapshot = parsed
    }
}
