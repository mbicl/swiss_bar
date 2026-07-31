//
//  ClaudeUsageMonitor.swift
//  swiss_bar
//

import Combine
import Foundation
import WidgetKit

/// Polls `claude -p "/usage"` on a timer and publishes the parsed result - the same `Timer`-driven
/// poll shape as `NetworkSpeedMonitor`, since there's no notification API for this either. One
/// instance per Claude usage account slot (see `ClaudeUsageAccountSettings`); `accountID` is which
/// element of `settings.claudeUsageAccounts` this instance tracks.
@MainActor
final class ClaudeUsageMonitor: ObservableObject {
    private static let pollInterval: TimeInterval = 300
    /// Initial poll delay per slot (`accountID * initialDelayStep`) - without this, N enabled
    /// accounts all fire their first `refreshNow()` at launch simultaneously (N concurrent Claude
    /// Code CLI subprocess starts), and their repeating timers then stay in phase forever.
    private static let initialDelayStep: TimeInterval = 5

    @Published private(set) var snapshot: ClaudeUsageSnapshot?
    @Published private(set) var isRefreshing = false

    private let settings: AppSettings
    private let accountID: Int
    private let widgetStore = ClaudeUsageSharedStore()
    private var timer: Timer?
    private var initialDelayTask: Task<Void, Never>?
    private var cancellables: Set<AnyCancellable> = []
    /// Skips the App Group write + `WidgetCenter` reload when nothing a widget would actually
    /// display has changed - a poll that reparses to an identical snapshot (the common case at a
    /// 5-minute cadence) must not count against WidgetKit's reload budget. Mirrors
    /// `ClaudeUsageMenuBarImageRenderer.lastRenderKey`.
    private var lastWidgetSyncKey: String?

    init(settings: AppSettings, accountID: Int) {
        self.settings = settings
        self.accountID = accountID
    }

    func start() {
        guard timer == nil else { return }
        let newTimer = Timer.scheduledTimer(withTimeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.poll()
            }
        }
        // Lets the OS coalesce this wakeup with others instead of forcing a precise one every
        // 5 minutes - measurable battery cost for an always-running background app otherwise.
        newTimer.tolerance = Self.pollInterval * 0.2
        timer = newTimer

        let delay = Self.initialDelayStep * Double(accountID)
        initialDelayTask = Task { @MainActor [weak self] in
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                guard !Task.isCancelled else { return }
            }
            self?.refreshNow()
        }

        // Re-poll immediately when this account's CLI command changes, rather than waiting up to
        // 5 minutes - debounced since a `TextField` binding publishes on every keystroke, and
        // firing a subprocess per keystroke while typing a command name would be wasteful.
        // `dropFirst()` skips the emit-on-subscribe value so this doesn't double the initial poll
        // above. Reads the *emitted* array element, not `settings.claudeUsageAccounts` - `@Published`
        // fires from `willSet`, so reading the stored property here would see the stale value.
        settings.$claudeUsageAccounts
            .dropFirst()
            .compactMap { [accountID] accounts in accounts.indices.contains(accountID) ? accounts[accountID].cliCommand : nil }
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
        initialDelayTask?.cancel()
        initialDelayTask = nil
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
        // The timer tick, the settings-change debounce, and "Update Now" can all reach here -
        // await suspends, so isRefreshing being read by the button's .disabled alone doesn't
        // prevent a second entry from the other two paths racing a subprocess against this one.
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        guard let raw = await ClaudeUsageCLIReader.readUsage(command: settings.claudeUsageAccounts[accountID].cliCommand) else {
            // Leave the last-known-good snapshot displayed rather than blanking on one transient
            // failure (subprocess timeout, momentary network blip affecting the CLI, etc.).
            return
        }
        guard let parsed = ClaudeUsageParser.parse(raw) else { return }
        snapshot = parsed
        syncWidgetData(snapshot: parsed)
    }

    private func syncWidgetData(snapshot: ClaudeUsageSnapshot) {
        let displayName = settings.claudeUsageAccounts.indices.contains(accountID)
            ? settings.claudeUsageAccounts[accountID].displayName : ""
        let weeklyKey = snapshot.weeklyLines.map { "\($0.label):\($0.percent)" }.joined(separator: ",")
        let key = "\(snapshot.sessionPercent)|\(weeklyKey)|\(displayName)"
        guard key != lastWidgetSyncKey else { return }
        lastWidgetSyncKey = key

        widgetStore.upsertSlot(
            ClaudeUsageWidgetAccountPayload(id: accountID, displayName: displayName, snapshot: snapshot, lastUpdated: Date())
        )
        WidgetCenter.shared.reloadTimelines(ofKind: ClaudeUsageSharedStore.widgetKind(forSlot: accountID))
    }
}
