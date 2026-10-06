# Casement

**A free, open-source Dynamic Island for the Mac notch.** Music, calls, timers, your iPhone's Live Activities, coding agents and anything a script can send show up around the notch, and stay out of the way when nothing's happening.

![The island open on Home: a song playing, with a meeting, a build and a coding agent beside it](docs/images/expanded-home.png)

## What it does

- **Your iPhone's Live Activities** — rides, deliveries, scores, flights — shown in the notch instead of hidden behind it. 137 apps have their own look. → [Live Activities](docs/LIVE-ACTIVITIES.md)
- **Now Playing** from any app, browsers included, with synced lyrics, a scrubber that seeks and an output picker. Small app icons switch between every player macOS lists.
- **Coding agents.** Watch Claude Code, Codex and Cursor work, answer their permission requests from the notch, and keep an eye on usage limits. → [Integrations](docs/INTEGRATIONS.md), [MCP](docs/MCP.md)
- **Meetings, timers and reminders.** A meeting counts down beside the notch and waits with a Join button until you join it.
- **A shelf, clipboard history and download progress.** Drop files on the notch, AirDrop one in a click, find that link you copied an hour ago.
- **Twelve tools, each off until you want it:** to-dos, a note, a converter, emoji, the weather, a camera mirror, a teleprompter, stocks, sales and more. → [Tools](docs/TOOLS.md)
- **Ask** Apple Intelligence, Claude, ChatGPT or your command-line agent a quick question. → [AI](docs/AI.md)
- **Your own activities** from a script, the command line, an HTTP API, the `casement://` scheme or iPhone Shortcuts. → [API](docs/API.md)

<img src="docs/images/closed-states.png" width="520" alt="The closed island: music with everything else in bubbles, a ride mirrored from the iPhone, and a coding agent's plan at step 3 of 5">

## How it stays out of the way

- **It lives in the menu bar row.** With Accessibility it measures the bar and shrinks to the space that's free, so it covers an icon only when the bar is packed right up to the notch.
- **It costs nothing when idle.** Everything is driven by events, and the pointer isn't watched until it reaches the notch.
- **It asks for nothing up front.** Each permission is requested when you turn on the feature that needs it.
- **It keeps things on your Mac.** No account, no telemetry, no licence server. Nothing reaches the network until you switch on something that needs it, and Casement never reads another app's sign-in.
- **It works with VoiceOver and the keyboard**, and honours Reduce Motion and Increase Contrast.
- **It's free and MIT-licensed**, written from scratch.

## Download

Casement is free and needs macOS 14 or later. Mirroring your iPhone's Live Activities needs macOS 26 or later, and has only been tested on macOS 27.

