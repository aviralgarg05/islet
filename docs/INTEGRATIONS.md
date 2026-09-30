# Integrations

Islet connects to apps in three ways:

1. **Built in, no setup:** anything playing media (Music, Spotify, browsers, podcasts, video players, via macOS Now Playing), calendar, battery, volume, brightness, audio devices, camera/microphone use, calls, downloads, and notifications from every app (opt-in).
2. **Push from anything:** the `isletctl` CLI, the local HTTP API, the `islet://` URL scheme and the iPhone bridge. Every app or tool that can run a command, open a URL or make a request can drive the island. The full reference is in [API.md](API.md).
3. **Script widgets:** any xbar/SwiftBar plugin, or a script that prints an Islet activity as JSON.

Ready-made files live in [`integrations/`](../integrations/). For recipes covering ~50 specific apps — Mail, Things, OmniFocus, Xcode, VS Code, Cursor, iTerm2, Ghostty, Docker, GitHub, Homebrew, OBS, Time Machine, Tailscale and more — see the [app integration catalogue](research/05-app-integration-catalogue.md).

---

## What works with zero setup

| Source | What you see | Needs |
|---|---|---|
| Any app that reports Now Playing (Music, Spotify, Podcasts, TV, Safari/Chrome/Arc/Firefox tabs, VLC, IINA, Plexamp, Tidal, Cider…) | Artwork + equalizer in the closed island; when open, a scrubber you can drag, ±15 s, shuffle and repeat (when the player reports them), system volume and an output picker | nothing |
| FaceTime, Zoom, Teams, Slack huddles, Discord, WhatsApp, Webex, Skype, Telegram, Signal, Meet in a browser | Green call pill with a live timer; video icon when the camera is on | nothing |
| Calendar (iCloud, Google and Exchange accounts added to macOS) | "Starting soon" 5 minutes before with a **Join** button for Zoom/Meet/Teams/Webex links | Calendar access |
| Battery | Charging splash with the adapter's watts, low and critical warnings at levels you choose, an optional "charged to 80%" alert, Low Power Mode on/off | nothing |
| Volume, brightness, keyboard backlight | HUD in the notch (optionally replacing the system one) | nothing (Accessibility to replace) |
| AirPods / headphones / displays / speakers | "Connected" card when the output device changes | nothing |
| Safari, Chrome, Firefox, Edge, Brave, Arc downloads | Progress (real % for Safari), then "Downloaded" with Open/Show | Downloads folder access |
| Notifications from every app, including iPhone notifications forwarded by macOS | App icon + sender + one line; per-app mute, tint and priority; optional on-device summary | Accessibility (experimental) |
| Screen unlock | "Welcome back" with what arrived while you were away | nothing |

---

## Coding agents

**Claude Code:** add [`integrations/claude-code/settings.json`](../integrations/claude-code/settings.json) to `~/.claude/settings.json` (merge the `hooks` key). The island then shows, per session:
- *Thinking…* with a spinner;
- *Running swift test* or *Editing App.swift* as tools run;
- **Waiting** in high priority with a glow when it needs your permission or input;
- **Done** when the turn ends, before the activity disappears at session end.

**Codex CLI:** add `notify = ["isletctl", "hook", "codex"]` to `~/.codex/config.toml` (see [`integrations/codex/config.toml`](../integrations/codex/config.toml)). You get a "Turn complete" card with the last message.

**Any other agent:** post the generic shape to `/v1/hooks/<name>` or pipe it to `isletctl hook <name>`:

```bash
echo '{"agent":"aider","session":"s1","event":"start","message":"Refactoring auth"}' | isletctl hook aider
# events: start | running | tool | thinking | waiting | input | permission | done | error | end
```

Plans and multi-step jobs can show a segmented stepper:

```bash
isletctl set plan --title "Migrate DB" --steps 5 --step 2 --subtitle "Backfilling users"
```

---

## Usage limits

The Home tab shows the 5-hour and weekly plan limits of Claude Code and Codex, one card per agent: a bar for each window, the share used and the time until it resets. For Claude it also shows the model and how full the context window is while a session is active.

The closed island shows nothing about usage until a window reaches 90%, and again at 100%. Each crossing posts one normal activity ("Claude 5-hour limit at 90%", "Resets 16:40") that leaves on its own. Alerts are armed again when the window resets.

Islet reads only what the two tools already write on this Mac. It doesn't read their login tokens, doesn't call their usage endpoints and sends nothing over the network. Switch either source off in Settings → Integrations → Usage limits (`claudeUsageEnabled` and `codexUsageEnabled` in `config.json`).

### Claude Code

