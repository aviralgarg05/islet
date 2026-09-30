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
| Any app that reports Now Playing (Music, Spotify, Podcasts, TV, Safari/Chrome/Arc/Firefox tabs, VLC, IINA, Plexamp, Tidal, Cider…) | Artwork + equalizer in the closed island; controls, scrubber and times when open | nothing |
| FaceTime, Zoom, Teams, Slack huddles, Discord, WhatsApp, Webex, Skype, Telegram, Signal, Meet in a browser | Green call pill with a live timer; video icon when the camera is on | nothing |
| Calendar (iCloud, Google and Exchange accounts added to macOS) | "Starting soon" 5 minutes before with a **Join** button for Zoom/Meet/Teams/Webex links | Calendar access |
| Battery | Charging splash, low-battery warning with a Battery Settings button, Low Power Mode on/off | nothing |
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

### Approvals from the notch

Claude Code, Codex and Cursor can ask you in the island instead of the terminal: permission to run a command or change a file, Claude's multiple-choice questions, and plans from plan mode. The island opens a card with the agent and project, the full command or file path (the box scrolls; nothing is cut short), and these buttons:

| Button | What the agent gets |
|---|---|
| **Allow** | Allowed, this once |
| **Always** | Allowed, plus the rule Claude suggests (for example `Bash(npm test:*)`) for the rest of this session only. Claude Code only, and only when Claude suggests a rule |
| **Deny** | Denied, with a short message so the agent knows you said no |
| **Terminal** | No answer: the agent asks in the terminal as usual, and Islet brings that terminal forward |

Questions show their options as buttons. When a question takes several answers, tick them and press **Send**. Plans show the Markdown with **Approve** and **Keep planning**. With more requests waiting, the card shows **+N** and they come one at a time. The chevron hides the card; it comes back when you open the island. While the island is hidden for a fullscreen app, the card waits for you to open the island.

**Risky commands.** Commands are checked against a list of patterns: `rm -rf`, `sudo`, `git push --force`, `git reset --hard`, `git clean -f`, `curl … | sh`, `chmod 777`, `dd` to a disk, `mkfs`, `diskutil erase…`, `npm publish`, `DROP TABLE`, writes outside the project folder, files that often hold secrets, and a few more. A match is shown in orange above the command, **Allow** then needs a second click (or a press and hold), and **Always** is hidden. The rules only add friction; they never block anything.

**Claude Code:** Settings → Integrations → **Install for Claude Code…** lists the hooks it will add to `~/.claude/settings.json` and asks before writing. Your own hooks and settings stay as they are, and the previous file is kept as `settings.json.bak`. Running it again changes nothing. To do it by hand, merge [`integrations/claude-code/settings.json`](../integrations/claude-code/settings.json). Next to the status hooks it adds:

```json
"PermissionRequest": [{"hooks": [{"type": "command", "command": "isletctl hook claude --wait 300", "timeout": 330}]}],
"PreToolUse": [{"matcher": "AskUserQuestion|ExitPlanMode",
                "hooks": [{"type": "command", "command": "isletctl hook claude --wait 300", "timeout": 330}]}]
```

The hook's `timeout` is 30 seconds longer than `--wait`, so Islet always answers first. Claude Code's deny and ask rules still apply: an **Allow** from the notch can't override them.

**Codex CLI:** add `hooks = true` under `[features]` in `~/.codex/config.toml`, copy [`integrations/codex/hooks.json`](../integrations/codex/hooks.json) to `~/.codex/hooks.json`, then run `/hooks` in Codex once to trust the new hooks. Codex won't run them until you do.

**Cursor:** copy [`integrations/cursor/hooks.json`](../integrations/cursor/hooks.json) to `~/.cursor/hooks.json` (or a project's `.cursor/hooks.json`). Shell commands and MCP tool calls then ask in the notch, and **Terminal** hands the choice back to Cursor's own prompt.

**How it works.** `isletctl hook <agent> --wait N` posts the hook's payload to `/v1/hooks/<agent>?wait=N` and waits (see [API.md](API.md#approvals-long-poll)). The card appears a quarter of a second later, so the terminal can print its own prompt first. Islet holds the request until you answer, for at most N seconds or the wait set in Settings, whichever is shorter, and `isletctl` prints the answer in the form the agent expects. Everything fails open: if Islet isn't running, approvals are off, the wait runs out or you choose **Terminal**, `isletctl` prints nothing and exits 0, and the agent asks in the terminal as if no hook had run. Only events that ask for a decision wait; every other event is sent and forgotten within 1.5 seconds.

Cards clear themselves when a later event shows the question is settled: the tool ran (`PostToolUse`), the turn ended (`Stop`), a new prompt arrived (`UserPromptSubmit`) or the session ended. If the agent stops the hook early (its timeout ran out, or it was interrupted), the card goes too.

**Safety.** Answers come only from clicks on the card. No API endpoint, `islet://` URL or script can approve anything, so a script holding the API token can at most show a card. The local-network bridge never shows cards. Each waiting card costs one sleeping `isletctl` process and one open loopback connection; nothing polls.

**Back to the terminal.** The hook records where the agent runs: `TERM_PROGRAM`, `__CFBundleIdentifier`, the tmux, WezTerm, kitty and Zellij pane variables, and the terminal device. The window button on the card, and **Terminal**, bring that app forward if it's running and select the tmux pane (or WezTerm pane). This needs no Automation permission. Individual iTerm2 and Terminal tabs are not selected.

Settings → Integrations → Coding agents has **Answer agent approvals in the notch** (on by default) and **Hand back to the terminal after** (5 minutes by default).

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
