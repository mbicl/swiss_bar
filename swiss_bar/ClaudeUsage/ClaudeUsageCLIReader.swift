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

    /// Runs `<command> -p "/usage" --output-format json` inside a *login-only* (non-interactive)
    /// shell, with the common install directories for user-level CLI tools prepended to `PATH`
    /// ourselves - a bare `Process` exec gets the minimal environment GUI apps launch with, which
    /// often can't find tools installed via `~/.local/bin`/homebrew.
    ///
    /// Deliberately **not** `-i` (interactive): that was tried first to source `~/.zshrc` (where
    /// PATH additions like `~/.local/bin` commonly live) - it worked, but it also runs *every* other
    /// interactive-shell customization in `~/.zshrc` (oh-my-zsh plugins, iTerm2 shell integration,
    /// prompt themes, etc.), one of which triggered an unrelated macOS permission prompt (Apple
    /// Music/media library access) attributed to this app - a real, unacceptable side effect for a
    /// background usage poll. Explicitly exporting the well-known install directories ourselves
    /// solves the same PATH problem without sourcing any of the user's actual shell config.
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
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            let pathExport = #"export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:$PATH""#
            process.arguments = ["-l", "-c", "\(pathExport); \(command) -p '/usage' --output-format json"]

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