Claude Code passes plan usage to its status line command on stdin (`rate_limits.five_hour` and `rate_limits.seven_day`, for Pro and Max plans, after a session's first reply). `isletctl statusline` records it.

In Settings → Integrations → Usage limits, click **Install status line for Claude Code…**. A sheet shows the `statusLine` command before and after, and nothing is written until you click Install.

- Without a status line, Islet sets one:
  ```json
  "statusLine": { "type": "command", "command": "/Applications/Islet.app/Contents/MacOS/isletctl statusline" }
  ```
  Claude Code then shows a short line such as `Opus 5.5 · 42% context · 5h 62%`.
- With your own status line, Islet wraps it instead of replacing it:
  ```json
  "command": "/Applications/Islet.app/Contents/MacOS/isletctl statusline -- '~/.claude/statusline.sh'"
  ```
  Your command gets the same input, and its output and exit code pass through unchanged.

Installing twice changes nothing. Only the `statusLine` value changes: the rest of `~/.claude/settings.json` keeps its order and spacing, and the previous file is kept as `settings.json.bak`. **Remove…** in the same place puts your own command back. By hand, use `isletctl statusline` as the command, or put `isletctl statusline -- ` in front of yours with your command quoted as one argument.

Claude Code runs the command from the app bundle, so remove the status line (or restore `settings.json.bak`) before you move or delete Islet.

Each run writes `~/Library/Application Support/Islet/usage/claude.json` (mode 0600), and only when a figure changed. Islet watches the file rather than polling it. Other tools can read it too:

```json
{"provider":"claude","model":"Opus 5.5","contextPercent":42.4,"costUSD":1.23,"project":"islet","sessionID":"…","updatedAt":1790786093,
 "windows":[{"id":"five_hour","usedPercent":62,"windowMinutes":300,"resetsAt":1790790413},
            {"id":"seven_day","usedPercent":31,"windowMinutes":10080,"resetsAt":1791200000}]}
```

### Codex

Codex CLI writes its limits into its session logs (`~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl`) after each reply, so there is nothing to install. While the setting is on, Islet watches that folder with FSEvents and, after a change, reads only the last 64 KB of the newest log. If Codex hasn't run on this Mac yet, switch the setting off and on again after its first session.

---

## Terminal

**Wrap a command:** it shows while running, then success or failure, and passes the exit code through:

```bash
isletctl run -- make release
isletctl run --title "Train model" -- python train.py --epochs 20
```

**Every long command automatically:** `source` [`integrations/shell/islet.zsh`](../integrations/shell/islet.zsh) in `~/.zshrc`. Commands that take longer than 10 s (`ISLET_MIN_SECONDS`) appear in the notch and report how they ended. Quick commands never flash.

**Progress from a script:**

```bash
for i in $(seq 1 100); do
  isletctl set upload --title "Uploading photos" --progress $i --subtitle "$i of 100"
  # ... work ...
done
isletctl set upload --state success --subtitle "All done"
```

---

## Launchers and automation apps

| App | Recipe |
|---|---|
| **Shortcuts (Mac)** | "Open URL" `islet://notify?title=…`, or "Run Shell Script" with `isletctl …`. Focus: Automation → *When Work turns on* → Open URL `islet://focus?name=Work&state=on`. |
| **Raycast** | Script commands in [`integrations/raycast/`](../integrations/raycast/) (timer, toggle). Any Raycast deeplink can be an activity `url`. |
| **Alfred** | Workflow → *Open URL* `islet://timer?minutes={query}`, or *Run Script* `isletctl notify "{query}"`. |
| **Hammerspoon** | [`integrations/hammerspoon/islet.lua`](../integrations/hammerspoon/islet.lua) posts to the API, with a Wi-Fi-change example. |
| **BetterTouchTool / Keyboard Maestro** | Action "Open URL" with an `islet://` link, or "Execute shell script" with `isletctl`. Good for trackpad gestures (`islet://toggle`) and hotkeys (`islet://media/next`). |
| **Stream Deck** | "Website" action with an `islet://` URL (background mode), or a "System: Open" action running `isletctl`. |
| **Home Assistant** | [`integrations/home-assistant/islet.yaml`](../integrations/home-assistant/islet.yaml): a `rest_command` to the LAN bridge, plus a doorbell automation. |
| **Makefiles, npm scripts, git hooks** | `isletctl run -- <cmd>` or `isletctl notify`. For example, a `post-merge` hook: `isletctl notify "Pulled $(git rev-parse --short HEAD)" --icon sf:arrow.down.circle`. |
| **CI (GitHub Actions)** | Watch a run from your Mac: `isletctl run --title "CI main" -- gh run watch --exit-status`. |

---

## Gestures

Two-finger swipes on the island work without any permission: Islet reads the scroll events its own windows already receive, and never watches the trackpad elsewhere.

| Swipe | Where | Does |
|---|---|---|
| Down | closed island | open it (handy with *Open on hover* off) |
| Up | open island | close it (it stays closed until the pointer leaves the notch) |
| Left / right | music, closed or on the Home tab | next / previous track, or 10 s forward / back |
| Left / right | a closed activity | show the next / previous activity, from the bubbles beside the notch |

A swipe fires once per flick, after about 24 pt of travel within a quarter of a second, so scrolling past the notch or the momentum of an earlier scroll doesn't trigger it. Directions are the way your fingers move, whatever your *Natural scrolling* setting. Each swipe can be turned off in *Settings → General → Gestures*.

---

## Keep awake

The cup in the open island's header keeps the Mac awake for 15 minutes, 1 or 2 hours, or until you turn it off. A live activity counts down in the notch. It turns itself off on battery below 20%, and won't start then.

| From | Use |
|---|---|
| Terminal | `isletctl awake 2h`, `isletctl awake off`, `isletctl awake status` |
| A long job | `isletctl awake on && make release; isletctl awake off` |
| Shortcuts, Raycast, Alfred, Stream Deck | Open URL `islet://awake?for=1h` or `islet://awake/off` |
| HTTP | `POST /v1/awake {"minutes": 60}`, `DELETE /v1/awake` (see [API.md](API.md#keep-awake)) |

Media keys for launchers work the same way: `islet://media/forward`, `islet://media/rewind`, `islet://media/shuffle`, `islet://media/repeat`, or `isletctl media seek 2m`.

---

## <a name="iphone"></a>iPhone → Mac

Apple doesn't let third-party apps read the iPhone's Live Activities (macOS 26+ shows them itself, as a menu-bar pill). Islet complements that in two ways:

1. **iPhone notifications.** macOS forwards them to the Mac when iPhone Mirroring or notification forwarding is on, and Islet's notification mirroring picks them up like any other banner.
2. **iPhone Shortcuts automations → Islet's local-network bridge.**

To set up the bridge, turn on *Settings → Integrations → iPhone bridge* and copy the token (`isletctl token`). Then on the iPhone: Shortcuts → Automation → **New** → pick a trigger → **Get Contents of URL**:
- URL: `http://<your-mac>.local:47832/v1/notify`
- Method: POST
- Headers: `Authorization: Bearer <token>`
- Request body: JSON (fields below)

| Trigger (iPhone) | Body |
|---|---|
| Alarm goes off | `{"title":"Alarm","subtitle":"Good morning","icon":"sf:alarm.fill"}` |
| Focus turns on / off (URL `/v1/focus`) | `{"name":"Work","on":true}` |
| Arrive at / leave Home | `{"title":"Left home","icon":"sf:figure.walk","ttl":8}` |
| Battery level falls below 20% | `{"title":"iPhone battery low","subtitle":"20%","icon":"sf:iphone.gen3","tint":"red"}` |
| CarPlay connects | `{"title":"Driving","icon":"sf:car.fill"}` |
| NFC tag (e.g. on your desk) | POST `/v1/timer` with `{"seconds":1500,"title":"Focus session"}` |
| Timer started (via a Shortcut) | POST `/v1/timer` with the same duration, so the Mac counts down too |

The bridge requires the token, rejects browser origins and rate-limits each client (30 requests / 10 s).

---

## Script widgets (xbar-compatible)

Drop executables into `~/.config/islet/plugins/` (Settings → Integrations → *Open Plugins Folder*):

- **Existing xbar/SwiftBar plugins** from [xbarapp.com](https://xbarapp.com) work as-is: the header appears in the Widgets tab, items with `href=` or `shell=` are clickable, and `refresh=true` re-runs.
- **JSON widgets** become live activities. [`integrations/plugins/cpu.10s.sh`](../integrations/plugins/cpu.10s.sh) turns CPU load into a low-priority activity every 10 s.
- [`integrations/plugins/github-prs.5m.sh`](../integrations/plugins/github-prs.5m.sh) lists pull requests awaiting your review.

---

## Per-app customisation

*Settings → Apps* (or `appRules` in `config.json`) lets you set, per app:
- a tint and icon for its activities and notifications;
- **hide the island while it's in front** (games, presentations);
- **keep the island in fullscreen** (for example, a call app);
- **mute its notifications**, or raise their priority.

Right-click any activity in the island to dismiss it or mute its source.
