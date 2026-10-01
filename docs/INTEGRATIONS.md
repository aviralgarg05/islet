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
| Any app that reports Now Playing (Music, Spotify, Podcasts, TV, Safari/Chrome/Arc/Firefox tabs, VLC, IINA, Plexamp, Tidal, Cider…) | Artwork + equalizer in the closed island, and each new song for a moment below the notch; when open, a scrubber you can drag, ±15 s, shuffle and repeat (when the player reports them), system volume and an output picker | nothing |
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

The quickest way: open *Settings → Coding agents* and press **Connect…** beside Claude Code, Codex or Cursor. A sheet lists every change before anything is written, your own hooks and settings stay as they are, and each file is copied to a `.bak` file first. The row then says **Connected**; if you later change how long Islet waits for an answer, it says **Needs an update** and **Update…** brings the hooks in line. The commands themselves are in *Settings → Advanced → Coding agents*, for dotfiles. The sections below do the same by hand.

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

### Approvals from the notch

Claude Code, Codex and Cursor can ask you in the island instead of the terminal: permission to run a command or change a file, Claude's multiple-choice questions, and plans from plan mode. The island opens a card with the agent and project, the full command or file path (the box scrolls; nothing is cut short), and these buttons:

| Button | What the agent gets |
|---|---|
| **Allow** | Allowed, this once |
| **Always** | Allowed, plus the rule Claude suggests (for example `Bash(npm test:*)`) for the rest of this session only. Claude Code only, and only when Claude suggests a rule |
| **Deny** | Denied, with a short message so the agent knows you said no |
| **Terminal** | No answer: the agent asks in the terminal as usual, and Islet brings that terminal forward |

Questions show their options as buttons. When a question takes several answers, tick them and press **Send**. Plans show the Markdown with **Approve** and **Keep planning**. With more requests waiting, the card shows **+N** and they come one at a time. The chevron hides the card; it comes back when you open the island. While the island is hidden (a fullscreen app, or a rule for the app in front), requests go straight back to the terminal instead of waiting where you can't see them.

**Risky commands.** Commands are checked against a list of patterns: `rm -rf`, `sudo`, `git push --force`, `git reset --hard`, `git clean -f`, `curl … | sh`, `chmod 777`, `dd` to a disk, `mkfs`, `diskutil erase…`, `npm publish`, `DROP TABLE`, writes, copies and moves outside the project folder, files that often hold secrets, and a few more. A match is shown in orange above the command, **Allow** then needs a second click (or a press and hold), and **Always** is hidden. The rules only add friction; they never block anything.

**Claude Code:** **Connect…** beside Claude Code in Settings → Coding agents lists the hooks it will add to `~/.claude/settings.json` and asks before writing. Your own hooks and settings stay as they are, and the previous file is kept as `settings.json.bak`. Connecting again changes nothing. To do it by hand, merge [`integrations/claude-code/settings.json`](../integrations/claude-code/settings.json). Next to the status hooks it adds:

```json
"PermissionRequest": [{"hooks": [{"type": "command", "command": "isletctl hook claude --wait 300", "timeout": 330}]}],
"PreToolUse": [{"matcher": "AskUserQuestion|ExitPlanMode",
                "hooks": [{"type": "command", "command": "isletctl hook claude --wait 300", "timeout": 330}]}]
```

The hook's `timeout` is 30 seconds longer than `--wait`, so Islet always answers first. Claude Code's deny and ask rules still apply: an **Allow** from the notch can't override them.

**Codex CLI:** **Connect…** beside Codex adds Islet's hooks to `~/.codex/hooks.json` and turns on `hooks = true` under `[features]` in `~/.codex/config.toml`, changing only that line. By hand: add the key, and copy [`integrations/codex/hooks.json`](../integrations/codex/hooks.json) to `~/.codex/hooks.json`. Either way, run `/hooks` in Codex once to trust the new hooks; Codex won't run them until you do.

**Cursor:** **Connect…** beside Cursor adds Islet's hooks to `~/.cursor/hooks.json`. By hand, copy [`integrations/cursor/hooks.json`](../integrations/cursor/hooks.json) there (or to a project's `.cursor/hooks.json`). Shell commands and MCP tool calls then ask in the notch, and **Terminal** hands the choice back to Cursor's own prompt.

**How it works.** `isletctl hook <agent> --wait N` posts the hook's payload to `/v1/hooks/<agent>?wait=N` and waits (see [API.md](API.md#approvals-long-poll)). The card appears a quarter of a second later, so the terminal can print its own prompt first. Islet holds the request until you answer, for at most N seconds or the wait set in Settings, whichever is shorter, and `isletctl` prints the answer in the form the agent expects. Everything fails open: if Islet isn't running, approvals are off, the wait runs out or you choose **Terminal**, `isletctl` prints nothing and exits 0, and the agent asks in the terminal as if no hook had run. Only events that ask for a decision wait; every other event is sent and forgotten within 1.5 seconds.

Cards clear themselves when a later event shows the question is settled: the tool ran (`PostToolUse`), the turn ended (`Stop`), a new prompt arrived (`UserPromptSubmit`) or the session ended. If the agent stops the hook early (its timeout ran out, or it was interrupted), the card goes too.

**Safety.** Answers come only from clicks on the card. No API endpoint, `islet://` URL or script can approve anything, so a script holding the API token can at most show a card. The local-network bridge never shows cards. Each waiting card costs one sleeping `isletctl` process and one open loopback connection; nothing polls.

