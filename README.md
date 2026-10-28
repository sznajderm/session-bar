# SessionBar

A macOS menu bar app that watches your running [Claude Code](https://claude.com/claude-code) sessions. It tells you which session needs you, which one is finished, and what each one is doing now.

## Features

- **Status per session.** Each session gets a colored dot:
  - 🔴 **Needs you:** the session waits for a permission or an answer.
  - 🟠 **Your turn:** the session finished and waits for the next prompt.
  - 🟡 **Background:** the session finished its turn but waits for a background task, for example a CodeRabbit review.
  - 🟢 **Working:** the session is busy.
- **One-sentence summary.** Claude Haiku reads the end of each transcript and says what the session is doing.
- **Session names.** Each session shows one name. The app takes the first name that exists:
  1. The name you gave the session in Claude Code, for example with `/rename`.
  2. The title of its [Warp](https://www.warp.dev) tab, if you renamed the tab.
  3. The AI title that Claude Code writes in the transcript.
  4. The name that Claude Code made, for example `session-bar-96`. The app uses it until the AI title exists.
- **Notifications.** You get a macOS notification when a session needs you or when it is your turn. A yellow session gives no notification until its background task ends.
- **Menu bar count.** The icon shows how many sessions need you or wait for you. It does not count yellow sessions.
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
- A session is yellow when its status is `shell` and its transcript shows that the turn ended. This is the state while a background command runs, for example a wait for a CodeRabbit review.
- For Warp tabs, the app reads `WARP_TERMINAL_SESSION_UUID` from the session process. Then it finds the tab title in the Warp database in read-only mode. The database has no documentation, so a Warp update can stop this lookup. The app then uses the next name in the list.
- When a transcript changes, the app runs `claude -p --model haiku` with no tools to make a one-sentence summary. It does this at most once per minute per session.
- If the `claude` CLI is not available, the app shows the last transcript line instead.

> **Privacy:** The summaries send short transcript excerpts to Claude through your own `claude` CLI login. The app sends no other data.

## Project layout

| Path | Contents |
|---|---|
| `Sources/Logic.swift` | Pure logic: status rules, transcript parsing, session names. |
| `Sources/App.swift` | SwiftUI menu bar app, window, polling and notifications. |
| `Tests/main.swift` | Tests for `Logic.swift`. They run without Xcode. |
| `build.sh` | Builds, tests and installs the app. |
| `Info.plist` | App bundle settings. The app has no Dock icon. |

## Run the tests only

```sh
mkdir -p build
swiftc -swift-version 5 Sources/Logic.swift Tests/main.swift -o build/tests && ./build/tests
```
