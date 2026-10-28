# SessionBar

A macOS menu bar app that watches your running [Claude Code](https://claude.com/claude-code) sessions. It tells you which session needs you, which one is finished, and what each one is doing now.

## Features

- **Status per session.** Each session gets a colored dot:
  - 🔴 **Needs you:** the session waits for a permission or an answer.
  - 🟠 **Your turn:** the session finished and waits for the next prompt.
  - 🟡 **Background:** the session finished its turn but waits for a background task, for example a CodeRabbit review.
  - 🟢 **Working:** the session is busy.
- **One-sentence summary.** Claude Haiku reads the end of each transcript and says what the session is doing.
- **Ticket detection.** The app finds the Jira-style ticket key (for example `EMR-123`) that the session works on.
- **Notifications.** You get a macOS notification when a session needs you or when it is your turn.
- **Menu bar count.** The icon shows how many sessions need you or wait for you.
- **Floating window.** A small window lists all sessions. It can stay on top of other windows.

## Requirements

- macOS 15 or later.
- Xcode Command Line Tools (`xcode-select --install`). You do not need the full Xcode.
- The Claude Code CLI (`claude`) in `/opt/homebrew/bin`, `~/.local/bin` or `/usr/local/bin`. The app uses it for the summaries.

## Build and install

```sh
./build.sh
```

The script does these steps:

1. It compiles and runs the tests in `Tests/main.swift`.
2. It builds `SessionBar.app` and signs it ad hoc.
3. It stops any running copy and installs the app in `~/Applications`.

Then open `~/Applications/SessionBar.app`. To start it at login, add it in **System Settings → General → Login Items**.

## How it works

- Every 5 seconds, the app reads the session files in `~/.claude/sessions/`. It keeps only interactive sessions whose process is still alive.
- For each session, it reads the end of the transcript in `~/.claude/projects/<project>/<session-id>.jsonl`.
- When a transcript changes, the app runs `claude -p --model haiku` with no tools to make a one-sentence summary. It does this at most once per minute per session.
- If the `claude` CLI is not available, the app shows the last transcript line instead.

> **Privacy:** The summaries send short transcript excerpts to Claude through your own `claude` CLI login. The app sends no other data.

## Project layout

| Path | Contents |
|---|---|
| `Sources/Logic.swift` | Pure logic: status rules, transcript parsing, ticket detection. |
| `Sources/App.swift` | SwiftUI menu bar app, window, polling and notifications. |
| `Tests/main.swift` | Tests for `Logic.swift`. They run without Xcode. |
| `build.sh` | Builds, tests and installs the app. |
| `Info.plist` | App bundle settings. The app has no Dock icon. |

## Run the tests only

```sh
mkdir -p build
swiftc -swift-version 5 Sources/Logic.swift Tests/main.swift -o build/tests && ./build/tests
```
