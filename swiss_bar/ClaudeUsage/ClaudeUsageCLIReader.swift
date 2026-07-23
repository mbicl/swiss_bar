//
//  ClaudeUsageCLIReader.swift
//  swiss_bar
//

import Foundation
import os

/// Isolates the subprocess glue for invoking the Claude Code CLI's `/usage` command - mirrors how
/// `NetworkInterfaceByteCounterReader` isolates the C API and `ClipboardHotkeyTapManager` isolates
/// `CGEvent`.
enum ClaudeUsageCLIReader {
    private static let timeout: TimeInterval = 10

    /// Runs `<command> -p "/usage" --output-format json` inside a *non-login, non-interactive*
    /// shell, with the common install directories for user-level CLI tools prepended to `PATH`
    /// ourselves - a bare `Process` exec gets the minimal environment GUI apps launch with, which
    /// often can't find tools installed via `~/.local/bin`/homebrew.
    ///
    /// Deliberately **not** `-i` (interactive) or `-l` (login): `-i` was tried first to source
    /// `~/.zshrc` (where PATH additions like `~/.local/bin` commonly live) - it worked, but it
    /// also runs *every* other interactive-shell customization in `~/.zshrc` (oh-my-zsh plugins,
    /// iTerm2 shell integration, prompt themes, etc.), one of which triggered an unrelated macOS
    /// permission prompt (Apple Music/media library access) attributed to this app. `-l` sources
    /// `/etc/zprofile` and `~/.zprofile` - both user-editable, and TCC attributes anything those
    /// (or their children) touch to this app - for no benefit, since PATH is already exported
    /// explicitly below. Explicitly exporting the well-known install directories ourselves solves
    /// the PATH problem without sourcing any of the user's actual shell config.
    ///
    /// **Trade-off:** shell *aliases* (e.g. `alias claude-work='CLAUDE_CONFIG_DIR=~/.claude-work claude'`)
    /// only exist inside files like `.zshrc` that we no longer source, so a bare alias name no longer
    /// resolves. This isn't a loss of capability though - the same effect is expressed as plain,
    /// alias-free shell syntax (`CLAUDE_CONFIG_DIR=~/.claude-work claude`), which works here exactly
    /// as it would in Terminal. `command` is user-configurable (see `AppSettings.claudeUsageCLICommand`)
    /// for exactly this multi-install case, and is interpolated unquoted so env-var-prefixed forms
    /// like that resolve correctly - trusted shell syntax, acceptable since it's a local Settings
    /// value only the user themselves types in.
    ///
    /// Returns the parsed `result` field of the JSON envelope on success - the same prose `/usage`
    /// prints in a terminal, with JSON's `\n`/`\"`/unicode escaping properly decoded (unlike the raw
    /// envelope string, which still has those as literal two-character escapes) - or `nil` on any
    /// failure (binary not found, non-zero exit, timeout, malformed/error envelope). Not unit tested
    /// - real subprocess, same convention as `ClipboardMonitor` never testing live `NSPasteboard`
    /// calls.
    static func readUsage(command: String) async -> String? {
        await withCheckedContinuation { continuation in
            // Single-resumption gate: the reader queue (normal completion) and the timeout queue
            // can both try to resume this continuation. A plain `Bool` mutated from both queues
            // was a real data race that could double-resume (traps at runtime) - this lock makes
            // exactly one of them win.
            let resumeGate = OSAllocatedUnfairLock(initialState: false)
            let resumeOnce: (String?) -> Void = { result in
                let shouldResume = resumeGate.withLock { didResume -> Bool in
                    if didResume { return false }
                    didResume = true
                    return true
                }
                if shouldResume { continuation.resume(returning: result) }
            }

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            let pathExport = #"export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:$PATH""#
            process.arguments = ["-c", "\(pathExport); \(command) -p '/usage' --output-format json"]
            // Neutral, app-owned cwd - the CLI treats cwd as a workspace and must never be left
            // at launchd's `/` (or wherever Xcode happened to launch this app from in a dev run).
            let cwd = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent(Bundle.main.bundleIdentifier ?? "com.MBI.swiss-bar")
            try? FileManager.default.createDirectory(at: cwd, withIntermediateDirectories: true)
            process.currentDirectoryURL = cwd

            let stdout = Pipe()
            let stderr = Pipe()
            process.standardOutput = stdout
            process.standardError = stderr

            do {
                try process.run()
            } catch {
                resumeOnce(nil)
                return
            }

            // Drain stderr concurrently so a chatty CLI (update notices, deprecation warnings)
            // can never fill that pipe's buffer and block the child on write(2).
            DispatchQueue.global(qos: .utility).async {
                _ = stderr.fileHandleForReading.readDataToEndOfFile()
            }

            // Drain stdout *while* the process runs - readDataToEndOfFile returns at EOF (child
            // exit or kill) - then collect the exit status. Reading only after termination (the
            // old approach) deadlocks once output exceeds the pipe's ~64KB buffer.
            DispatchQueue.global(qos: .utility).async {
                let data = stdout.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                guard process.terminationStatus == 0 else {
                    resumeOnce(nil)
                    return
                }
                resumeOnce(extractResultText(from: data))
            }

            // Timeout: SIGTERM, then SIGKILL if the shell ignores it. `resumeOnce` makes this a
            // no-op once the process already finished normally. (Limitation: this signals the
            // `zsh` wrapper, not the `claude` child it spawned - an orphaned child exits on its
            // own once its stdout pipe closes.)
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout) {
                if process.isRunning {
                    process.terminate()
                }
                DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 2) {
                    if process.isRunning {
                        kill(process.processIdentifier, SIGKILL)
                    }
                }
                resumeOnce(nil)
            }
        }
    }

    private struct ResultEnvelope: Decodable {
        let type: String
        let isError: Bool
        let result: String?

        enum CodingKeys: String, CodingKey {
            case type
            case isError = "is_error"
            case result
        }
    }

    private static func extractResultText(from data: Data) -> String? {
        guard let envelope = try? JSONDecoder().decode(ResultEnvelope.self, from: data) else { return nil }
        guard envelope.type == "result", !envelope.isError else { return nil }
        return envelope.result
    }
}
