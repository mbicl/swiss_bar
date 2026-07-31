# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project overview

`swiss_bar` is a macOS menubar app (SDK: macosx, deployment target 26.5, Swift 5.0) bundling several independent utilities:

1. **Window switcher** — replaces Cmd+Tab with a switcher that cycles through windows instead of apps.
2. **Clipboard history** — records copied text/images (FlyCut-style), pastes via Cmd+Shift+V.
3. **Keyboard cleaning mode** — temporarily disables all keyboard input (for physically cleaning the keyboard).
4. **Network speed indicator** — shows live download/upload speed in the menubar.
5. **Claude usage indicator** — shows Claude usage (session, weekly, Fable 5 if present), similar to the Claude web app, both as a menu bar item and as a macOS desktop/Notification Center widget.

All five features above are implemented; they were built one at a time, each in its own isolated subdirectory (see Structure below).

The app is `LSUIElement` (agent app: no Dock icon, no app menu bar) and runs unsandboxed (`ENABLE_APP_SANDBOX` removed from the `swiss_bar` target) — several features (window switcher, keyboard cleaning mode) need a global `CGEventTap` and cross-process Accessibility (`AXUIElement`) control that don't work under App Sandbox. The `swiss_barWidgets` extension target is the one exception: WidgetKit extensions are always sandboxed (no opt-out), so it and the main app share Claude usage data via an App Group (`group.com.MBI.swiss-bar`) rather than in-process — see `swiss_bar/ClaudeUsage/ClaudeUsageSharedStore.swift`. `swiss_bar/swiss_bar.entitlements` grants the main app only `application-groups`, never `app-sandbox` — adding sandbox there would break the window switcher and keyboard cleaning. Distribution is via GitHub Releases, signed with a self-signed certificate (not an Apple Developer ID) — not the Mac App Store, not notarized. See `INSTALL.md` for why, and the Releasing section below for how.

## Structure

- `swiss_bar/swiss_barApp.swift` — `@main` App entry point; `MenuBarExtra` scene hosting `MenuBarMenuView`, wired to `AppDelegate` via `@NSApplicationDelegateAdaptor`.
- `swiss_bar/AppDelegate.swift` — owns feature-level singletons (event tap, overlay, permissions) and their lifecycle; wire new features in here.
- `swiss_bar/AccessibilityPermissionManager.swift` — tracks Accessibility/Input Monitoring TCC grant state, used by any feature needing global input/window access.
- `swiss_bar/MenuBarMenuView.swift` — the menu bar dropdown content. Rendered as a custom floating panel via `.menuBarExtraStyle(.window)` (set in `swiss_barApp.swift`), not a native `NSMenu` — needed so on/off state (e.g. keyboard cleaning) can show a real system switch instead of a checkmark. Rows close the panel explicitly (`NSApp.keyWindow?.close()`) before acting, to replicate native menu dismiss-on-click behavior.
- `swiss_bar/WindowSwitcher/` — window switcher feature: `EventTapManager` (global Cmd+Tab interception), `WindowEnumerator`/`CandidateWindow` (AX-based window listing), `WindowActivator` (raise/focus), `SwitcherViewModel`/`OverlayController`/`SwitcherOverlayView` (the HUD). Each feature gets its own subdirectory like this one, isolated from the others.
- `swiss_bar/KeyboardCleaning/` — keyboard cleaning mode feature: `KeyboardCleaningManager`, a global `CGEventTap` that swallows keyboard input while active, toggled from a switch in the menu bar dropdown (no Settings tab).
- `swiss_bar/ClipboardHistory/` — clipboard history feature: `ClipboardMonitor` (polls `NSPasteboard` for new copies), `ClipboardHistoryStore`/`ClipboardHistoryPersistence` (in-memory + disk-backed history, capped by a configurable capacity), `ClipboardHotkeyTapManager` (global Cmd+Shift+V interception, independent of the window switcher's `EventTapManager`), `ClipboardPickerViewModel`/`ClipboardPickerOverlayController`/`ClipboardPickerOverlayView` (the mouse-and-keyboard-navigable HUD), `ClipboardPasteExecutor` (writes the selected item back to the pasteboard and synthesizes a Cmd+V keystroke into the frontmost app).
- `swiss_bar/ClaudeUsage/` — also has files with **dual membership** in the `swiss_barWidgets` target (`ClaudeUsageSnapshot.swift`, `ClaudeUsageSeverity.swift`, `ClaudeUsageSeverityColor.swift`, `ClaudeUsageSharedStore.swift`) — anything the widget needs to decode/render shared data without pulling in the AppKit-heavy renderer files. Add/remove a file's widget-target membership via Xcode's File Inspector checkbox, not by hand-editing `project.pbxproj`.
- `swiss_bar/Assets.xcassets` — app icon and accent color assets.
- `swiss_barWidgets/` — the Claude usage WidgetKit extension target (separate `.appex`, embedded in `swiss_bar.app/Contents/PlugIns/`). `swiss_barWidgetsBundle.swift` hosts three static widgets, `ClaudeUsageWidgetSlot0/1/2` (`ClaudeUsageWidget.swift`), one per `ClaudeUsageAccountSettings` slot — **not** a single `AppIntentConfiguration`-based widget with an in-gallery account picker. That was the original design, but importing `AppIntents` anywhere in this target makes WidgetKit's `Widget`/`WidgetConfiguration` symbols unresolvable elsewhere in the same target on this Xcode/SDK combination (a genuine toolchain bug, reproducible with a two-file repro outside Xcode entirely — don't reintroduce `AppIntents` here without confirming it's been fixed upstream). `ClaudeUsageTimelineProvider.swift` is a plain `TimelineProvider` (policy `.never`) that only renders what `ClaudeUsageMonitor` last wrote to the shared container — the extension never spawns the Claude CLI itself. `ClaudeUsageWidget.swift` needs both `import WidgetKit` and `import SwiftUI` — WidgetKit alone left `some WidgetConfiguration` unresolvable in that file (unrelated to the AppIntents issue above).
- `swiss_barTests/` — unit tests using the Swift Testing framework (`import Testing`, `@Test` macro), not XCTest.
- `swiss_barUITests/` — UI tests using XCTest/XCUIApplication (launch and performance tests).

Note: the project uses Xcode's file-system-synchronized groups (`PBXFileSystemSynchronizedRootGroup`) — new files placed under `swiss_bar/`, `swiss_barTests/`, `swiss_barUITests/`, or `swiss_barWidgets/` are picked up automatically; there's no need to manually register them in `project.pbxproj`. This does **not** extend to creating a whole new target, though — `swiss_barWidgets` itself was added via Xcode's target machinery (in this repo's case, scripted through the `xcodeproj` Ruby gem rather than the Xcode UI, but the resulting `project.pbxproj` structure — target, build phases, synchronized root group, embed-extension phase on `swiss_bar` — is the same either way).

