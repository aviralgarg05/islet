# Changelog

## 0.2.0 (unreleased)

Islet now shows the Live Activities your iPhone sends to the Mac, answers coding agents' permission requests, runs timers, and asks Apple Intelligence, Claude or ChatGPT. It also fits beside the notch without covering menu bar icons.

### iPhone Live Activities
- Rides, deliveries, scores, flights and other Live Activities that macOS 26 and later show in the menu bar now appear in the island, including ones macOS has tucked behind the notch. Islet recognises them by the label macOS gives them, in all 41 of its languages, and never mistakes Now Playing, the Clock timer or the camera controls for one.
- A catalogue of 119 apps that use Live Activities gives each its icon, colour and layout: ride or delivery ETA with a moving marker, order stages, flight board, transit route, live score, timer ring, workout, gauge, live audio, media and agent.
- Clicking a mirrored activity opens Apple's own view of it. Nothing outside Islet can trigger that click.
- Needs Accessibility. Settings can limit mirroring to activities the notch hides, and mirrored text is kept out of the API unless you allow it.

### The menu bar
- The closed island always stays in the top row, beside the notch, like the iPhone's. With Accessibility it measures the free space beside the notch and fits itself to it, down to icon-only wings on a crowded menu bar. If even those don't fit, it keeps the icon-only wings and may cover the edge of the nearest menu bar item.
- It keeps clear of macOS 27's overflow chevron whenever there's room, and items hidden behind the chevron no longer make the menu bar look full.
- Measuring reads one window of the system menu bar instead of asking every app, and only while the island is showing.
- Mission Control now hides the island.

### Coding agents
- **Approvals.** Claude Code, Codex and Cursor can ask in the island: Allow, Always for this session, Deny, or answer in the terminal. Commands are shown in full, risky ones (recursive deletes, force pushes, sudo and more) need a second click, and questions and plans can be answered there too. If Islet isn't running or you don't answer, the agent asks in the terminal as usual.
- **Usage limits.** Claude Code's and Codex's 5-hour and weekly limits appear on Home, with one alert at 90% and at 100%. They come from files the tools write locally; no tokens are read and nothing goes over the network.
- **MCP.** `isletctl mcp` lets agents show progress, notes and timers in the notch as tools.
- Commands shown in the notch hide anything that looks like a key or password.

### Ask
- An Ask box answered on the Mac by Apple Intelligence, by Claude or ChatGPT with your own API key (kept in the Keychain), or by the Claude Code and Codex command-line tools with the login you already have. ⌃⌥A opens it from anywhere.
- Answers stream in and stop when the island closes. Nothing is kept on disk, and an `islet://ask` link only fills in the question.
- Apple Intelligence now picks icons from a fixed set of categories, so its answers are always usable.

### Timers and Siri
- Timers you can start, pause, extend and stop from the island, the API, the URL scheme or `isletctl`, including phrases like "tea 4m" or "in 20 minutes to check the oven". A Pomodoro cycle. Timers survive a relaunch and ring with a sound of your choice.
- Siri reaches Islet through Shortcuts; [docs/SHORTCUTS.md](docs/SHORTCUTS.md) has the recipes.

### Now Playing and controls
- The scrubber seeks. ±15 seconds, shuffle and repeat where the player supports them, the system volume and an output picker.
- Two-finger swipes: down to open, up to close, sideways over music to change track.
- Keep awake for 15 minutes, an hour, two hours or until you turn it off.
- Battery thresholds are adjustable, with an optional "charged to 80%" alert.

### Calendar and reminders
- A Today tab with the rest of the day's events, Join buttons and reminders you can tick off. Repeating meetings now alert every time, and the agenda rolls over at midnight.

### Look
- Liquid Glass for the expanded island on macOS 26 and later, kept below the menu bar row so the notch still reads as hardware.

### Safer and lighter
- A crash when the Now Playing helper stopped, and a core spinning at 100% after it did, are fixed.
- Module switches in Settings take effect at once, and turning clipboard history off clears it.
- `islet://` links can't replace Islet's own activities or open anything but https. Script widgets are off until you turn them on and only run files you own. Meeting links must be on the real host to get a Join button.
- Downloads, the clipboard and plugins stop checking while nothing changes or the screen is locked.
- Local builds use the hardened runtime.

### Measured on an M3 Pro MacBook Pro, macOS 27.0.1

MEASURED_TABLE

### Known issues
- Tested on macOS 27 only; mirroring Live Activities on macOS 26 is untested.
- How much text a Live Activity exposes varies by app.
- Apple Intelligence features need the on-device model to be downloaded.
- Siri can't call Islet directly yet: that needs App Intents metadata only Xcode can build.
- The build is ad-hoc signed, so macOS asks you to confirm the first launch.

## 0.1.0 (30 September 2026)

First version. Islet puts live activities in the space around the MacBook notch and lets other apps and scripts put their own there.

### What's in it

- **Now Playing** for any app that reports to macOS, including browser tabs. It works on macOS 15.4 and later, where Apple locked the private API most notch apps relied on. A small helper runs inside `/usr/bin/perl`, and the Music and Spotify notifications back it up.
- **Live activities** with progress, steps, countdowns and count-ups, states, buttons and links. You can send them with the `isletctl` CLI, a local HTTP API (loopback only, token required), the `islet://` URL scheme, or xbar-style script widgets.
- **Coding agents.** Claude Code hooks and Codex `notify` show what the agent is doing, and flag when it's waiting for you.
- **Calls.** A timer appears when FaceTime, Zoom, Teams, Slack, Discord, WhatsApp or a browser call is using the microphone.
- **System events.** Volume and brightness HUD, charging, low battery, Low Power Mode, audio output changes, Focus (through a Shortcuts automation) and a summary on unlock.
- **Calendar.** Next event, a reminder five minutes before, and a Join button for Zoom, Meet, Teams and Webex links.
- **File shelf** with AirDrop, clipboard history (off by default, skips password managers), download progress and system stats.
- **Notification mirroring.** Experimental and opt-in; needs Accessibility.
- **iPhone Shortcuts bridge.** Off by default. The same API is served on the local network with a token and a rate limit.
- **Appearance.** Compact, Standard and Large sizes; Black, Graphite and Glass themes; five motion styles including Off; up to three activities at once; per-app rules.

### Measured on an M3 Pro MacBook Pro, macOS 27.0.1

From `scripts/perf.sh` (8-second windows) and `Tests/E2E/e2e.py`:

| State | CPU |
|---|---|
| Idle | 0.0% |
| Music playing, closed island | 0.0% |
| Live countdown | 0.62% |
| Island open with Now Playing | 0.25% |

Memory stayed between 73 and 88 MB across those runs. 132 unit and system tests and 51 end-to-end checks pass.

### Known issues

- When something is showing in the closed island, its sides can cover menu bar icons that sit close to the notch. Fixed in the next version.
- Notification mirroring depends on Notification Center's accessibility tree and hasn't been tested against every app.
- Apple Intelligence features only switch on when the on-device model is downloaded. Otherwise Islet falls back to its own icon rules.
- The build is ad-hoc signed, so macOS will ask you to confirm the first launch.
