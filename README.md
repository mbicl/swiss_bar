# swiss_bar

A macOS menubar multitool — window switcher (Cmd+Tab per window), clipboard history, keyboard
cleaning mode, and live network/Claude usage indicators, all in one lightweight menubar app.

## Features

- [x] **Window switcher** — replaces Cmd+Tab with a switcher that cycles through individual
  windows instead of apps, with MRU-based ordering and arrow-key navigation.
- [x] **Clipboard history** — records copied text/images (FlyCut-style); paste from history via
  Cmd+Shift+V.
- [x] **Keyboard cleaning mode** — temporarily disables all keyboard input so the keyboard can be
  physically cleaned, via a live switch in the menu-bar dropdown.
- [x] **Network speed indicator** — shows live download/upload speed in the menubar, with a
  dropdown graph of recent history.
- [x] **Claude usage indicator** — shows Claude Code session/weekly usage in the menubar, colored
  by how close you are to the limit, similar to the Claude web app.

All five are implemented and shipping in [Releases](https://github.com/mbicl/swiss_bar/releases).

## Install

Download the latest `.dmg` from [Releases](https://github.com/mbicl/swiss_bar/releases).
swiss_bar isn't notarized (see [INSTALL.md](INSTALL.md) for why), so macOS will warn about an
unidentified developer on first launch — INSTALL.md covers both ways to get past that, plus the
Accessibility/Input Monitoring permissions the app needs.

## Building from source

Requires Xcode 26+ and macOS 26.5+.

```sh
git clone https://github.com/mbicl/swiss_bar.git
cd swiss_bar
open swiss_bar.xcodeproj
```

Build & Run (⌘R) from Xcode, or from the command line:

```sh
xcodebuild -project swiss_bar.xcodeproj -scheme swiss_bar -configuration Debug build
xcodebuild test -project swiss_bar.xcodeproj -scheme swiss_bar -destination 'platform=macOS'
```

swiss_bar is `LSUIElement` (no Dock icon, no app menu bar) and runs unsandboxed — several
features need a global `CGEventTap` and cross-process Accessibility control that don't work
under App Sandbox.

## Contributing

This is a personal project built one feature at a time; see [CLAUDE.md](CLAUDE.md) for
architecture notes.