1. Download the zip from the [latest release](https://github.com/aviralgarg05/casement/releases/latest) and double-click it in Finder to unzip it.
2. Move `Casement.app` to Applications. If you open it straight from Downloads, Casement offers to move itself there.
3. To use `casementctl` from Terminal, link it onto your `PATH`:

   ```bash
   ln -sf /Applications/Casement.app/Contents/MacOS/casementctl /opt/homebrew/bin/casementctl
   ```

The Releases page of this repository is the only official download. Each release is built from this repository's source at its tag. From 0.2.0 on, the release notes give the zip's SHA-256 (it's also attached as a `.sha256` file), which you can check with `shasum -a 256` on the downloaded zip.

### Opening it the first time

Releases aren't notarised by Apple yet, so macOS blocks the first launch. To allow it:

1. Open Casement. macOS says it can't verify the app. Close the message, without choosing *Move to Trash*.
2. Open *System Settings → Privacy & Security* and scroll down to *Security*.
3. Next to the message that Casement was blocked, click **Open Anyway**.
4. Click **Open Anyway** again to confirm, and enter your password or use Touch ID.

You only need to do this once. On macOS 15 and later, Control-clicking the app and choosing *Open* no longer gets past this check, so use the steps above.

## Build from source

To build Casement yourself, you need the Xcode Command Line Tools or Xcode with the macOS 26 SDK or later (`xcrun --show-sdk-version` prints 26 or later); full Xcode isn't needed.

```bash
git clone https://github.com/aviralgarg05/casement.git casement && cd casement
make app          # builds build/Casement.app
make run          # builds and opens it
```

To keep it, copy it to Applications and put the command-line tool on your `PATH`:

```bash
make install
ln -sf /Applications/Casement.app/Contents/MacOS/casementctl /opt/homebrew/bin/casementctl
```

A build you make yourself opens without the steps above.

## Try it

Rest the pointer on the notch, or press **⌃⌥I**. **⌃⌥A** opens the Ask box.

```bash
casementctl notify "Hello from the notch" --icon sf:hand.wave.fill
casementctl timer "tea 4m"
casementctl run -- make release                   # shows while it runs, then done or failed
casementctl set deploy --title "Deploying" --progress 40
open "casement://timer?in=25m&title=Focus"
```

To connect a coding agent, press **Connect…** beside it in *Settings → Coding agents*, or merge the hooks from [`integrations/claude-code/settings.json`](integrations/claude-code/settings.json) into `~/.claude/settings.json`, or copy [`integrations/codex`](integrations/codex) or [`integrations/cursor`](integrations/cursor).

## Permissions (all optional)

| Feature | Permission |
|---|---|
| Fitting beside the notch, iPhone Live Activities, mirrored notifications, replacing the system HUD, typing emoji where you're typing | Accessibility |
| Calendar events | Calendars |
| Camera mirror | Camera |
| Reminders | Reminders |
| Download progress | Downloads folder |
| Weather where you are (a typed city needs nothing) | Location |
| Music and Spotify extras when the system bridge can't help | Automation |

Now Playing, volume, brightness, battery, calls, camera and microphone indicators, timers, the shelf, the Ask box and the API need no permission.

Casement doesn't read what you type. With Accessibility it reads where menu bar items are, whether a window is in full screen, the text of Live Activities and banners, and, only with *Replace the system volume and brightness display* on, those keys. With *Type emoji where you're typing* on, it types the emoji you click, and nothing else. From macOS 27, System Settings calls Accessibility *Device Control and Data Access*.

## Configure

Everything is in *Settings* (the capsule in the menu bar) and in `~/.config/casement/config.json`, which reloads when you edit it and can live in your dotfiles. The search field at the top of Settings finds any setting, and everything technical (the local API, the iPhone bridge, hook commands, script widgets) waits under *Advanced*.

## Develop

```bash
make test        # unit and system tests (swift-testing)
make e2e         # end-to-end checks against the real app, with its own config and port
make perf        # CPU for each island state against its budget
make snapshots   # renders every island state to build/snapshots/
make settings-snapshots  # renders every Settings page, light and dark
make demo        # runs with sample content
```

CPU figures for each release are in the [changelog](CHANGELOG.md).

The code is split into `CasementCore` (pure, tested logic), `CasementSystem` (macOS adapters), `Casement` (the app) and `casementctl` (the CLI and MCP server). See [Architecture](docs/ARCHITECTURE.md) and [Research](docs/RESEARCH.md).

## Help and contributing

Questions go to [Discussions](https://github.com/aviralgarg05/casement/discussions), and bugs and ideas to [issues](https://github.com/aviralgarg05/casement/issues) (*Send feedback* in Settings → About opens the form with your versions filled in); [SUPPORT.md](SUPPORT.md) says what to include. Report security problems privately, as [SECURITY.md](SECURITY.md) describes. To send a change, read [CONTRIBUTING.md](CONTRIBUTING.md).

## Licence

MIT. See [LICENSE](LICENSE).

Casement is not affiliated with or endorsed by Apple. Dynamic Island, Live Activities, macOS and Mac are trademarks of Apple Inc.
