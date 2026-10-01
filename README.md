# Islet

**A free, open-source Dynamic Island for the Mac notch.** Music, calls, timers, your iPhone's Live Activities, coding agents and anything a script can send show up around the notch, and stay out of the way when nothing's happening.

<img src="docs/images/closed-states.png" width="500" alt="The closed island: music with other activities in bubbles, a ride mirrored from the iPhone, a live score, an agent waiting, a timer, an agent's plan and a usage alert">

![The expanded island on Home](docs/images/expanded-home.png)

## What it does

- **Your iPhone's Live Activities.** Rides, deliveries, scores and flights that macOS shows in the menu bar appear in the island with the app's icon and colour, including the ones the notch hides. 119 apps have their own look. See [Live Activities](docs/LIVE-ACTIVITIES.md).
- **Now Playing** from any app, browsers included, with a scrubber that seeks, ±15 s, shuffle and repeat, volume and an output picker. Each new song shows for a moment below the notch.
- **Coding agents.** See what Claude Code, Codex or Cursor is doing, answer their permission requests and questions from the notch, and watch your plan's usage limits. Agents can also drive the notch over MCP. See [Integrations](docs/INTEGRATIONS.md) and [MCP](docs/MCP.md).
- **Ask** Apple Intelligence, Claude, ChatGPT or your command-line agent a quick question. See [AI](docs/AI.md).
- **Timers and Pomodoro**, started from the island, a phrase like "tea 4m", Siri via Shortcuts ([recipes](docs/SHORTCUTS.md)) or a script.
- **Calendar and Reminders**: the next meeting with a Join button, the rest of today, and reminders you can tick off.
- **Calls, HUDs and system events**: call timers, volume and brightness, charging and battery, Focus, keep awake, a summary when you unlock.
- **A file shelf, clipboard history, download progress and script widgets** (xbar and SwiftBar plugins run unchanged).
- **Your own activities** from the command line, a local HTTP API, the `islet://` URL scheme or iPhone Shortcuts. See the [API](docs/API.md).

## How it stays out of the way

- **It sits beside the notch, like the iPhone's.** It always stays in the menu bar row. With Accessibility it measures the menu bar and shrinks to the free space, down to just an icon each side, so it covers a menu bar icon only when the bar is packed right up to the notch.
- **It costs nothing when idle.** Everything is driven by events, looping animations run in Core Animation, and the pointer isn't watched until it reaches the notch. `make perf` checks each state against a CPU budget; the latest figures are in the [changelog](CHANGELOG.md).
- **It asks for nothing up front.** Each permission is requested when you turn on the feature that needs it.
- **It keeps things on your Mac.** No account, no telemetry, no licence server. Questions go to an AI provider only when you ask one, with your own key.
- **It's free and MIT-licensed**, written from scratch.

## Install

Islet needs macOS 14 or later (Live Activity mirroring needs macOS 26, and is built for 27). Build it with the Xcode Command Line Tools; full Xcode isn't needed.

```bash
git clone <this repo> islet && cd islet
make app          # builds build/Islet.app
make run          # builds and opens it
```

To keep it, copy it to Applications and put the command-line tool on your `PATH`:

```bash
make install
ln -sf /Applications/Islet.app/Contents/MacOS/isletctl /opt/homebrew/bin/isletctl
```

The zipped app on the Releases page is ad-hoc signed, so the first time you open it macOS will ask you to confirm it in *System Settings → Privacy & Security*.

## Try it

Rest the pointer on the notch, or press **⌃⌥I**. **⌃⌥A** opens the Ask box.

```bash
isletctl notify "Hello from the notch" --icon sf:hand.wave.fill
isletctl timer "tea 4m"
isletctl run -- make release                   # shows while it runs, then done or failed
isletctl set deploy --title "Deploying" --progress 40
open "islet://timer?in=25m&title=Focus"
```

To connect a coding agent, use *Settings → Integrations*, or copy [`integrations/claude-code/settings.json`](integrations/claude-code/settings.json), [`integrations/codex`](integrations/codex) or [`integrations/cursor`](integrations/cursor).

## Permissions (all optional)

| Feature | Permission |
|---|---|
| Fitting beside the notch, iPhone Live Activities, mirrored notifications, replacing the system HUD | Accessibility |
| Calendar events | Calendars |
| Reminders | Reminders |
| Download progress | Downloads folder |
| Music and Spotify extras when the system bridge can't help | Automation |

Now Playing, volume, brightness, battery, calls, camera and microphone indicators, timers, the shelf, the Ask box and the API need no permission.

## Configure

Everything is in *Settings* (the capsule in the menu bar) and in `~/.config/islet/config.json`, which reloads when you edit it and can live in your dotfiles.

## Develop

```bash
make test        # unit and system tests (swift-testing)
make e2e         # end-to-end checks against the real app, with its own config and port
make perf        # CPU for each island state against its budget
make snapshots   # renders every island state to build/snapshots/
make demo        # runs with sample content
```

The code is split into `IsletCore` (pure, tested logic), `IsletSystem` (macOS adapters), `Islet` (the app) and `isletctl` (the CLI and MCP server). See [Architecture](docs/ARCHITECTURE.md) and [Research](docs/RESEARCH.md).

## Licence

MIT. See [LICENSE](LICENSE).