## Build, run, and test

This is an Xcode project (`swiss_bar.xcodeproj`) with a single scheme, `swiss_bar`.

Build and run from Xcode, or via `xcodebuild` from the command line:

```sh
# Build
xcodebuild -project swiss_bar.xcodeproj -scheme swiss_bar -configuration Debug build

# Run all tests (unit + UI)
xcodebuild test -project swiss_bar.xcodeproj -scheme swiss_bar -destination 'platform=macOS'

# Run a single unit test (Swift Testing)
xcodebuild test -project swiss_bar.xcodeproj -scheme swiss_bar -destination 'platform=macOS' \
  -only-testing:swiss_barTests/swiss_barTests/example

# Run a single UI test (XCTest)
xcodebuild test -project swiss_bar.xcodeproj -scheme swiss_bar -destination 'platform=macOS' \
  -only-testing:swiss_barUITests/swiss_barUITests/testExample
```

Note: `swiss_barTests` uses the Swift Testing framework (`@Test`), while `swiss_barUITests` uses XCTest (`XCTestCase`) — the two are not interchangeable and use different assertion styles (`#expect` vs. `XCTAssert*`).

## Releasing

Pushing a tag matching `v*` triggers `.github/workflows/release.yml`, which runs the unit tests,
builds Release-configuration, signs with the self-signed certificate, packages a DMG + zip, and
publishes a GitHub Release — no need to open that workflow file to remember how it works.
`scripts/build-release.sh` signs `swiss_barWidgets.appex` (with its own entitlements) before
signing the outer `swiss_bar.app` (with its own, different entitlements) — nested code must be
signed first — then verifies with `codesign --verify --deep --strict` so a broken nested signature
doesn't slip through. To cut a release:

1. Make sure `main` is clean and pushed: `git status`, `git push origin main`.
2. Pick the next version: `git tag -l --sort=-v:refname | head -1` for the latest, then bump —
   minor for new features, patch for fixes/small changes (no major yet).
3. Tag and push (this alone starts the workflow — nothing else to trigger manually):
   ```sh
   git tag -a vX.Y.Z -m "swiss_bar X.Y.Z: <short summary>"
   git push origin vX.Y.Z
   ```
4. Watch it: `gh run list --workflow=release.yml --limit 1` for the run ID, then
   `gh run watch <run-id> --exit-status`.
5. **The workflow's own release notes are static installation instructions only — they say
   nothing about what changed in that version.** Always follow up by editing the release to
   prepend a "What's new" section (features and fixes since the previous tag — summarize
   `git log <previous-tag>..vX.Y.Z --oneline`, don't just paste raw commit subjects) above that
   static text, so every published release documents what's actually in it:
   ```sh
   gh release view vX.Y.Z --json body -q .body > /tmp/notes.md   # existing static notes
   # prepend a "## What's new" bullet list to /tmp/notes.md, then:
   gh release edit vX.Y.Z --notes-file /tmp/notes.md
   ```
6. Verify: `gh release view vX.Y.Z`.