**Back to the terminal.** The hook records where the agent runs: `TERM_PROGRAM`, `__CFBundleIdentifier`, the tmux, WezTerm, kitty and Zellij pane variables, and the terminal device. The window button on the card, and **Terminal**, bring that app forward if it's running and select the tmux pane (or WezTerm pane). This needs no Automation permission. Individual iTerm2 and Terminal tabs are not selected.

Settings → Coding agents → Approvals has **Answer requests in the notch** (on by default) and **Hand back to the terminal after** (5 minutes by default). After changing the wait, press **Update…** beside each connected agent so the hooks' `--wait` and `timeout` follow it; until then the shorter of the two applies.

---

## Usage limits

The Home tab shows the 5-hour and weekly plan limits of Claude Code and Codex, one card per agent: a bar for each window, the share used and the time until it resets. For Claude it also shows the model and how full the context window is while a session is active.

The closed island shows nothing about usage until a window reaches 90%, and again at 100%. Each crossing posts one normal activity ("Claude 5-hour limit at 90%", "Resets 16:40") that leaves on its own. Alerts are armed again when the window resets.

Islet reads only what the two tools already write on this Mac. It doesn't read their login tokens, doesn't call their usage endpoints and sends nothing over the network. Switch either source off in Settings → Coding agents → Usage limits (`claudeUsageEnabled` and `codexUsageEnabled` in `config.json`).

### Claude Code

Claude Code keeps no usage on disk that Islet can read. It passes plan usage only to its status line command on stdin (`rate_limits.five_hour` and `rate_limits.seven_day`, for Pro and Max plans, after a session's first reply), so the figures update while Claude Code runs in a terminal. `isletctl statusline` records them.

While Claude Code is installed (it has a `~/.claude` folder) without Islet's status line, Home shows Claude with a **Show usage** button that opens this part of Settings. Once the status line is in place, Home says "Waiting for Claude Code" until the first figures arrive. The "x" on that row hides it for good (`"claudeUsageHint": false`).

In Settings → Coding agents → Usage limits, click **Show Usage…** beside Claude Code limits. A sheet shows the `statusLine` command before and after, and nothing is written until you click Add.

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
| **Siri** | Name a shortcut and say it: "Hey Siri, notch timer". Recipes for timers, the Pomodoro and asking Apple Intelligence with the answer in the notch: [Siri and Shortcuts](SHORTCUTS.md). |
| **Raycast** | Script commands in [`integrations/raycast/`](../integrations/raycast/) (timer, toggle). Any Raycast deeplink can be an activity `url`. |
| **Alfred** | Workflow → *Open URL* `islet://timer?minutes={query}`, or *Run Script* `isletctl notify "{query}"`. |
| **Hammerspoon** | [`integrations/hammerspoon/islet.lua`](../integrations/hammerspoon/islet.lua) posts to the API, with a Wi-Fi-change example. |
| **BetterTouchTool / Keyboard Maestro** | Action "Open URL" with an `islet://` link, or "Execute shell script" with `isletctl`. Good for trackpad gestures (`islet://toggle`) and hotkeys (`islet://media/next`). |
| **Stream Deck** | "Website" action with an `islet://` URL (background mode), or a "System: Open" action running `isletctl`. |
| **Home Assistant** | [`integrations/home-assistant/islet.yaml`](../integrations/home-assistant/islet.yaml): a `rest_command` to the LAN bridge, plus a doorbell automation. |
| **Makefiles, npm scripts, git hooks** | `isletctl run -- <cmd>` or `isletctl notify`. For example, a `post-merge` hook: `isletctl notify "Pulled $(git rev-parse --short HEAD)" --icon sf:arrow.down.circle`. |
| **CI (GitHub Actions)** | Watch a run from your Mac: `isletctl run --title "CI main" -- gh run watch --exit-status`. |
| **A hotkey for the Ask box** | In any of the above, bind a hotkey to Open URL `islet://ask`, or `islet://ask?q={query}` to pass what you typed in Alfred or Raycast. The island opens with the question filled in; you press Return to send. See [AI.md](AI.md). |

---

## Gestures

Two-finger swipes on the island work without any permission: Islet reads the scroll events its own windows already receive, and never watches the trackpad elsewhere.

| Swipe | Where | Does |
|---|---|---|
| Down | closed island | open it (handy with *Open the island* set to *On click*) |
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

To set up the bridge, turn on **Accept requests from this network** in *Settings → Advanced → iPhone bridge* and press **Copy** beside the token. This is the bridge's own token, not the one `isletctl token` prints; neither works in place of the other. Then on the iPhone: Shortcuts → Automation → **New** → pick a trigger → **Get Contents of URL**:
- URL: `http://<your-mac>.local:47832/v1/notify`
- Method: POST
- Headers: `Authorization: Bearer <bridge token>`
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

The bridge is not encrypted: anyone on the same Wi-Fi can read what a Shortcut sends, token included. So it only accepts notifications, timers, Focus and simple activities, and everything else gets `403`. It can't read your notifications, activities or state, control media or the island, or take part in agent approvals. Activities from the bridge have no links or buttons, use symbols, emoji or app icons only, get ids starting with `lan-`, and are at most `high` priority. If the token may have leaked, press **New Token** and paste the new one into your Shortcuts.

The bridge also rejects browser origins, rate-limits each client (30 requests / 10 s), limits bodies to 16 KB and serves 8 connections at once. Bonjour advertises it as "Islet", not by your Mac's name. The full list of routes is in [API.md](API.md#local-network-bridge-iphone-shortcuts).

---

## Script widgets (xbar-compatible)

Turn on **Run scripts from the plugins folder** in *Settings → Advanced → Script widgets*, then drop executables into `~/.config/islet/plugins/` (**Open Folder** there):

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
