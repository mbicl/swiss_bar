//
//  ClaudeUsageCLIReader.swift
//  swiss_bar
//

import Foundation

/// Isolates the subprocess glue for invoking the Claude Code CLI's `/usage` command - mirrors how
/// `NetworkInterfaceByteCounterReader` isolates the C API and `ClipboardHotkeyTapManager` isolates
/// `CGEvent`.
enum ClaudeUsageCLIReader {
    private static let timeout: TimeInterval = 10

    /// Runs `<command> -p "/usage" --output-format json` inside a login *and interactive* shell so
    /// `command` resolves exactly as it would when the user types it in their own Terminal - a bare
    /// `Process` exec gets the minimal environment GUI apps launch with, which often can't find CLI
    /// tools installed via nvm/homebrew/`~/.local/bin`. Both `-l` (login) *and* `-i` (interactive)
    /// are required: zsh only sources `~/.zshrc` - where PATH additions like `~/.local/bin` commonly
    /// live - for interactive shells; a login-only, non-interactive `-l -c` skips it, confirmed by
    /// this failing to find a real `~/.local/bin`-installed `claude` until `-i` was added. `command`
    /// is user-configurable (see `AppSettings.claudeUsageCLICommand`) since some users have more than
    /// one Claude Code install (e.g. `claude-work`, `claude-personal`) - it's shell-quoted into the
    /// shell string rather than split into argv so a configured value still resolves the same way a
    /// real shell would.
    ///
    /// Returns the parsed `result` field of the JSON envelope on success - the same prose `/usage`
    /// prints in a terminal, with JSON's `\n`/`\"`/unicode escaping properly decoded (unlike the raw
    /// envelope string, which still has those as literal two-character escapes) - or `nil` on any
    /// failure (binary not found, non-zero exit, timeout, malformed/error envelope). Not unit tested
    /// - real subprocess, same convention as `ClipboardMonitor` never testing live `NSPasteboard`
    /// calls.
    static func readUsage(command: String) async -> String? {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            let escapedCommand = command.replacingOccurrences(of: "'", with: "'\\''")
            process.arguments = ["-l", "-i", "-c", "'\(escapedCommand)' -p '/usage' --output-format json"]

            let stdout = Pipe()
            process.standardOutput = stdout
            process.standardError = Pipe()

            var didResume = false
            let resumeOnce: (String?) -> Void = { result in
                guard !didResume else { return }
                didResume = true
                continuation.resume(returning: result)
            }

            process.terminationHandler = { proc in
                guard proc.terminationStatus == 0 else {
                    resumeOnce(nil)
                    return
                }
                let data = stdout.fileHandleForReading.readDataToEndOfFile()
                resumeOnce(extractResultText(from: data))
            }

            do {
                try process.run()
            } catch {
                resumeOnce(nil)
                return
            }

            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                if process.isRunning {
                    process.terminate()
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
