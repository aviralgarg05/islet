# 05 — App Integration Catalogue

**Goal:** make Islet "connect to almost every app" using only the surfaces Islet already ships: the local HTTP API (`127.0.0.1:47831`, bearer token), `isletctl`, the `islet://` URL scheme, xbar/SwiftBar-style script widgets in `~/.config/islet/plugins`, the optional LAN bridge (port `47832`, Bonjour `_islet._tcp`) and the built-in monitors (Now Playing, calendar, battery, HUDs, camera/mic/call detection, downloads watcher, Accessibility notification mirroring).
**Machine used for local checks:** macOS 27.0.1 (Darwin 27.0.0), Apple silicon, Command Line Tools only (no Xcode.app).
**Date:** 2026-09-30

**Key findings**

- **Four universal hooks cover most chat and meeting apps with no per-app code:** Accessibility banner mirroring, per-process mic use (calls), system Now Playing, and Dock badge counts. Per-app glue only adds mute state, deep links and progress (§0.2).
- **Event-driven local sources exist for about half the list:** Music/Spotify distributed notifications, Mail rules, Folder Actions, Xcode Behaviors, Cursor/Claude Code/Codex hooks, shell `preexec`/`precmd`, `docker events`, the OBS WebSocket, HandBrake's stdout, torrent-client "done" scripts, Hammerspoon watchers, Home Assistant `rest_command`, and Shortcuts automations on Mac (macOS 26+) and iPhone.
- **SaaS tools (Todoist, Notion, Linear, Figma, GitHub) only push webhooks to public HTTPS endpoints**, so for a local notch app the practical path is a polling widget (5–15 min).
- **Dead ends confirmed:** the Microsoft Teams local meeting API was retired on 2026-06-30, so there is no Teams mute state. Discord RPC voice scopes are partner-only. Messages has had no incoming-message AppleScript event since 10.13.4. Firefox has no usable AppleScript. Arc is in maintenance mode.
- **Biggest Islet gaps these recipes expose:** a supervisor for long-running bridge scripts, `endsAt`/`actions` parity in `isletctl` and `islet://`, built-in badge counts, and config-driven distributed-notification rules (§12).

---

## 0. How to read this catalogue

Each app entry has three parts:

- **(a) Exposes**: what the app offers that Islet can use (distributed notifications, AppleScript dictionary, URL schemes, CLI, local API, webhooks, logs), and whether it is **event-driven** or needs **polling**.
- **(b) Recipe**: a copy-pasteable snippet that uses an existing Islet surface.
- **(c) Islet shows**: what appears in the **compact** island (closed notch: icon on the left wing, short `trailing` text on the right), as a **sneak** (a brief auto-expansion when an activity is created, updated or finishes), and in the **expanded** island (title, subtitle, progress or countdown, up to 2 action buttons).

Evidence tags:

| Tag | Meaning |
|---|---|
| **[VERIFIED local]** | Read from the installed app bundle on this Mac (`Info.plist` `CFBundleURLTypes`, the `.sdef` scripting dictionary, strings in the binary, or a read-only `--help`/status command). Nothing was launched, played, paused or scripted. |
| **[web: URL]** | Taken from the linked documentation or source. |
| **[UNVERIFIED]** | Plausible and widely reported, but not confirmed from a primary source or on this Mac. Test before shipping. |

Apps **installed on this Mac** (so local checks were possible): Music, Podcasts, Safari, Google Chrome, Brave, Spotify, zoom.us, Microsoft Teams, Slack, Discord, Messages, FaceTime, Mail, Calendar, Reminders, Notes, Visual Studio Code, Terminal, Docker Desktop, Finder, Shortcuts, OBS, Time Machine, Tailscale, Figma, plus the `gh`, `brew`, `docker`, `tailscale`, `tmutil` and `shortcuts` CLIs.
**Not installed** (web-sourced only): Arc, Firefox, Things 3, Todoist, OmniFocus, Fantastical, Xcode, Cursor, iTerm2, Ghostty, Warp, Raycast, Alfred, Hammerspoon, BetterTouchTool, Keyboard Maestro, Stream Deck, 1Password, Obsidian, Notion (desktop), Linear, Final Cut Pro/Compressor, HandBrake, Transmission, qBittorrent.

### 0.1 Conventions used in every recipe

`isletctl` must be on `PATH` (`ln -sf /Applications/Islet.app/Contents/MacOS/isletctl /opt/homebrew/bin/isletctl`). Scripts launched by other apps (Mail rules, Xcode behaviors, qBittorrent, LaunchAgents) do **not** get your shell `PATH`, so they use the absolute path `/opt/homebrew/bin/isletctl`.

For `curl` recipes, read the port and token from Islet's discovery file instead of hard-coding them:

```bash
# ~/.config/islet/lib.sh — `source` this from any script
ISLET_JSON="$HOME/Library/Application Support/Islet/api.json"
ISLET_PORT=$(/usr/bin/jq -r .port  "$ISLET_JSON" 2>/dev/null || echo 47831)
ISLET_TOKEN=$(/usr/bin/jq -r .token "$ISLET_JSON" 2>/dev/null)
islet() {  # islet METHOD PATH [JSON]   (works in bash and zsh)
  local args=(-fsS -m 2 -X "$1" "http://127.0.0.1:$ISLET_PORT$2"
              -H "Authorization: Bearer $ISLET_TOKEN" -H 'Content-Type: application/json')
  [ -n "$3" ] && args+=(--data-raw "$3")
  /usr/bin/curl "${args[@]}" >/dev/null 2>&1
}
```

Rules of thumb that fall out of the Islet API (from `docs/API.md` and `Sources/`):

- **Use a stable `id`** so updates replace the activity instead of stacking new ones. `isletctl set <id>` is an upsert (`PUT /v1/activities/{id}`); omitted fields keep their value.
- **`state: success|failure` auto-dismisses after 10 s** unless you set `ttl`. Use `priority: high` for things that should beat music in the closed notch (a failing build, a call), and `critical` only for things that must break through fullscreen.
- **Countdowns and count-ups** (`endsAt`, `startedAt`) are not `isletctl set` flags; send them with `curl` (or use `isletctl timer`). Islet then animates the clock itself, so you post **once** instead of every second.
- **Script widgets are killed after 15 s.** Anything that has to *stream* (`docker events`, `tailscale debug watch-ipn`, OBS/Teams WebSockets, `log stream`) belongs in a **LaunchAgent**, not a widget. Template:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<!-- ~/Library/LaunchAgents/dev.islet.bridge.NAME.plist ; load with:
     launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/dev.islet.bridge.NAME.plist -->
<plist version="1.0"><dict>
  <key>Label</key><string>dev.islet.bridge.NAME</string>
  <key>ProgramArguments</key><array>
    <string>/bin/zsh</string><string>-lc</string><string>$HOME/.config/islet/bridges/NAME.sh</string>
  </array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>ThrottleInterval</key><integer>30</integer>
  <key>StandardErrorPath</key><string>/tmp/islet-bridge-NAME.log</string>
</dict></plist>
```

- **Script widgets** print either xbar text or **one** Islet activity JSON object. The file name sets the interval (`name.5m.sh`). Print nothing when there is nothing to show.
- **Never put secrets in the notch.** It is visible on screen shares. Recipes for 1Password, Messages and Mail show counts or senders, never contents, unless you opt in.

### 0.2 Universal hooks that cover apps with no API

Before writing per-app glue, check whether one of these already covers the app. Most chat and meeting apps need nothing else.

| # | Hook | Covers | Event / poll | Notes |
|---|---|---|---|---|
| U1 | **Accessibility notification mirroring** (built-in, opt-in) | Anything that posts a banner: Slack, Discord, Teams, WhatsApp, Telegram, Messages, Mail, Calendar alerts, 1Password, Figma, Linear, Docker Desktop, iTerm2/Ghostty OSC 9 notifications | Event | One integration, every app. Use per-app rules (`appRules`, `mutedSources`) to keep noise down. |
| U2 | **Mic/camera/call detection** (built-in, CoreAudio per-process input) | Zoom, Teams, FaceTime, Slack huddles, Discord voice, Meet in any browser | Event | Shows a green/orange dot and a call count-up. Map helper processes to parent apps. |
| U3 | **System Now Playing** (built-in, MediaRemote via perl) | Music, Spotify, Podcasts, TV, VLC, browsers (YouTube, SoundCloud, Netflix), IINA | Event | The app-specific hooks below only matter as fallbacks or for extra metadata. |
| U4 | **Downloads watcher** (built-in) | Safari, Chrome, Brave, Arc, Firefox, Transmission/qBittorrent (if saving to `~/Downloads`), AirDrop, Taildrop | Event | `NSProgress` file subscription on `~/Downloads`, with a `.download`/`.crdownload`/`.part` fallback. |
| U5 | **Dock badge counts** via `lsappinfo` | Unread counts for Slack, Mail, Discord, Teams, Telegram, Outlook (Messages/WhatsApp may need the AX fallback) | Poll (widget) | No Automation or Accessibility permission. See recipe below. |
| U6 | **Distributed notifications** (Hammerspoon or a tiny Swift listener) | Music, Spotify, screen lock/unlock, any app that broadcasts | Event | Listening needs no permission. Names per app below. |
| U7 | **`NSWorkspace` app launch/quit/activate** (Hammerspoon `hs.application.watcher`) | "Xcode opened → show today's build count", "Zoom quit → clear call activity" | Event | |
| U8 | **Unified log** (`log stream --predicate …`) | Apps with no API at all (last resort) | Event | Brittle; message formats change between releases. Run as a LaunchAgent. |

**U5 recipe — unread badges for chat apps** (`~/.config/islet/plugins/unread.1m.sh`):

```bash
#!/bin/zsh
# Reads Dock badge labels. No Automation/Accessibility prompt. Prints one Islet activity.
typeset -A apps=( Slack com.tinyspeck.slackmacgap  Mail com.apple.mail  Messages com.apple.MobileSMS
                  Discord com.hnc.Discord  Teams com.microsoft.teams2 )
parts=(); total=0
for name bid in ${(kv)apps}; do
  asn=$(lsappinfo find bundleid=$bid) || continue
  [[ -z $asn ]] && continue
  n=$(lsappinfo info -only StatusLabel "$asn" | sed -n 's/.*"label"="\([^"]*\)".*/\1/p')
  [[ -z $n ]] && continue
  parts+=("$name $n"); [[ $n == <-> ]] && (( total += n ))
done
(( ${#parts} )) || exit 0          # nothing unread: print nothing
printf '{"id":"unread","title":"Unread","subtitle":"%s","icon":"sf:tray.full.fill","trailing":"%s","priority":"low","source":"unread"}\n' \
  "${(j: · :)parts}" "$total"
```

`lsappinfo find`/`info -only <key>` work read-only on this Mac **[VERIFIED local]** (no app had a badge during testing). The output for a badged app is `"StatusLabel"={ "label"="3" }`; labels can be `99+` or `•`, which the script keeps as text; Messages and WhatsApp reportedly return NULL, so fall back to the `AXStatusLabel` Accessibility attribute of their Dock item for those **[web: SketchyBar discussion #317]**.

**U6 recipe — a generic distributed-notification bridge in Hammerspoon.** Hammerspoon is the lowest-friction place to listen to broadcasts and forward them. Save this helper once; later recipes `require` it.

```lua
-- ~/.hammerspoon/islet.lua
local M = {}
local function cfg()
  local f = io.open(os.getenv("HOME") .. "/Library/Application Support/Islet/api.json")
  if not f then return nil end
  local c = hs.json.decode(f:read("*a")); f:close(); return c
end
function M.call(method, path, body)
  local c = cfg(); if not c then return end
  hs.http.doAsyncRequest(("http://127.0.0.1:%d%s"):format(c.port, path), method,
    body and hs.json.encode(body) or nil,
    { ["Authorization"] = "Bearer " .. c.token, ["Content-Type"] = "application/json" },
    function() end)
end
function M.set(id, spec) spec.id = id; M.call("POST", "/v1/activities", spec) end
function M.notify(title, subtitle, icon) M.call("POST", "/v1/notify", {title=title, subtitle=subtitle, icon=icon}) end
function M.rm(id) M.call("DELETE", "/v1/activities/" .. id) end
return M
```

```lua
-- ~/.hammerspoon/init.lua
islet = require("islet")
```


---

## 1. Summary matrix

**E** = event-driven, **P** = polling, **U1–U8** = universal hooks from §0.2. "Local" = checked in the app bundle on this Mac.

| App | Best hook for Islet | E/P | Recipe surface | Islet shows | Evidence |
|---|---|---|---|---|---|
| Music | Built-in Now Playing; `com.apple.Music.playerInfo`; AppleScript | E | built-in, widget for radio titles | player, sneak on track change | Local |
| Spotify | Built-in; `com.spotify.client.PlaybackStateChanged`; AppleScript; `spotify:` | E | built-in, Hammerspoon → `/v1/media` | player | Local |
| Podcasts | Now Playing only (no sdef) | E | `isletctl timer` + `media pause` | player, sleep countdown | Local |
| Safari | AppleScript (`do JavaScript`, tabs); U4 | P/E | `pin-tab` script | pinned-tab pill, downloads | Local |
| Chrome / Brave | AppleScript (`execute javascript`, `loading`); MV3 extension → HTTP API | E | extension, `pin-tab` | per-download rings | Local |
| Arc | AppleScript (tabs, spaces); Chromium extension; maintenance mode | E | same as Chrome | same | Web |
| Firefox | WebExtension only (no AppleScript) | E | extension | downloads | Web |
| Zoom | U2 + Meeting-menu mute state (AX); `zoommtg:` | E/P | Hammerspoon | call count-up, Muted/Live wing, mic HUD | Local + web |
| Teams | U1/U2/U5; **local API retired 2026-06-30** | E | `appRules` | call pill, badge | Local + web |
| Slack | U1/U2/U5; `slack:` links; Web API DND | E/P | `deepwork` script | Focus pill + countdown | Local + web |
| Discord | U1/U2/U5; `discord:` links (RPC is partner-only) | E | action buttons | call pill, shortcuts | Local + web |
| Messages | U1; `chat.db` (FDA); sdef has no receive event | E/P | unread widget | count pill | Local + web |
| FaceTime / Phone | U2; `facetime:`, `facetime-audio:`, `tel:` | E | action buttons | call buttons, count-up | Local |
| Mail | Rules → `perform mail action with messages` | E | AppleScript rule | sender sneak, opens message | Local |
| Calendar | Built-in EventKit; `iCal.sdef` | E | activity with Join action | T-5 countdown + Join | Local |
| Reminders | EventKit; AppleScript | P | widget | due-soon count | Local |
| Notes | AppleScript (no events) | P | capture button | pill | Local |
| Things 3 | URL scheme; AppleScript | P | widget | Today count + Add | Web |
| Todoist | API v1 | P | widget | due count | Web |
| OmniFocus | URL scheme; Omni Automation; AppleScript | P | widget | due count | Web |
| Fantastical | `x-fantastical://parse`; EventKit | E | `fadd` | confirmation sneak | Web |
| Xcode | Behaviors → Run script | E | 3 scripts | build spinner / result | Web |
| VS Code | tasks + shell hook; `vscode:` | E | `tasks.json` + §10 | task result | Local + web |
| Cursor | `hooks.json` (after*/stop) → `/v1/hooks/cursor` | E | hook script | agent working / done | Web |
| Terminal | shell hook; sdef `busy` | E | §10 | per-command result | Local |
| iTerm2 | shell hook; Triggers; Python API | E | Trigger → `isletctl` | "needs input" alert | Web |
| Ghostty | shell hook; `notify-on-command-finish`; OSC 9 → U1 | E | §10 / config | per-command result | Web |
| Warp | built-in notifications → U1; shell hook (verify) | E | §10 | per-command result | Web |
| Docker Desktop | `docker events`; `docker desktop status` | E | LaunchAgent bridge | crash / unhealthy sneaks | Local |
| GitHub / `gh` | `gh run view --json jobs`; `gh search prs` | P | `ghwatch`, widget | CI stepper, review count | Local |
| Homebrew | `brew outdated --json=v2` | P | widget, `isletctl run` | update count | Local + web |
| Finder | Folder Actions; NSProgress (U4) | E | folder-action script | "new file" sneak | Local |
| Shortcuts (Mac) | automations (macOS 26+), `shortcuts run`, URL | E | Open URL `islet://` | anything | Local + web |
| Raycast | Script Commands; deeplinks | E | script command | timer etc. | Web |
| Alfred | workflows; External Triggers; `alfred://runtrigger` | E | Open URL | timer etc. | Web |
| Hammerspoon | distributed notifications, app/Wi-Fi/USB/lock watchers | E | `islet.lua` | sneaks | Web |
| BetterTouchTool | Open URL / shell action; `btt://trigger_named` | E | Open URL | toggles, timers | Web |
| Keyboard Maestro | shell action; `kmtrigger://` | E | shell action | sneaks | Web |
| Stream Deck | API Request plugin (POST + headers) | E | plugin | timers, state | Web |
| Home Assistant | `rest_command` → LAN bridge; REST poll | E/P | YAML | appliance done, countdowns | Web |
| 1Password | `op` CLI only; U1 | – | mute + `isletctl run` | nothing sensitive | Web |
| Obsidian | files; Shell commands / Local REST API plugins | P/E | widget | checklist stepper | Web |
| Notion | API (data sources) | P | widget | due count | Web |
| Linear | GraphQL | P | widget | current issue | Web |
| Figma | REST comments; `figma:` | P | widget | new-comment sneak | Local + web |
| Final Cut / Compressor | Compressor CLI; U1 | P | `cmpr` | export spinner → done | Web |
| HandBrake | `HandBrakeCLI` progress lines / `--json` | E | `hb` | % ring + ETA | Web |
| Transmission / qBittorrent | done scripts; RPC / WebUI API | E/P | scripts + widget | ring + done sneak | Web |
| OBS | obs-websocket v5 (bundled, off by default) | E | Python bridge | REC/LIVE count-up | Local + web |
| Time Machine | `tmutil status` | P | widget | backup ring | Local |
| Tailscale | `tailscale status --json`; `debug watch-ipn` | P/E | widget | exit-node / disconnected pill | Local |


---

## 2. Media

### 2.1 Apple Music

- **(a) Exposes**
  - **Distributed notification `com.apple.Music.playerInfo`** (event). The string is in the Music binary **[VERIFIED local]**. Music's userInfo mirrors the old `com.apple.iTunes.playerInfo` keys (`Player State`, `Name`, `Artist`, `Album`, `Album Artist`, `Genre`, `Total Time` in ms, `PersistentID`, `Store URL`, `Location`, `Track Number`, `Year`…) **[web: distnote README, dev.to write-up; exact Music key set UNVERIFIED]**.
  - **AppleScript** (`com.apple.Music.sdef` **[VERIFIED local]**): `player state`, `player position` (settable), `current track` (name, artist, album, duration, artwork), `current stream title`/`current stream URL` (radio), `sound volume`, `mute`, `shuffle enabled`, `current AirPlay devices`; commands `playpause`, `next track`, `back track`, `search`, `play`.
  - **URL schemes** `music://`, `musics://`, `itms://`, `itmss://` **[VERIFIED local]**.
  - Already handled by Islet's built-in Now Playing (U3) and its Music/Spotify notification listener.
- **(b) Recipe — radio "now playing" titles.** Radio streams change `current stream title` without a new track, so Now Playing often shows only the station. A 30 s widget fills the gap (it only talks to Music if Music is already running, so it never launches it):

```bash
#!/bin/zsh
# ~/.config/islet/plugins/music-radio.30s.sh
pgrep -xq Music || exit 0
t=$(osascript -e 'tell application "Music" to if player state is playing then get current stream title' 2>/dev/null)
[[ -z $t || $t == "missing value" ]] && exit 0
printf '{"id":"music-radio","title":"%s","subtitle":"Apple Music Radio","icon":"app:com.apple.Music","priority":"low","source":"com.apple.Music","sneak":false}\n' "${t//\"/\\\"}"
```

- **(c) Islet shows:** built-in: artwork in the left wing, a live waveform on the right; sneak on track change; expanded player with scrubber and controls. The widget adds a low-priority line under it.

### 2.2 Spotify

- **(a) Exposes**
  - **Distributed notification `com.spotify.client.PlaybackStateChanged`** (event) **[VERIFIED local: string present in the Spotify binary]**. userInfo keys: `Player State` (`Playing`/`Paused`/`Stopped`), `Name`, `Artist`, `Album`, `Album Artist`, `Track ID` (`spotify:track:…`), `Track Number`, `Disc Number`, `Duration` (ms), `Playback Position` (seconds, float), `Play Count`, `Popularity`, `Has Artwork` **[web: community gist]**. A passive listener on this Mac saw no broadcasts during an earlier 4-minute window without playback changes, so treat it as a change trigger, not a heartbeat.
  - **AppleScript** (`Spotify.sdef` **[VERIFIED local]**): application `current track`, `player state`, `player position`, `sound volume`, `shuffling`, `repeating`; track `name`, `artist`, `album`, `duration`, `id`, `artwork url`, `spotify url`, `popularity`, `starred`; commands `playpause`, `next track`, `previous track`, `play track "<spotify: URI>"`.
  - **URL scheme** `spotify:` **[VERIFIED local]** (`spotify:playlist:<id>`, `spotify:track:<id>`).
  - Built-in Now Playing already covers it (U3).
- **(b) Recipe — Hammerspoon fallback that feeds `/v1/media`** (useful if the MediaRemote adapter ever breaks, or to get Spotify's HTTPS artwork URL):

```lua
-- ~/.hammerspoon/init.lua  (after `islet = require("islet")`)
spotifyWatcher = hs.distributednotifications.new(function(_, _, info)
  if not info then return end
  if info["Player State"] == "Stopped" then islet.call("DELETE", "/v1/media"); return end
  -- one Automation prompt (Hammerspoon → Spotify) the first time
  local ok, url = hs.osascript.applescript('tell application "Spotify" to get artwork url of current track')
  islet.call("POST", "/v1/media", {
    title = info["Name"], artist = info["Artist"], album = info["Album"],
    isPlaying = info["Player State"] == "Playing",
    duration = (info["Duration"] or 0) / 1000, elapsed = info["Playback Position"],
    bundleID = "com.spotify.client", appName = "Spotify",
    artworkURL = ok and url or nil })
end, "com.spotify.client.PlaybackStateChanged")
spotifyWatcher:start()
```

  Quick action from anywhere (Raycast, Alfred, Stream Deck): `open "spotify:playlist:37i9dQZF1DX8Uebhn9wzrS" && isletctl notify "Focus playlist" --icon app:com.spotify.client --ttl 4`.
- **(c) Islet shows:** same as Music (artwork, waveform, controls). The `/v1/media` fallback shows the same player with Spotify's icon.

### 2.3 Podcasts

- **(a) Exposes:** **no AppleScript dictionary** (no `.sdef` in the bundle) **[VERIFIED local]**. URL schemes `podcasts://`, `podcast://`, `pcast://`, `itms-podcasts://` **[VERIFIED local]**. No documented distributed notification; the `com.apple.podcasts.*` strings in the binary look like queue/bundle identifiers, not broadcasts **[UNVERIFIED]**. Playback reaches Islet through Now Playing only (U3).
- **(b) Recipe — sleep timer that pauses whatever is playing:**

```bash
# "podsleep 30" in ~/.zshrc, or a Raycast/Alfred script command
podsleep() {
  local m=${1:-30}
  isletctl timer ${m}m --title "Sleep timer"
  ( sleep $(( m * 60 )) && isletctl media pause && isletctl notify "Paused" --icon sf:moon.zzz.fill ) &!
}
```

- **(c) Islet shows:** the player (built-in), plus an orange countdown ring in the right wing and a sneak when the timer ends.


---

## 3. Browsers

Browser **media** already reaches Islet through Now Playing (U3), and **downloads** through the `~/Downloads` watcher (U4). The recipes below add what those miss: pinning a tab, and per-download progress straight from the browser.

### 3.1 Safari

- **(a) Exposes:** `Safari.sdef` **[VERIFIED local]**: `document` (URL, name, text, source), `window.current tab`, `tab` (URL, name, index, visible, `pid`), commands `do JavaScript`, `add reading list item`, `search the web`, `show bookmarks`. `do JavaScript` requires "Allow JavaScript from Apple Events" (Settings → Advanced → "Show features for web developers", then the Developer tab) **[web: Apple Safari guide; exact toggle location UNVERIFIED on Safari 27]**. URL schemes include `x-safari-https`, `x-webkit-app-launch`, `prefs` **[VERIFIED local]**. No events for scripts → on-demand or polling. Web push notifications are regular banners (U1).
- **(b) Recipe — "pin this tab to the notch"** (works for Safari and the Chromium browsers in §3.2–3.3; bind it to a hotkey in Raycast, Alfred, BetterTouchTool or Keyboard Maestro):

```bash
#!/bin/zsh
# ~/bin/pin-tab — pin the frontmost browser tab as a low-priority activity; click reopens it
bid=$(lsappinfo info -only bundleid "$(lsappinfo front)" | sed -n 's/.*bundleID="\([^"]*\)".*/\1/p')
case $bid in
  com.apple.Safari)
    as='tell application id "com.apple.Safari" to tell front document to return (URL & linefeed & name)' ;;
  com.google.Chrome|com.brave.Browser|company.thebrowser.Browser|com.microsoft.edgemac)
    as="tell application id \"$bid\" to tell active tab of front window to return (URL & linefeed & title)" ;;
  *) isletctl notify "Not a supported browser" --ttl 3; exit 1 ;;
esac
out=$(osascript -e "$as") || exit 1          # first run: one Automation prompt per browser
url=${out%%$'\n'*}; title=${out#*$'\n'}; host=${${url#*://}%%/*}
isletctl set "pin-$(date +%s)" --title "$title" --subtitle "$host" --icon "app:$bid" \
  --url "$url" --priority low --ttl 0 --source pin-tab
```

- **(c) Islet shows:** a sneak with the page title and host; afterwards a low-priority pill with the browser icon; click opens the URL; `isletctl clear --source pin-tab` removes all pins.

### 3.2 Google Chrome (and Brave, Edge, other Chromium browsers)

- **(a) Exposes**
  - **AppleScript** (`scripting.sdef` **[VERIFIED local]** for Chrome 154 and Brave 153): `window` (`active tab`, `mode`), `tab` (`id`, `title`, `URL`, `loading`), commands `reload`, `go back`, `execute … javascript`, bookmarks. `execute javascript` needs View → Developer → "Allow JavaScript from Apple Events".
  - **URL scheme** `google-chrome://` for Chrome **[VERIFIED local]**; Brave registers only `http`/`https`/`file` **[VERIFIED local]**.
  - **MV3 extension → Islet HTTP API** (event-driven). The service worker may `fetch` `http://127.0.0.1/*` (the pattern matches any port) once that host permission is granted; content scripts may not **[web: Chrome network-requests and match-patterns docs]**. Islet explicitly accepts `chrome-extension://` origins with the token (`docs/API.md`). `chrome.downloads.onChanged` does **not** fire for `bytesReceived`, so progress must be polled with `downloads.search` **[web: chrome.downloads docs]**. Chrome 142+ "Local Network Access" prompts may apply to loopback requests; whether extensions are exempt is **[UNVERIFIED]**.
- **(b) Recipe — a 40-line "Islet bridge" extension** (per-download progress with the real file name; load unpacked from a folder):

```json
{
  "manifest_version": 3,
  "name": "Islet bridge",
  "version": "0.1",
  "permissions": ["downloads", "storage"],
  "host_permissions": ["http://127.0.0.1/*"],
  "background": { "service_worker": "background.js" }
}
```

```js
// background.js — set the token once in the service-worker console:
//   chrome.storage.local.set({isletToken: "<output of `isletctl token`>", isletPort: 47831})
async function islet(method, path, body) {
  const { isletToken, isletPort = 47831 } = await chrome.storage.local.get(["isletToken", "isletPort"]);
  if (!isletToken) return;
  await fetch(`http://127.0.0.1:${isletPort}${path}`, {
    method, body: body && JSON.stringify(body),
    headers: { Authorization: `Bearer ${isletToken}`, "Content-Type": "application/json" },
  }).catch(() => {});
}
const base = (p) => (p || "").split("/").pop();
let polling = false;
async function poll() {
  const items = await chrome.downloads.search({ state: "in_progress" });
  for (const d of items) {
    await islet("POST", "/v1/activities", {
      id: `chrome-dl-${d.id}`, title: base(d.filename) || "Downloading", source: "com.google.Chrome",
      subtitle: new URL(d.finalUrl || d.url).hostname, icon: "app:com.google.Chrome",
      progress: d.totalBytes > 0 ? d.bytesReceived / d.totalBytes : -1, state: "running", sneak: false,
    });
  }
  polling = items.length > 0;
  if (polling) setTimeout(poll, 1000);
}
chrome.downloads.onCreated.addListener(() => { if (!polling) { polling = true; setTimeout(poll, 300); } });
chrome.downloads.onChanged.addListener(async (delta) => {
  const id = `chrome-dl-${delta.id}`;
  if (delta.state?.current === "complete") {
    const [d] = await chrome.downloads.search({ id: delta.id });
    islet("POST", "/v1/activities", { id, title: base(d.filename), subtitle: "Downloaded", progress: 1,
      state: "success", url: "file://" + encodeURI(d.filename), source: "com.google.Chrome" });
  } else if (delta.state?.current === "interrupted") {
    islet("DELETE", `/v1/activities/${id}`);
  }
});
```

  The same code runs in Brave/Edge/Arc (Chromium extension APIs). Tab pinning: `pin-tab` from §3.1.
- **(c) Islet shows:** compact: Chrome icon + ring progress per download (up to the "activities shown together" setting); sneak on completion; click opens the file.

### 3.3 Arc

- **(a) Exposes:** AppleScript with `tab` (title, URL, id, location), `space`/`active space`, `make new tab with properties {URL:…}`, `select` **[web: Raycast Arc extension source]**; `execute javascript` **[UNVERIFIED]**. Chromium extension APIs work (so §3.2's extension works). Bundle id `company.thebrowser.Browser` **[UNVERIFIED]**. **Status:** Arc has been in maintenance mode since 2025 (security and Chromium updates only) while The Browser Company focuses on Dia; Atlassian announced the acquisition on 2025-09-04 **[web: Atlassian announcement]**. Do not invest in Arc-specific code.
- **(b) Recipe:** `pin-tab` (§3.1) and the Chromium extension (§3.2). Opening a URL in a specific Space is possible via AppleScript but not worth a dedicated integration.
- **(c) Islet shows:** same as Chrome.

### 3.4 Firefox

- **(a) Exposes:** effectively **no AppleScript** (Bugzilla 125419 "still NEW", 516502 "re-add AppleScript support for getting the current URL" open) **[web: Bugzilla]**. WebExtensions can `fetch` loopback with `host_permissions`; in Firefox MV3 host permissions are optional and user-revocable, so call `permissions.request()` from a user gesture **[web: MDN]**. `browser.downloads` exists. Islet accepts `moz-extension://` origins (`docs/API.md`). Downloads to `~/Downloads` appear as `.part` files (U4).
- **(b) Recipe:** port §3.2: replace `"background": {"service_worker": …}` with `"background": {"scripts": ["background.js"]}`, keep the code (Firefox also exposes the `chrome.*` namespace), and add an options button that calls `browser.permissions.request({origins: ["http://127.0.0.1/*"]})`. `pin-tab` cannot read the Firefox URL; use the extension (`browser.tabs.query({active: true, currentWindow: true})`) instead.
- **(c) Islet shows:** same as Chrome.


---

## 4. Calls and chat

**Baseline for every app in this section:** call/meeting presence comes from U2 (per-process mic use, event-driven), message banners from U1, unread counts from U5. The per-app hooks below add *mute state*, *deep links* and *status sync*.

### 4.1 Zoom

- **(a) Exposes:** **no AppleScript dictionary** (no `.sdef`; Info.plist only sets an empty `NSAppleEventsUsageDescription`) **[VERIFIED local, zoom.us 7.1.9]**. URL schemes `zoommtg://`, `zoomus://`, plus `tel`, `callto`, `sip` **[VERIFIED local]**; join syntax `zoommtg://zoom.us/join?action=join&confno=<id>&pwd=<pwd>`, which Zoom staff describe as deprecated but still working **[web: Zoom dev forum]**. No local API. In-meeting heuristic: the `CptHost` process exists **[web: brunerd]**. Mute state: the **Meeting** menu shows "Mute audio" (you're live) or "Unmute audio" (you're muted); readable with Accessibility, English UI only **[web: dustin.lol]**. All polling.
- **(b) Recipe — live mic indicator (Hammerspoon, polls every 1 s only while a meeting is up):**

```lua
-- ~/.hammerspoon/init.lua  (after `islet = require("islet")`)
local zoomMuted = nil
zoomTimer = hs.timer.doEvery(1, function()
  local z = hs.application.get("us.zoom.xos")
  local inMeeting = z and (z:findMenuItem({"Meeting", "Mute audio"}) or z:findMenuItem({"Meeting", "Unmute audio"}))
  if not inMeeting then
    if zoomMuted ~= nil then islet.rm("zoom-mic"); zoomMuted = nil end
    return
  end
  local muted = z:findMenuItem({"Meeting", "Unmute audio"}) ~= nil
  if muted == zoomMuted then return end
  zoomMuted = muted
  islet.set("zoom-mic", { title = muted and "Muted" or "Mic on", subtitle = "Zoom",
    icon = muted and "sf:mic.slash.fill" or "sf:mic.fill", tint = muted and "red" or "green",
    trailing = muted and "Muted" or "Live", priority = "high", source = "us.zoom.xos", ttl = 0 })
  islet.call("POST", "/v1/hud", { kind = "microphone", value = muted and 0 or 1, muted = muted })
end)
```

  Join buttons: give a calendar-style activity an action `{"title":"Join","url":"zoommtg://zoom.us/join?action=join&confno=123456789&pwd=abc"}` (§5.2).
- **(c) Islet shows:** U2's call pill with a count-up; this recipe adds a red "Muted"/green "Live" wing and a brief microphone HUD on every toggle.

### 4.2 Microsoft Teams

- **(a) Exposes:** URL schemes `msteams:`, `web+msteams:`, `sip`, `sips`, `tel` **[VERIFIED local, Teams 26225.x]**; no `.sdef` **[VERIFIED local]**. **The local third-party WebSocket API (`ws://localhost:8124`, pairing token, `meetingUpdate` with `isMuted`/`isVideoOn`/`isInMeeting`…) was retired on 2026-06-30** (Microsoft 365 message MC1266901, published 2026-03-31, "Retirement of legacy third-party meeting and call control APIs"; no replacement named) **[web: MC1266901, verified by fetch]**. Stream Deck/MuteMe integrations built on it stopped working. What remains: U1/U2/U5, deep links, and Microsoft Graph presence (`/me/presence`, needs an Entra app registration and a delegated token; polling) **[UNVERIFIED for personal accounts]**.
- **(b) Recipe:** rely on U2 for the call pill and U5 for unread counts. Add Teams-specific styling and keep it visible in fullscreen screen-shares:

In `~/.config/islet/config.json` (merge into any existing `appRules`):

```json
{ "appRules": [ { "bundleID": "com.microsoft.teams2", "showInFullscreen": true, "tint": "indigo" } ] }
```

  Open a chat from an Islet action: `msteams:/l/chat/0/0?users=someone@contoso.com` **[UNVERIFIED path]**.
- **(c) Islet shows:** call pill with count-up (U2), unread count (U5), mirrored banners (U1). **No mute state** after the API retirement.

### 4.3 Slack

- **(a) Exposes:** URL scheme `slack:` **[VERIFIED local]**: `slack://open?team=T…`, `slack://channel?team=T…&id=C…`, `slack://user?team=T…&id=U…` (IDs only) **[web: Slack deep-linking docs]**. No `.sdef`, no local API **[VERIFIED local: no sdef]**. Web API with a user token: `dnd.setSnooze` (`num_minutes`, scope `dnd:write`, returns `snooze_endtime`), `dnd.endSnooze`, `dnd.info`, `users.setPresence` (`auto|away`), `users.profile.set` (status) **[web: Slack API docs]**. Huddles show up as mic use (U2).
- **(b) Recipe — Focus ↔ Slack DND in one command** (call it from a Mac Shortcuts Focus automation, Raycast, or the iPhone recipe in §11):

```bash
#!/bin/zsh
# ~/bin/deepwork on|off [minutes]  — Slack DND + Islet focus pill + countdown
source ~/.config/islet/secrets.env            # SLACK_USER_TOKEN=xoxp-…
if [[ $1 == on ]]; then
  m=${2:-60}
  curl -fsS -X POST https://slack.com/api/dnd.setSnooze -H "Authorization: Bearer $SLACK_USER_TOKEN" \
       --data-urlencode "num_minutes=$m" >/dev/null
  isletctl focus "Deep Work" on
  isletctl timer ${m}m --title "Deep work"
else
  curl -fsS -X POST https://slack.com/api/dnd.endSnooze -H "Authorization: Bearer $SLACK_USER_TOKEN" >/dev/null
  isletctl focus "Deep Work" off
fi
```

- **(c) Islet shows:** an indigo Focus pill, an orange countdown, and Slack's unread badge (U5) still counting quietly.

### 4.4 Discord

- **(a) Exposes:** URL scheme `discord:` **[VERIFIED local]**; community-tested deep links `discord://-/channels/<guild>/<channel>` and `discord://-/channels/@me/<dm>` **[web, unofficial]**. Local RPC over `$TMPDIR/discord-ipc-{n}` exists and `GET_VOICE_SETTINGS` / `VOICE_SETTINGS_UPDATE` expose `mute`/`deaf`, but the `rpc` and `rpc.voice.read` scopes are "only available to approved partners"; an unapproved personal app works only for its listed testers **[web: Discord OAuth2 and RPC docs]**. So: no practical mute state.
- **(b) Recipe:** U2 (voice = mic in use), U5 (badge), plus one-click voice channels:

```bash
isletctl set discord-squad --title "Squad voice" --icon app:com.hnc.Discord --priority low \
  --url "discord://-/channels/123456789012345678/234567890123456789" --ttl 0
```

- **(c) Islet shows:** call pill while in voice; a low-priority "Squad voice" shortcut pill.

### 4.5 Messages

- **(a) Exposes:** `Messages.sdef` **[VERIFIED local]**: `account`, `chat`, `participant`, `file transfer` (with `file progress`, `transfer status`), commands `send`, `login`, `logout`. **No incoming-message event handler**: the AppleScript handler preference was removed in macOS 10.13.4 **[web: zekesnider.com]**, and the current sdef has no events **[VERIFIED local]**. Data lives in `~/Library/Messages/chat.db` (Full Disk Access required; since Ventura the body is often only in the `attributedBody` typedstream blob; `date` is nanoseconds since 2001-01-01) **[web]**. URL schemes `imessage:`, `sms:`, `im:`, `messages:` **[VERIFIED local]**. The Dock badge may read as NULL via `lsappinfo` for Messages **[web: SketchyBar discussion]**.
- **(b) Recipe — unread count without reading message text** (needs Full Disk Access for **Islet**, because widgets are its child processes; skip if you won't grant FDA and rely on U1):

```bash
#!/bin/zsh
# ~/.config/islet/plugins/imessage-unread.1m.sh
db=~/Library/Messages/chat.db
n=$(sqlite3 -readonly "$db" \
  "SELECT COUNT(*) FROM message WHERE is_read=0 AND is_from_me=0 AND item_type=0
     AND date > (strftime('%s','now','-2 days') - 978307200) * 1000000000;" 2>/dev/null) || exit 0
(( n > 0 )) || exit 0
printf '{"id":"imessage","title":"%s unread","icon":"app:com.apple.MobileSMS","trailing":"%s","url":"messages://","priority":"low","source":"com.apple.MobileSMS"}\n' "$n" "$n"
```

- **(c) Islet shows:** mirrored banners with sender (U1, content optional); a low-priority count pill; click opens Messages.

### 4.6 FaceTime (and Phone)

- **(a) Exposes:** FaceTime URL schemes `facetime:`, `facetime-group:`, `facetime-open-link:`, `system-call-controls:` **[VERIFIED local]**; the macOS **Phone** app registers `tel:`, `facetime-audio:`, `phone-facetime-audio:` and friends **[VERIFIED local]**. No `.sdef` for either **[VERIFIED local]**. macOS asks for confirmation before placing a call **[web: Apple URL scheme reference]**. Calls are detected by U2 **[UNVERIFIED: attribution may point at a system daemon rather than FaceTime]**.
- **(b) Recipe — favourite-contact call buttons in the expanded island:**

```bash
source ~/.config/islet/lib.sh
islet POST /v1/activities '{"id":"call-favs","title":"Quick call","icon":"sf:phone.fill","priority":"low","ttl":0,
  "actions":[{"title":"Mum","url":"facetime-audio://+15551234567"},{"title":"Alex","url":"facetime://alex@example.com"}]}'
```

- **(c) Islet shows:** a phone pill; expanded shows two call buttons; during the call U2 shows a green count-up.


---

## 5. Mail, calendar, tasks and notes

### 5.1 Mail

- **(a) Exposes**
  - **Rules that run an AppleScript** (event-driven). `Mail.sdef` defines the handler `perform mail action with messages … for rule` ("Script handler invoked by rules and menus that execute AppleScripts") **[VERIFIED local]**. Scripts must live in `~/Library/Application Scripts/com.apple.mail/` and are chosen in Settings → Rules → "Run AppleScript".
  - AppleScript also has `check for new mail`, `synchronize`, and `unread count` on mailboxes **[VERIFIED local]**.
  - URL schemes `message://<%3CMessage-ID%3E>` (open a specific message), `mailto:` **[VERIFIED local: `message`, `mailto`]**.
  - Dock badge (U5) and banner mirroring (U1) need no setup.
- **(b) Recipe — VIP / keyword mail sneaks with an "Open" button.** Create a rule (for example *From is in VIPs* or *Subject contains "invoice"*) → *Run AppleScript* → `Islet.scpt`:

```applescript
-- ~/Library/Application Scripts/com.apple.mail/Islet.applescript
-- (save as .scpt or keep .applescript; Mail accepts both)
using terms from application "Mail"
  on perform mail action with messages theMessages for rule theRule
    repeat with m in theMessages
      set who to extract name from sender of m
      set subj to subject of m
      set mid to message id of m
      set openURL to "message://%3C" & mid & "%3E"
      do shell script "/opt/homebrew/bin/isletctl set mail-" & (id of m) & ¬
        " --title " & quoted form of who & " --subtitle " & quoted form of subj & ¬
        " --icon app:com.apple.mail --state info --ttl 20 --source com.apple.mail --url " & quoted form of openURL
    end repeat
  end perform mail action with messages
end using terms from
```

- **(c) Islet shows:** compact: Mail icon + sender initials; sneak with sender and subject; click opens the exact message.

### 5.2 Calendar

- **(a) Exposes:** Islet reads calendars through **EventKit** already (built-in, event-driven via `EKEventStoreChanged`). `iCal.sdef` **[VERIFIED local]** adds `event` (summary, start/end date, location, `url`, attendees), `view calendar`, `switch view`, `GetURL`; URL schemes `ical://`, `webcal://` **[VERIFIED local]**. Anything synced into macOS Internet Accounts (iCloud, Google, Exchange) appears through EventKit, including events created in Fantastical or Outlook if they use the same accounts.
- **(b) Recipe — "join" button for meetings Islet doesn't recognise.** The built-in calendar activity links to the event. For a meeting link that lives only in the notes field (Webex, Jitsi, a custom bridge), push an activity with an explicit countdown and a Join action:

```bash
source ~/.config/islet/lib.sh
start=$(date -v+5M +%s)   # or parse from your own source
islet POST /v1/activities "$(jq -nc --argjson s $start '{
  id:"meet-standup", title:"Stand-up", subtitle:"Jitsi · 15 min", icon:"sf:video.fill",
  endsAt:$s, priority:"high", tint:"blue", source:"calendar",
  actions:[{title:"Join", url:"https://meet.jit.si/acme-standup", dismiss:true}]}')"
```

- **(c) Islet shows:** compact: calendar glyph + `5:00` counting down; sneak at T-5 min; expanded: title, location, **Join** button.

### 5.3 Reminders

- **(a) Exposes:** `Reminders.sdef` **[VERIFIED local]**: `reminder` (name, body, `due date`, `allday due date`, `remind me date`, `completed`, `flagged`, `priority`), lists, `show`. URL scheme `x-apple-reminderkit://` **[VERIFIED local]**. EventKit (`EKReminder`) is the fast path for Islet itself; AppleScript over Reminders is slow on large lists. No events for scripts → **poll**.
- **(b) Recipe — "due in the next hour" widget** (only queries if Reminders is running, so it never launches the app):

```bash
#!/bin/zsh
# ~/.config/islet/plugins/reminders-due.5m.sh
pgrep -xq Reminders || exit 0
names=$(osascript <<'EOF'
tell application "Reminders"
  set cutoff to (current date) + 3600
  set r to name of (reminders whose completed is false and due date is not missing value and due date < cutoff)
  set AppleScript's text item delimiters to " · "
  return r as text
end tell
EOF
)
[[ -z $names ]] && exit 0
n=$(( $(grep -o ' · ' <<<"$names" | wc -l) + 1 ))
printf '{"id":"reminders-due","title":"%s due soon","subtitle":"%s","icon":"app:com.apple.reminders","trailing":"%s","tint":"orange","source":"com.apple.reminders"}\n' \
  "$n" "${names//\"/\\\"}" "$n"
```

  From an iPhone or a Mac Shortcut instead: *Find Reminders where Due Date is today and Is Not Completed* → *Count* → *Get Contents of URL* (POST `/v1/activities`).
- **(c) Islet shows:** compact: checklist icon + count; expanded: the titles. No sneak on every poll (same `id`, unchanged fields).

### 5.4 Notes

- **(a) Exposes:** `Notes.sdef` **[VERIFIED local]**: accounts, folders, `note` (name, body, plaintext, creation/modification date, `password protected`), `show`, `open note location`. URL schemes `applenotes:` and `notes:` **[VERIFIED local]**. No change events → poll, and there is little worth showing live.
- **(b) Recipe — quick capture button.** Pin a "capture" activity whose action runs a Shortcut (Shortcuts' own *Create Note* action):

```bash
isletctl set capture --title "Quick note" --icon app:com.apple.Notes --priority low \
  --url "shortcuts://run-shortcut?name=Quick%20Note" --ttl 0
```

- **(c) Islet shows:** a low-priority pill; clicking runs the Shortcut. Low value otherwise; skip unless requested.


### 5.5 Things 3

- **(a) Exposes:** URL scheme (enable in Things → Settings → General → "Enable Things URLs") with commands `add`, `add-project`, `update`, `update-project`, `show`, `search`, `json`, `version`; `things:///add?title=…&when=today|tomorrow|evening|anytime|someday|<date>` plus `deadline`, `list`, `tags`, `checklist-items`, `notes`, `reveal`; `things:///show?id=today|inbox|upcoming|anytime|someday|logbook|deadlines…`; x-callback returns `x-things-ids`; `update` and `json` updates need an `auth-token` **[web: Things URL scheme docs]**. AppleScript: `to dos of list "Today"` with `name`, `id`, `due date`, `activation date`, `status` (open/completed/canceled), `tag names`, `notes` **[web: Things AppleScript guide]**. No events → poll.
- **(b) Recipe — "Today" widget with a quick-add button:**

```bash
#!/bin/zsh
# ~/.config/islet/plugins/things-today.10m.sh
pgrep -qf 'Things3.app' || exit 0              # don't launch Things
out=$(osascript <<'EOF'
tell application id "com.culturedcode.ThingsMac"
  set names to {}
  repeat with t in to dos of list "Today"
    if status of t is open then set end of names to name of t
  end repeat
  set AppleScript's text item delimiters to linefeed
  return ((count of names) as text) & linefeed & (names as text)
end tell
EOF
) || exit 0
n=${out%%$'\n'*}; (( n > 0 )) || exit 0
next=${${out#*$'\n'}%%$'\n'*}
jq -nc --arg n "$n" --arg next "$next" '{id:"things-today", title:"\($n) for Today", subtitle:"Next: \($next)",
  icon:"app:com.culturedcode.ThingsMac", trailing:$n, priority:"low", source:"things",
  url:"things:///show?id=today", actions:[{title:"Add", url:"things:///add?show-quick-entry=true"}]}'
```

  (`show-quick-entry=true` opens Quick Entry instead of adding silently; that parameter and the bundle id `com.culturedcode.ThingsMac` are **[UNVERIFIED]** here, since Things is not installed on this Mac.)
- **(c) Islet shows:** a low-priority checklist pill with the count; expanded shows the next to-do, **Add** opens Quick Entry, click opens Today.

### 5.6 Todoist

- **(a) Exposes:** unified **API v1** at `https://api.todoist.com/api/v1` with `Authorization: Bearer <token>`; today's tasks via `GET /api/v1/tasks/filter?query=today` **[web: Todoist API v1 docs, official Python SDK]**. REST v2 now returns 410 Gone (shutdown date reported as 2026-02-10 **[UNVERIFIED official date]**). Webhooks (`item:added/updated/completed…`, `reminder:fired`) need a public HTTPS URL **and** an OAuth app, so a personal token cannot use them **[web]**. `todoist://` deep links **[UNVERIFIED]**. → Poll.
- **(b) Recipe:**

```bash
#!/bin/zsh
# ~/.config/islet/plugins/todoist.10m.sh   (TODOIST_TOKEN in ~/.config/islet/secrets.env, chmod 600)
source ~/.config/islet/secrets.env
j=$(curl -fsS -m 8 -G https://api.todoist.com/api/v1/tasks/filter \
      --data-urlencode 'query=today | overdue' -H "Authorization: Bearer $TODOIST_TOKEN") || exit 0
jq -c '(if type == "array" then . else .results end) as $t | ($t|length) as $n | select($n > 0) |
  {id:"todoist", title:"\($n) due today", subtitle:("Next: " + ($t | sort_by(-.priority) | .[0].content)),
   icon:"sf:checklist", trailing:"\($n)", tint:"red", priority:"low", source:"todoist",
   url:"https://app.todoist.com/app/today"}' <<<"$j"
```

  (The `results` wrapper is how v1 paginates; the `type` check also accepts a bare array **[UNVERIFIED response shape]**.)
- **(c) Islet shows:** count pill; expanded shows the highest-priority task; click opens Todoist Today.

### 5.7 OmniFocus 4

- **(a) Exposes:** URL scheme `omnifocus:///add?name=&note=&due=&defer=&project=&context=&flag=&estimate=&reveal-new-item=`, `omnifocus:///perspective/<Name>`, `/inbox`, `/flagged`, `/forecast` **[web: inside.omnifocus.com/url-schemes]**. Omni Automation `omnifocus://localhost/omnijs-run?script=<encoded>&arg=<encoded>` (off by default, per-script approval, no return value) **[web: omni-automation.com]**. AppleScript (`default document`, `flattened tasks`, `due date`, `flagged`) **[web; exact `whose` clause UNVERIFIED]**. No events → poll.
- **(b) Recipe:**

```bash
#!/bin/zsh
# ~/.config/islet/plugins/omnifocus-due.10m.sh
pgrep -qx OmniFocus || exit 0
n=$(osascript -e 'tell application "OmniFocus" to tell default document to count (flattened tasks whose completed is false and effectively dropped is false and due date is not missing value and due date < ((current date) + 86400))' 2>/dev/null) || exit 0
(( n > 0 )) || exit 0
printf '{"id":"omnifocus","title":"%s due in 24 h","icon":"sf:checkmark.circle","trailing":"%s","url":"omnifocus:///forecast","priority":"low","source":"omnifocus"}\n' "$n" "$n"
```

- **(c) Islet shows:** count pill; click opens Forecast.

### 5.8 Fantastical

- **(a) Exposes:** URL scheme `x-fantastical://parse?sentence=…&notes=…&add=1&calendarName=…` (also `title`, `location`, `url`, `start`, `end`, `allDay`, `attendees`), `x-fantastical://show/calendar`, `x-fantastical://date/yyyy-MM-dd` **[web: Flexibits integration help]**; AppleScript `parse sentence "…" with add immediately` **[web]**. Events created in Fantastical on accounts that are also in macOS Internet Accounts reach Islet through EventKit (§5.2); Flexibits-only accounts do not **[UNVERIFIED]**.
- **(b) Recipe — natural-language "add event" from anywhere, confirmed in the notch:**

```bash
#!/bin/zsh
# ~/bin/fadd "Lunch with Sam tomorrow 1pm at Blue Bottle"
s=$(jq -rn --arg s "$*" '$s|@uri')
open "x-fantastical://parse?sentence=$s&add=1" && isletctl notify "Added to calendar" --subtitle "$*" --icon sf:calendar.badge.plus --ttl 5
```

- **(c) Islet shows:** a short confirmation sneak; the event itself then appears through the calendar integration.


---

## 6. Developer tools

Every terminal in this section is covered by the **shell hook in §10**; the entries below list what each app adds on top.

### 6.1 Xcode

- **(a) Exposes:** **Behaviors** (Settings → Behaviors) fire on Build starts / succeeds / fails / generates issues, Testing starts / succeeds / fails, Running starts / completes / exits unexpectedly, and more; each can **Run** a script **[web: Apple Xcode help]**. Xcode does not source your shell profile, so use absolute paths **[web: jessesquires.com]**; whether it passes environment variables is **[UNVERIFIED]**. `xcodebuild`/`xcrun` are plain commands (§10 or `isletctl run`). Xcode Cloud webhooks POST on build created/started/completed (`ciBuildRun.executionProgress`, `completionStatus`) but need a public HTTPS endpoint **[web: Apple, polpiella.dev]**. Xcode is not installed on this Mac (CLT only), so nothing here is locally verified.
- **(b) Recipe — build lifecycle in the notch.** Create three executable scripts (`chmod +x`, shebang required) and attach them in Settings → Behaviors → Build Starts / Succeeds / Fails → **Run**:

```bash
#!/bin/zsh
# ~/Library/Developer/Islet/xcode-build.sh  — symlink as xcode-start, xcode-ok, xcode-fail
I=/opt/homebrew/bin/isletctl
case ${0:t} in
  xcode-start) $I set xcode-build --title "Building" --subtitle "Xcode" --icon app:com.apple.dt.Xcode \
                 --progress -1 --state running --sneak false --source com.apple.dt.Xcode ;;
  xcode-ok)    $I set xcode-build --title "Build succeeded" --icon app:com.apple.dt.Xcode \
                 --state success --progress 1 --ttl 6 --source com.apple.dt.Xcode ;;
  xcode-fail)  $I set xcode-build --title "Build failed" --icon app:com.apple.dt.Xcode \
                 --state failure --priority high --ttl 60 --source com.apple.dt.Xcode ;;
esac
```

  Do the same for Testing Succeeds/Fails with an `xcode-test` id. For CLI builds: `isletctl run --title "xcodebuild test" -- xcodebuild test -scheme App -destination 'platform=macOS'`.
- **(c) Islet shows:** a spinner with the Xcode icon while building (no sneak, so it doesn't nag); a quick green tick on success; a sticky red high-priority "Build failed" that beats music.

### 6.2 Visual Studio Code

- **(a) Exposes:** URL scheme `vscode:` **[VERIFIED local, 1.138.0]**, e.g. `vscode://file/<abs path>:<line>:<col>` **[web: VS Code CLI docs]**; `code` CLI inside the bundle (`Contents/Resources/app/bin/code`) **[VERIFIED local]**. **Tasks** (`tasks.json`: `dependsOn`, `dependsOrder`, `isBackground` + background problem matchers, `runOptions.runOn: "folderOpen"`) **[web]**. Extension API events `tasks.onDidEndTaskProcess` (with `exitCode`) and `window.onDidEndTerminalShellExecution` (`exitCode`, `commandLine`; shell-integration API stable since 1.93) **[web]**. The integrated terminal runs your zsh, so §10's hook already works there.
- **(b) Recipe — wrap long tasks so they report to the notch:**

```jsonc
// .vscode/tasks.json
{
  "version": "2.0.0",
  "tasks": [
    { "label": "build", "type": "shell", "group": { "kind": "build", "isDefault": true },
      "command": "isletctl run --title 'build ${workspaceFolderBasename}' -- npm run build",
      "problemMatcher": ["$tsc"] },
    { "label": "test", "type": "shell", "group": "test",
      "command": "isletctl run --title 'tests ${workspaceFolderBasename}' -- npm test" }
  ]
}
```

  `isletctl run` passes output and the exit code through untouched, so problem matchers and `dependsOn` chains keep working. To jump from a failure to code, give the activity `--url "vscode://file/$PWD/src/app.ts:42"`.
- **(c) Islet shows:** `isletctl run`: a terminal-icon spinner titled "build my-app", then "Finished in 0:42" (green, 15 s) or "Failed (exit 1)" (red, high priority, 60 s).

### 6.3 Cursor

- **(a) Exposes:** everything VS Code has (it is a fork; same tasks and terminal), plus **Hooks** (since Cursor 1.7, Oct 2025) in `~/.cursor/hooks.json` or `<project>/.cursor/hooks.json`: `{"version":1,"hooks":{"<event>":[{"command":"…","timeout":30,"matcher":"regex"}]}}` **[web: cursor.com/docs/hooks]**. Events: `sessionStart`, `sessionEnd`, `stop`, `beforeSubmitPrompt`, `preToolUse`, `postToolUse`, `beforeShellExecution`, `afterShellExecution`, `beforeMCPExecution`, `afterMCPExecution`, `beforeReadFile`, `afterFileEdit`, `afterAgentResponse`, `subagentStart`, `subagentStop`, `preCompact`… Input is JSON on stdin (`conversation_id`, `generation_id`, `hook_event_name`, `workspace_roots`, `cursor_version`; `stop` adds `status` = `completed|aborted|error`; `afterFileEdit` adds `file_path`). `before*` hooks can return `{"permission":"allow|deny|ask"}` and exit code 2 blocks, so **only attach Islet to `after*`/`stop`/`sessionEnd` events** and print nothing. Event-driven.
- **(b) Recipe — map Cursor's agent into Islet's generic agent hook** (`POST /v1/hooks/cursor` accepts `{agent, event: start|tool|waiting|done|error|end, session, message, title}`, per `Sources/IsletCore/AgentHooks.swift`):

```bash
#!/bin/zsh
# ~/.cursor/islet-hook.sh <alias>   (chmod +x). Prints nothing, so it never changes Cursor's decisions.
in=$(cat); alias=$1
sess=$(jq -r '.conversation_id // "cursor"' <<<"$in")
proj=$(jq -r '(.workspace_roots[0] // "") | split("/") | last' <<<"$in")
case $alias in
  edit)  ev=tool; msg="Editing $(jq -r '(.file_path // "") | split("/") | last' <<<"$in")" ;;
  shell) ev=tool; msg="Ran $(jq -r '(.command // "a command")[0:40]' <<<"$in")" ;;
  stop)  st=$(jq -r '.status // "completed"' <<<"$in")
         [[ $st == completed ]] && ev=done || ev=error; msg="$st · $proj" ;;
  end)   ev=end; msg="" ;;
esac
jq -nc --arg s "$sess" --arg e "$ev" --arg m "$msg" --arg t "Cursor · $proj" \
  '{agent:"Cursor", title:$t, session:$s, event:$e, message:$m}' | /opt/homebrew/bin/isletctl hook cursor
```

```json
{
  "version": 1,
  "hooks": {
    "afterFileEdit":       [{ "command": "/Users/YOU/.cursor/islet-hook.sh edit" }],
    "afterShellExecution": [{ "command": "/Users/YOU/.cursor/islet-hook.sh shell" }],
    "stop":                [{ "command": "/Users/YOU/.cursor/islet-hook.sh stop" }],
    "sessionEnd":          [{ "command": "/Users/YOU/.cursor/islet-hook.sh end" }]
  }
}
```

  (`command` as an `afterShellExecution` input field is **[UNVERIFIED]**; the fallback text covers it.)
- **(c) Islet shows:** a CPU-icon spinner "Cursor · my-app — Editing App.tsx" while the agent works (no sneak); a green "Done" sneak (30 s) when the turn completes; a red high-priority "Error" otherwise. `isletctl hook` always exits 0 within ~1.5 s, so it can't slow Cursor down.

### 6.4 Terminal (Apple)

- **(a) Exposes:** `Terminal.sdef` **[VERIFIED local]**: `tab` has `busy`, `processes`, `history`, `contents`, `tty`, `custom title`, `selected`; commands `do script`, `get URL`. URL schemes `ssh:`, `telnet:`, `x-man-page:` **[VERIFIED local]**. No events; `busy` can be polled, but the shell hook (§10) is event-driven and better.
- **(b) Recipe:** §10's `longcmd.zsh`. Optional "what is still running" widget, only if Terminal is open:

```bash
#!/bin/zsh
# ~/.config/islet/plugins/terminal-busy.30s.sh
pgrep -xq Terminal || exit 0
busy=$(osascript <<'EOF' 2>/dev/null
tell application "Terminal"
  set out to {}
  repeat with w in windows
    repeat with t in tabs of w
      if busy of t then set end of out to (last item of (processes of t))
    end repeat
  end repeat
  set AppleScript's text item delimiters to ", "
  return out as text
end tell
EOF
)
[[ -z $busy ]] && exit 0
printf '{"id":"terminal-busy","title":"Terminal busy","subtitle":"%s","icon":"app:com.apple.Terminal","priority":"low","source":"terminal"}\n' "$busy"
```

- **(c) Islet shows:** per-command spinners and results from §10.

### 6.5 iTerm2

- **(a) Exposes:** **Python API** (event-driven): `iterm2.PromptMonitor(connection, session_id, modes=[COMMAND_START, COMMAND_END])` yields `(mode, command)` / `(mode, exit_status)`; needs shell integration **[web: iterm2.com/python-api]**. **Triggers** (regex on output → Run Command, Post Notification, Invoke Script Function…, with `\0`–`\9` captures) **[web]**. Escape codes: `OSC 9` notifications, `OSC 133 A/B/C/D`, `OSC 1337 SetUserVar` **[web]**. AppleScript (deprecated): session `is processing`, `is at shell prompt`, `tty` **[web]**. Not installed here.
- **(b) Recipe — "needs input" alert via a Trigger** (catches sudo/ssh/password prompts in long scripts you walked away from). Settings → Profiles → Advanced → Triggers → **+**:
  - Regular expression: `(?i)(password|passphrase)[^:]*:\s*$`
  - Action: **Run Command…**; Parameters: `/opt/homebrew/bin/isletctl set iterm-input --title "iTerm2 needs input" --subtitle "\0" --icon app:com.googlecode.iterm2 --state waiting --priority high --ttl 120`
  - Tick **Instant**.

  Command completion itself comes from §10.
- **(c) Islet shows:** an amber high-priority "waiting" activity that beats music until you answer.

### 6.6 Ghostty

- **(a) Exposes (1.3.0, 2026-03-09):** `notify-on-command-finish = never|unfocused|always`, `notify-on-command-finish-action = bell,notify`, `notify-on-command-finish-after = 5s` (needs OSC 133 shell integration); `desktop-notifications = true` lets programs post via `OSC 9` / `OSC 777` **[web: Ghostty 1.3 release notes and config reference]**. AppleScript (preview in 1.3): windows → tabs → terminals (`id`, `name`, `working directory`), `new window`, `new tab`, `split`, `input text`, `perform action` **[web]**. Not installed here.
- **(b) Recipe:** either §10 (richer: duration, exit code, spinner), or Ghostty's native notifications mirrored by U1:

```ini
# ~/.config/ghostty/config
notify-on-command-finish = unfocused
notify-on-command-finish-action = notify
notify-on-command-finish-after = 10s
```

  Scripts can also ping the notch from inside any Ghostty/iTerm2/Warp session without `isletctl`: `printf '\e]9;Deploy finished\e\\'` (becomes a macOS banner → U1).
- **(c) Islet shows:** §10's activities, or mirrored Ghostty banners.

### 6.7 Warp

- **(a) Exposes:** built-in notifications for long-running commands, password prompts and agent completion (only when Warp is not the active app; Settings → Features → Notifications), and it honours OSC 9/777 **[web: docs.warp.dev]**. URI scheme `warp://action/new_window?path=…`, `warp://action/new_tab?path=…`, `warp://launch/<config>`, `warp://tab_config/<name>` **[web]**. Warp lists some zsh plugins as incompatible; whether plain `preexec`/`precmd` hooks fire reliably is **[UNVERIFIED]**. Not installed here.
- **(b) Recipe:** try §10; if it misbehaves, guard it with `[[ $TERM_PROGRAM == WarpTerminal ]] && return` at the top of `longcmd.zsh` and let U1 mirror Warp's own notifications. Action buttons can open a project in Warp: `--url "warp://action/new_tab?path=$PWD"`.
- **(c) Islet shows:** §10 activities, or mirrored Warp banners.

### 6.8 Coding agents in any editor or terminal (Claude Code, Codex CLI)

Islet already parses these natively (`POST /v1/hooks/claude|codex`, `isletctl hook`). For completeness:

```jsonc
// ~/.claude/settings.json — Claude Code hooks (event JSON arrives on stdin)
{ "hooks": {
    "UserPromptSubmit": [{ "hooks": [{ "type": "command", "command": "/opt/homebrew/bin/isletctl hook claude" }] }],
    "PreToolUse":       [{ "hooks": [{ "type": "command", "command": "/opt/homebrew/bin/isletctl hook claude" }] }],
    "Notification":     [{ "hooks": [{ "type": "command", "command": "/opt/homebrew/bin/isletctl hook claude" }] }],
    "Stop":             [{ "hooks": [{ "type": "command", "command": "/opt/homebrew/bin/isletctl hook claude" }] }],
    "SessionEnd":       [{ "hooks": [{ "type": "command", "command": "/opt/homebrew/bin/isletctl hook claude" }] }] } }
```

```toml
# ~/.codex/config.toml — Codex passes the JSON as the last argv argument, which `isletctl hook` accepts
notify = ["/opt/homebrew/bin/isletctl", "hook", "codex"]
```

Claude Code also supports `"type": "http"` hooks that POST the same JSON to a URL **[web: Claude Code hooks docs]**, but that path cannot add Islet's bearer header unless the hook config supports headers, so the `command` form is the safe default. Islet shows a spinner while the agent works, a high-priority amber "Waiting" when it needs permission, and a green "Done" sneak at the end of a turn.


### 6.9 Docker Desktop

- **(a) Exposes**
  - **`docker events`** (event stream) with `--filter` and `--format json` **[VERIFIED local: Docker 29.0.1 help]**. Each line carries `Type` (`container`, `image`, `network`, `volume`…), `Action` (`start`, `die`, `oom`, `health_status…`, `pull`…), `Actor.ID`, `Actor.Attributes` (`name`, `image`, `exitCode`, compose labels such as `com.docker.compose.project`), `time`, `timeNano`; the legacy `status`/`id`/`from` fields are deprecated **[web: Docker docs]**. The exact health action string (`health_status: healthy`) is **[UNVERIFIED]**; the recipe matches it by prefix.
  - **`docker desktop status --format json`** and `docker desktop start|stop|restart|logs|update` **[VERIFIED local]** (Desktop CLI GA since Docker Desktop 4.39 **[web]**).
  - URL scheme `docker-desktop://` **[VERIFIED local]**.
  - Long builds and `compose up --wait` are plain commands, so `isletctl run` or the shell hook (§10) covers them.
- **(b) Recipe — container crash / health bridge** (LaunchAgent from §0.1, `NAME=docker`):

```bash
#!/bin/zsh
# ~/.config/islet/bridges/docker.sh — streams forever; launchd restarts it if Docker restarts
export PATH=/usr/local/bin:/opt/homebrew/bin:$PATH
until docker info >/dev/null 2>&1; do sleep 15; done
docker events --format '{{json .}}' \
  --filter type=container --filter event=die --filter event=oom --filter event=health_status |
while IFS= read -r ev; do
  name=$(jq -r '.Actor.Attributes.name' <<<"$ev"); id="docker-${name//[^A-Za-z0-9.:-]/-}"
  action=$(jq -r '.Action' <<<"$ev")
  code=$(jq -r '.Actor.Attributes.exitCode // empty' <<<"$ev")
  case $action in
    die)  [[ $code == 0 ]] && continue   # clean exits are not news
          isletctl set "$id" --title "$name exited" --subtitle "exit $code" \
            --icon app:com.docker.docker --state failure --priority high --ttl 120 --source docker ;;
    oom)  isletctl set "$id" --title "$name out of memory" --icon app:com.docker.docker \
            --state failure --priority high --ttl 120 --source docker ;;
    health_status*unhealthy)
          isletctl set "$id" --title "$name unhealthy" --icon app:com.docker.docker \
            --state warning --ttl 60 --source docker ;;
    health_status*healthy) isletctl rm "$id" 2>/dev/null ;;
  esac
done
```

  For builds: `isletctl run --title "docker build api" -- docker build -t api .`
- **(c) Islet shows:** nothing while healthy; a red sneak with the container name on crash/OOM (high priority, stays 2 min); the Docker whale icon via `app:` icons.

### 6.10 GitHub and the GitHub CLI

- **(a) Exposes**
  - `gh run watch <id> [--exit-status] [-i N]` (blocking watcher), `gh run view <id> --json attempt,conclusion,createdAt,databaseId,displayTitle,event,headBranch,headSha,jobs,name,number,startedAt,status,updatedAt,url,workflowDatabaseId,workflowName`, `gh run list --json … --status …`, `gh pr checks --watch [--fail-fast] [-i N]`, `gh search prs --review-requested=@me --state=open --json number,title,repository,url,…` **[VERIFIED local: gh 2.72.0 help]**.
  - Webhooks (`workflow_run`, `check_suite`, `pull_request_review`) need a public URL; the `cli/gh-webhook` extension can forward them to localhost during development **[web, §12]**. Polling with `gh` is simpler and good enough at 10–60 s.
- **(b) Recipe 1 — `ghwatch`: a CI run as a segmented progress bar** (one segment per job):

```bash
#!/bin/zsh
# ~/bin/ghwatch — usage: ghwatch [run-id]   (default: latest run on the current branch)
run=${1:-$(gh run list --branch "$(git branch --show-current)" -L 1 --json databaseId -q '.[0].databaseId')}
[[ -z $run ]] && { echo "no runs"; exit 1 }
id="gh-run-$run"
while :; do
  j=$(gh run view "$run" --json status,conclusion,name,url,headBranch,jobs) || exit 1
  st=$(jq -r .status <<<"$j"); concl=$(jq -r .conclusion <<<"$j")
  name=$(jq -r .name <<<"$j");  url=$(jq -r .url <<<"$j"); br=$(jq -r .headBranch <<<"$j")
  total=$(jq '.jobs|length' <<<"$j"); done_=$(jq '[.jobs[]|select(.status=="completed")]|length' <<<"$j")
  cur=$(jq -r '[.jobs[]|select(.status=="in_progress").name][0] // "queued"' <<<"$j")
  if [[ $st == completed ]]; then
    if [[ $concl == success ]]; then
      isletctl set $id --title "$name passed" --subtitle "$br" --state success --ttl 30 --url "$url" --source gh
    else
      bad=$(jq -r '[.jobs[]|select(.conclusion=="failure").name]|join(", ")' <<<"$j")
      isletctl set $id --title "$name $concl" --subtitle "$bad" --state failure --priority high --ttl 0 --url "$url" --source gh
    fi
    exit 0
  fi
  (( total == 0 )) && total=1
  isletctl set $id --title "$name" --subtitle "$cur · $br" --steps $total --step $done_ \
    --state running --icon sf:gearshape.2.fill --url "$url" --source gh --sneak false
  sleep 10
done
```

  Typical use: `git push && ghwatch`. For PR checks only: `isletctl run --title "PR checks" -- gh pr checks --watch --fail-fast`.
- **(b) Recipe 2 — review requests widget:**

```bash
#!/bin/zsh
# ~/.config/islet/plugins/gh-reviews.5m.sh
j=$(gh search prs --review-requested=@me --state=open --json number,title,repository,url -L 20 2>/dev/null) || exit 0
n=$(jq length <<<"$j"); (( n == 0 )) && exit 0
jq -c --argjson n $n '{id:"gh-reviews", title:"\($n) review\(if $n>1 then "s" else "" end) requested",
  subtitle:(.[0] | "\(.repository.nameWithOwner)#\(.number) \(.title)"), url:.[0].url,
  icon:"sf:arrow.triangle.pull", trailing:"\($n)", priority:"low", source:"gh"}' <<<"$j"
```

- **(c) Islet shows:** Recipe 1: a stepper bar (`3/5`) with the current job name, a green sneak on success or a sticky red high-priority activity on failure that opens the run. Recipe 2: a low-priority pill with the count.

### 6.11 Homebrew

- **(a) Exposes:** `brew outdated --json` (v2 shape: `formulae[]` and `casks[]` with `name`, `installed_versions`, `current_version`) and `--greedy` for auto-updating casks **[VERIFIED local: flags; JSON shape web §12]**. No events; no hook for "upgrade finished" beyond the exit code.
- **(b) Recipe:**

```bash
#!/bin/zsh
# ~/.config/islet/plugins/brew-outdated.6h.sh   (brew is slow; run rarely)
j=$(HOMEBREW_NO_AUTO_UPDATE=1 brew outdated --json=v2 2>/dev/null) || exit 0
n=$(jq '(.formulae|length)+(.casks|length)' <<<"$j"); (( n == 0 )) && exit 0
names=$(jq -r '[.formulae[].name, .casks[].name][:4]|join(", ")' <<<"$j")
printf '{"id":"brew","title":"%s updates","subtitle":"%s","icon":"sf:mug.fill","trailing":"%s","priority":"low","source":"brew"}\n' "$n" "$names" "$n"
```

  And the upgrade itself: `alias bup='isletctl run --title "brew upgrade" -- brew upgrade'`.
- **(c) Islet shows:** a low-priority mug icon with the count; `bup` shows a spinner, then "Finished in 3:12" or a red failure sneak.


---

## 7. Automation hubs (one integration each, reaches hundreds of apps)

These tools matter most: each already talks to many apps, so teaching each one to talk to Islet multiplies coverage. Two directions:

- **Hub → Islet:** open an `islet://` URL (no token needed; local only), run `isletctl`, or `curl` the API.
- **Islet → hub:** an activity's `url` or `actions[].url` can be any scheme, so the notch's buttons can fire `shortcuts://`, `raycast://`, `alfred://`, `hammerspoon://`, `btt://`, `kmtrigger://` URLs.

### 7.1 Shortcuts (Mac)

- **(a) Exposes:** `Shortcuts.sdef` **[VERIFIED local]**: `shortcut` (name, id, folder, `accepts input`, `action count`), command `run`. `/usr/bin/shortcuts run "<name>" [-i path] [-o path] [--output-type UTI]`, `list`, `view`, `sign` **[VERIFIED local: help]**. URL schemes `shortcuts:`, `workflow:` **[VERIFIED local]** (`shortcuts://run-shortcut?name=…&input=text&text=…`). **Automations on the Mac (macOS 26+):** time of day / sunrise / sunset, alarm, email, message, folder and file changes, drive connect, Wi-Fi join/leave, Bluetooth device or display connect, Stage Manager, app opened/closed, Focus on/off **[web: Apple newsroom, MacStories Tahoe review]**; battery/charger triggers on Mac **[UNVERIFIED]**. Event-driven.
- **(b) Recipe — "Focus mirrors into the notch" (Mac automation):** Shortcuts → Automations → New → **Focus** → *Work* → *When Turning On* → action **Open URLs** → `islet://focus?name=Work&state=on`. Duplicate for *When Turning Off* with `state=off`. More Mac automations worth adding:
  - **App opened: Xcode** → *Run Shell Script* `isletctl notify "Xcode" --subtitle "$(git -C ~/src/app log -1 --format=%s)" --ttl 5`.
  - **External display connected** → *Open URLs* `islet://notify?title=Desk%20mode&icon=sf:display&ttl=4` plus your window-layout actions.
  - **Wi-Fi joins "Office"** → *Open URLs* `islet://focus?name=Office&state=on`.
  - **Folder "Scans" gets a file** → *Get Contents of URL* POST `/v1/notify` (headers below) or *Run Shell Script* with `isletctl`.

  *Get Contents of URL* settings for the local API: URL `http://127.0.0.1:47831/v1/activities`, Method **POST**, Headers `Authorization: Bearer <token>`, Request Body **JSON** with the activity fields.
- **(c) Islet shows:** whatever the called surface shows; Focus gives the iPhone-style Focus pill.

### 7.2 Raycast

- **(a) Exposes:** **Script Commands**: any script with `# @raycast.schemaVersion 1`, `# @raycast.title`, `# @raycast.mode` (`silent|compact|fullOutput|inline`; `inline` needs `@raycast.refreshTime`, minimum 10 s), up to three `@raycast.argumentN` JSON specs (`text|password|dropdown`) **[web: raycast/script-commands README]**. Deeplinks `raycast://extensions/<owner>/<ext>/<command>?arguments=<json>&launchType=…` (Raycast asks for confirmation) and `raycast://script-commands/<name>?arguments=…` **[web: Raycast developer docs]**. Raycast Quicklinks can open any URL (so `islet://…` works) **[UNVERIFIED for custom schemes]**. Event-driven (user-invoked).
- **(b) Recipe — notch timer with an argument:**

```bash
#!/bin/zsh
# ~/raycast-scripts/islet-timer.sh
# @raycast.schemaVersion 1
# @raycast.title Notch Timer
# @raycast.mode silent
# @raycast.argument1 { "type": "text", "placeholder": "25m / 90s / 1h" }
# @raycast.argument2 { "type": "text", "placeholder": "label", "optional": true }
/opt/homebrew/bin/isletctl timer "$1" --title "${2:-Timer}" && echo "Timer set"
```

  Also: a Quicklink named "Pin tab" pointing at a script command that runs `~/bin/pin-tab` (§3.1).
- **(c) Islet shows:** orange countdown ring; sneak at zero.

### 7.3 Alfred

- **(a) Exposes:** workflows with **Run Script** and **Open URL** actions; **External Triggers** callable by AppleScript `tell application id "com.runningwithcrayons.Alfred" to run trigger "<trigger>" in workflow "<bundle id>" with argument "<arg>"`, by JXA, and (Alfred 5+) by URL `alfred://runtrigger/<bundle id>/<trigger>/?argument=<arg>` **[web: alfredapp.com help]**.
- **(b) Recipe:** Keyword `tt` (argument required) → **Open URL** `islet://timer?minutes={query}&title=Timer`. Reverse direction: an Islet action button that runs an Alfred workflow, e.g. `{"title":"Snooze","url":"alfred://runtrigger/com.me.snooze/snooze/?argument=10"}`.
- **(c) Islet shows:** countdown; the button runs the workflow.

### 7.4 Hammerspoon

- **(a) Exposes (all event-driven):** `hs.distributednotifications.new(fn, name)` (callback `(name, object, userInfo)`), `hs.application.watcher` (`launched`, `terminated`, `activated`…), `hs.caffeinate.watcher` (`screensDidLock`, `screensDidUnlock`, `systemWillSleep`, `systemDidWake`…), `hs.wifi.watcher` (`SSIDChange`, `linkChange`…), `hs.usb.watcher` (`eventType`, `productName`, `vendorName`), `hs.battery.watcher` (no args; re-query), `hs.urlevent.bind(name, fn)` for `hammerspoon://name?k=v`, `hs.http.doAsyncRequest(url, method, body, headers, cb)` **[web: hammerspoon.org docs]**. Not installed here.
- **(b) Recipe — five watchers in one file** (uses `islet.lua` from §0.2):

```lua
-- ~/.hammerspoon/init.lua
islet = require("islet")

-- USB: show what was plugged in (drives, audio interfaces, keyboards)
usbWatcher = hs.usb.watcher.new(function(e)
  if e.eventType == "added" then
    islet.notify(e.productName or "USB device", e.vendorName, "sf:cable.connector")
  end
end):start()

-- Wi-Fi: announce network changes and warn on open networks
wifiWatcher = hs.wifi.watcher.new(function()
  local ssid = hs.wifi.currentNetwork()
  if ssid then islet.notify("Wi-Fi: " .. ssid, nil, "sf:wifi") else islet.notify("Wi-Fi disconnected", nil, "sf:wifi.slash") end
end):watchingFor({"SSIDChange"}):start()

-- Screen lock: pause media, and remember how long you were away
local lockedAt
cafWatcher = hs.caffeinate.watcher.new(function(ev)
  if ev == hs.caffeinate.watcher.screensDidLock then
    lockedAt = os.time(); islet.call("POST", "/v1/media/command", {command = "pause"})
  elseif ev == hs.caffeinate.watcher.screensDidUnlock and lockedAt then
    local m = math.floor((os.time() - lockedAt) / 60)
    if m >= 5 then islet.notify("Welcome back", ("Away %d min"):format(m), "sf:hand.wave.fill") end
  end
end):start()

-- App watcher: clear stale activities when their app quits
appWatcher = hs.application.watcher.new(function(name, ev, app)
  if ev == hs.application.watcher.terminated and app and app:bundleID() == "us.zoom.xos" then islet.rm("zoom-mic") end
end):start()

-- URL entry point so notch buttons can call Lua, e.g. an action {"title":"Lock","url":"hammerspoon://islet-lock"}
hs.urlevent.bind("islet-lock", function() hs.caffeinate.lockScreen() end)
```

  Plus the Music/Spotify listeners (§2.1–2.2) and the Zoom mic indicator (§4.1).
- **(c) Islet shows:** short sneaks for USB/Wi-Fi/welcome-back; buttons can call back into Hammerspoon.

### 7.5 BetterTouchTool

- **(a) Exposes:** Named Triggers fired by AppleScript `tell application "BetterTouchTool" to trigger_named "Name"`, by URL `btt://trigger_named/?trigger_name=Name&var=value` (also `btt://trigger_named_async_without_response/…`, optional `shared_secret`), or by its optional local webserver (off by default, random port) **[web: docs.folivora.ai]**. Actions include **Open URL** and **Execute Shell Script / Task**; **no native HTTP-request action** (the developer recommends curl) **[web: folivora community]**.
- **(b) Recipe:** trackpad gesture or key → **Open URL** `islet://toggle` (show/hide the expanded island) or `islet://media/next`; **Execute Shell Script / Task** `/opt/homebrew/bin/isletctl timer 5m --title Tea`. Reverse direction: action button `{"title":"Tile","url":"btt://trigger_named/?trigger_name=TileLeft"}`.
- **(c) Islet shows:** the called surface; the island itself opens/closes on `islet://toggle`.

### 7.6 Keyboard Maestro

- **(a) Exposes:** `kmtrigger://macro=<name or UUID>&value=<v>` (value → `%TriggerValue%`), AppleScript `tell application "Keyboard Maestro Engine" to do script "<macro>" with parameter "x"`, v11 CLI `…/keyboardmaestro -p <value> "<macro>"` **[web: KM wiki]**. **Execute a Shell Script** runs with `PATH=/usr/bin:/bin:/usr/sbin:/sbin` and variables as `$KMVAR_Name` **[web]**. Triggers worth pairing with Islet: USB Device, Wireless Network, Application, Folder, Clipboard Changed, Periodic, Wake, Unlock, Power Status Changed, Display Layout Changed **[web]**. **Get a URL** has no header options, so use curl or `isletctl` **[web]**.
- **(b) Recipe — "unplugged during a long render":** trigger **Power Status Changed** (to battery) → action **Execute a Shell Script**:

```bash
/opt/homebrew/bin/isletctl notify "On battery" --subtitle "Render still running" --icon sf:bolt.slash.fill --tint orange --ttl 8
```

  Reverse direction: an Islet action `{"title":"Paste snippet","url":"kmtrigger://macro=Paste%20Signature"}`.
- **(c) Islet shows:** an orange sneak; buttons run macros.

### 7.7 Stream Deck

- **(a) Exposes:** built-in **Website** action (has a "GET request in background" option; GET only), **System → Open** (app/file), **Multi Action** **[web; Elgato help pages returned 403, so partly UNVERIFIED]**. Third-party plugins that send POST with headers: *API Request* (method, headers, body, polling, icon from response) and *Web Requests* (HTTP + WebSocket) **[web: GitHub]**. SDK (Node): `npm i -g @elgato/cli && streamdeck create` **[web: docs.elgato.com]**.
- **(b) Recipe:** with the *API Request* plugin: URL `http://127.0.0.1:47831/v1/timer`, Method POST, Header `Authorization: Bearer <token>`, Body `{"seconds":1500,"title":"Pomodoro"}`. A key that shows the notch's state uses the plugin's polling on `GET /v1/state`. Without plugins: **Website** action pointed at `islet://timer?minutes=25&title=Pomodoro` **[UNVERIFIED that the Website action hands custom schemes to LaunchServices]**.
- **(c) Islet shows:** the countdown; Stream Deck key can mirror `GET /v1/state`.

### 7.8 Home Assistant

- **(a) Exposes:** `rest_command` (url, method, headers, payload, content_type, timeout, verify_ssl; templated) called as `action: rest_command.<name>` with `data:` variables; REST API `GET /api/states/<entity_id>` with a long-lived token; WebSocket `subscribe_events`; webhook triggers `POST /api/webhook/<id>` (local-only by default) **[web: home-assistant.io]**. HA → Islet goes over Islet's **LAN bridge** (port 47832, token required, 30 requests / 10 s per client).
- **(b) Recipe — appliance finished / countdown / dismiss:**

```yaml
# configuration.yaml   (secrets.yaml:  islet_bearer: "Bearer <output of `isletctl token`>")
rest_command:
  islet_activity:
    url: "http://192.168.1.20:47832/v1/activities"     # the Mac's LAN IP (or mymac.local if mDNS works in HA)
    method: post
    headers:
      authorization: !secret islet_bearer
    content_type: "application/json"
    timeout: 5
    payload: >-
      {{ dict(id=id, title=title, subtitle=subtitle | default(''), icon=icon | default('sf:house.fill'),
              state=state | default('info'), priority=priority | default('normal'),
              ttl=ttl | default(0), source='home-assistant',
              endsAt=(ends_at if ends_at is defined else none)) | tojson }}
  islet_dismiss:
    url: "http://192.168.1.20:47832/v1/activities/{{ id }}"
    method: delete
    headers:
      authorization: !secret islet_bearer

automation:
  - alias: "Washer done → notch"
    triggers:
      - trigger: numeric_state
        entity_id: sensor.washer_power
        below: 3
        for: "00:03:00"
    actions:
      - action: rest_command.islet_activity
        data: { id: washer, title: "Laundry done", icon: "sf:washer.fill", state: success, priority: high, ttl: 900 }

  - alias: "Dishwasher countdown → notch"
    triggers:
      - trigger: state
        entity_id: sensor.dishwasher_program_finish      # a timestamp sensor
    conditions: "{{ trigger.to_state.state not in ['unknown', 'unavailable'] }}"
    actions:
      - action: rest_command.islet_activity
        data:
          id: dishwasher
          title: Dishwasher
          icon: "sf:dishwasher.fill"
          state: running
          ends_at: "{{ trigger.to_state.state }}"
```

  Reverse direction (Islet polls HA, no LAN bridge needed):

```bash
#!/bin/zsh
# ~/.config/islet/plugins/ha-door.1m.sh   (HA_URL, HA_TOKEN in ~/.config/islet/secrets.env)
source ~/.config/islet/secrets.env
s=$(curl -fsS -m 5 "$HA_URL/api/states/binary_sensor.garage_door" -H "Authorization: Bearer $HA_TOKEN" | jq -r .state) || exit 0
[[ $s == on ]] && echo '{"id":"garage","title":"Garage open","icon":"sf:door.garage.open","state":"warning","priority":"high","source":"home-assistant"}'
```

- **(c) Islet shows:** "Laundry done" as a high-priority green sneak that stays 15 min; the dishwasher as a live countdown ring (Islet animates `endsAt`, HA posts once); an amber "Garage open" pill while the door is open.


---

## 8. Work apps and media production

Secrets for the recipes below live in one file that widgets `source`: `~/.config/islet/secrets.env` (`chmod 600`), for example `TODOIST_TOKEN=…`, `NOTION_TOKEN=…`, `LINEAR_API_KEY=…`, `FIGMA_TOKEN=…`. Widgets run as children of Islet and inherit nothing from your shell.

### 8.1 1Password

- **(a) Exposes:** CLI `op` (with desktop-app integration each command is authorised by Touch ID); `op whoami` errors when no account is authenticated, but with app integration it can wrongly report "not signed in", so `op vault list` is the reliable probe (and may prompt) **[web: 1password.dev, op-js #227]**. Undocumented `onepassword://search/<q>` links **[web, unofficial]**. **No event API.** Banners (for example Watchtower alerts, SSH-agent approvals) are mirrored by U1.
- **(b) Recipe:** deliberately minimal. **Never** put item names, TOTP codes or passwords in the notch (screen shares). Two safe uses:
  - Hide 1Password's own banners from the mirror so nothing sensitive is echoed: add `"mutedSources": ["com.1password.1password"]` to `config.json` **[UNVERIFIED bundle id]**.
  - Wrap secret-injection commands so you see that they finished, not what they did: `isletctl run --title "op inject .env" -- op inject -i .env.tpl -o .env`.
- **(c) Islet shows:** only the `isletctl run` spinner/result.

### 8.2 Obsidian

- **(a) Exposes:** `obsidian://` URI actions `open` (vault, file, path), `new` (name, content, append, silent…), `search`, `daily`, `unique`, `choose-vault` **[web: obsidian.md/help/uri]**. Community plugins: **Local REST API** (HTTPS on 27124, optional HTTP 27123, bearer API key; `POST /events/<emitter>/<event>/` then an SSE stream = event-driven) **[web: GitHub]**; **Shell commands** (events: Obsidian starts, every n seconds, file created, file content modified with cooldown) **[web]**; **Advanced URI** (`obsidian://adv-uri?…&commandid=…`) **[web]**. Plain Markdown files, so grep works without any plugin.
- **(b) Recipe — today's checklist as a stepper** (no plugin needed):

```bash
#!/bin/zsh
# ~/.config/islet/plugins/obsidian-today.5m.sh
VAULT=~/Notes; rel="Daily/$(date +%F)"; note="$VAULT/$rel.md"
[[ -f $note ]] || exit 0
open_=$(grep -c '^[[:space:]]*- \[ \]' "$note"); done_=$(grep -ci '^[[:space:]]*- \[x\]' "$note")
total=$(( open_ + done_ )); (( total > 0 )) || exit 0
next=$(grep -m1 '^[[:space:]]*- \[ \]' "$note" | sed 's/^[[:space:]]*- \[ \] //')
jq -nc --arg v "${VAULT:t}" --arg f "$rel" --arg next "$next" --argjson o $open_ --argjson d $done_ --argjson t $total \
  '{id:"obsidian-today", title:"Today \($d)/\($t)", subtitle:(if $o > 0 then "Next: \($next)" else "All done" end),
    steps:$t, step:$d, icon:"sf:checklist", priority:"low", source:"obsidian",
    url:"obsidian://open?vault=\($v|@uri)&file=\($f|@uri)"}'
```

  For instant updates instead of 5-minute polling, add a *Shell commands* entry on "File content modified" (cooldown 5 s) that runs `touch ~/.config/islet/plugins/obsidian-today.5m.sh` **[UNVERIFIED that Islet re-runs a widget when its file changes]**, or have it call `isletctl set obsidian-today …` directly.
- **(c) Islet shows:** a segmented bar (`3/7`) with the next task; click opens today's note.

### 8.3 Notion

- **(a) Exposes:** REST API with a required `Notion-Version` header (latest `2026-03-11`); since `2025-09-03`, queries go to `POST /v1/data_sources/{id}/query` (get the id from `GET /v1/databases/{id}` → `data_sources[]`) **[web: developers.notion.com]**. Webhooks (`page.*`, `data_source.*`, `comment.*`; aggregated events arrive within about a minute; signed with `X-Notion-Signature`) need a public HTTPS endpoint **[web]**. Deep links: replace `https://` with `notion://` **[web]**. → Poll from a widget.
- **(b) Recipe — tasks due today from a Notion database** (property names `Due`, `Status`, `Name` are examples; match yours):

```bash
#!/bin/zsh
# ~/.config/islet/plugins/notion-due.15m.sh   (NOTION_TOKEN, NOTION_DS in secrets.env)
source ~/.config/islet/secrets.env
body=$(jq -nc --arg d "$(date +%F)" '{page_size:10, filter:{and:[
  {property:"Due", date:{on_or_before:$d}}, {property:"Status", status:{does_not_equal:"Done"}}]}}')
j=$(curl -fsS -m 8 -X POST "https://api.notion.com/v1/data_sources/$NOTION_DS/query" \
  -H "Authorization: Bearer $NOTION_TOKEN" -H "Notion-Version: 2025-09-03" \
  -H 'Content-Type: application/json' -d "$body") || exit 0
jq -c '.results as $r | select(($r|length) > 0) |
  {id:"notion-due", title:"\($r|length) due in Notion", trailing:"\($r|length)", icon:"sf:doc.text",
   subtitle:($r[0].properties.Name.title[0].plain_text // "Untitled"), priority:"low", source:"notion",
   url:($r[0].url | sub("^https://"; "notion://"))}' <<<"$j"
```

- **(c) Islet shows:** a count pill; expanded shows the first task; click opens it in the Notion app.

### 8.4 Linear

- **(a) Exposes:** GraphQL at `https://api.linear.app/graphql`; a personal key goes in `Authorization: <key>` (no "Bearer") **[web: linear.app/developers]**. Webhooks (Issues, Comments, Projects, Cycles…; `Linear-Signature` HMAC; public HTTPS only, 5 s timeout) **[web]**. Desktop deep links `linear://…` **[web]**. → Poll.
- **(b) Recipe — "what am I working on":**

```bash
#!/bin/zsh
# ~/.config/islet/plugins/linear.5m.sh   (LINEAR_API_KEY in secrets.env)
source ~/.config/islet/secrets.env
q='{"query":"{ viewer { assignedIssues(first: 10, filter: {state: {type: {eq: \"started\"}}}) { nodes { identifier title url } } } }"}'
j=$(curl -fsS -m 8 https://api.linear.app/graphql -H "Authorization: $LINEAR_API_KEY" \
      -H 'Content-Type: application/json' -d "$q") || exit 0
jq -c '.data.viewer.assignedIssues.nodes as $n | select(($n|length) > 0) |
  {id:"linear", title:"\($n[0].identifier) · \($n[0].title)", trailing:"\($n|length)", icon:"sf:circle.lefthalf.filled",
   subtitle:(if ($n|length) > 1 then "+\(($n|length) - 1) more in progress" else "In progress" end),
   url:$n[0].url, priority:"low", source:"linear"}' <<<"$j"
```

  (Field names checked against Linear's filtering docs only loosely **[UNVERIFIED query shape]**.)
- **(c) Islet shows:** a low-priority pill "ENG-123 · Fix login"; click opens the issue.

### 8.5 Figma

- **(a) Exposes:** URL scheme `figma:` **[VERIFIED local, Figma 126.8]** (exact path format **[UNVERIFIED]**). REST `GET /v1/files/:key/comments` with `X-Figma-Token` (scope `file_comments:read`) **[web: developers.figma.com]**. Webhooks V2 (`FILE_UPDATE` after ~30 min of inactivity, `FILE_VERSION_UPDATE`, `FILE_COMMENT`, `LIBRARY_PUBLISH`, `DEV_MODE_STATUS_UPDATE`) need a public endpoint **[web]**. Comment banners from the desktop app are mirrored by U1.
- **(b) Recipe — new comments on a file you care about:**

```bash
#!/bin/zsh
# ~/.config/islet/plugins/figma-comments.5m.sh   (FIGMA_TOKEN, FIGMA_FILE in secrets.env). Prints nothing.
source ~/.config/islet/secrets.env
st=~/.config/islet/state/figma-$FIGMA_FILE; mkdir -p ${st:h}
last=$(cat $st 2>/dev/null || echo 1970)
j=$(curl -fsS -m 8 "https://api.figma.com/v1/files/$FIGMA_FILE/comments" -H "X-Figma-Token: $FIGMA_TOKEN") || exit 0
new=$(jq -c --arg last "$last" '[.comments[] | select(.created_at > $last and .resolved_at == null)] | sort_by(.created_at)' <<<"$j")
n=$(jq length <<<"$new"); (( n > 0 )) || exit 0
jq -r '.[-1].created_at' <<<"$new" > $st
jq -r '.[-1] | "\(.user.handle)\n\(.message[0:90])"' <<<"$new" | { read -r who; read -r msg
  isletctl set figma-comments --title "$n new comment$([[ $n -gt 1 ]] && echo s) · $who" --subtitle "$msg" \
    --icon app:com.figma.Desktop --ttl 900 --source figma --url "https://www.figma.com/file/$FIGMA_FILE"; }
```

- **(c) Islet shows:** a sneak with the commenter and text; the pill stays 15 min.

### 8.6 Final Cut Pro and Compressor

- **(a) Exposes:** Compressor CLI `/Applications/Compressor.app/Contents/MacOS/Compressor -batchname <n> -jobpath <src> -settingpath <.cmprstng> -locationpath <out>` (+ `-priority`, `-instances`, `-resetBackgroundProcessing`) **[web: Apple Compressor guide]**. No documented progress or completion hook (`-monitor` **[UNVERIFIED]**). Final Cut Pro share/export completion is a macOS notification (U1) **[UNVERIFIED]**; no API. Neither is installed here. (Adobe Premiere Pro 2026 and Media Encoder 2026 are installed on this Mac; they have the same "banner only" story plus Media Encoder watch folders.)
- **(b) Recipe — submit, then watch the output file until it stops growing:**

```bash
#!/bin/zsh
# ~/bin/cmpr <source.mov> <setting.cmprstng> <outdir>
src=$1 setting=$2 out=$3; id="cmpr-$$"
/Applications/Compressor.app/Contents/MacOS/Compressor -batchname "${src:t}" \
  -jobpath "$src" -settingpath "$setting" -locationpath "$out/" || exit 1
isletctl set $id --title "Compressor: ${src:t}" --subtitle "Queued" --icon sf:film --progress -1 --state running
sleep 20; f=$(ls -t "$out" | head -1); last=-1
while sleep 10; do
  s=$(stat -f %z "$out/$f" 2>/dev/null || echo 0)
  [[ $s == $last && $s != 0 ]] && break
  last=$s; isletctl set $id --subtitle "$(( s / 1048576 )) MB written" >/dev/null
done
isletctl set $id --title "Exported ${f}" --subtitle "Compressor" --state success --ttl 30 --url "file://${out// /%20}/${f// /%20}"
```

- **(c) Islet shows:** an indeterminate spinner with "MB written", then a green sneak that opens the file. For FCP shares, U1 mirrors the completion banner.

### 8.7 HandBrake

- **(a) Exposes:** `HandBrakeCLI` prints progress as `Encoding: task N of M, P.PP % (F fps, avg F fps, ETA HHhMMmSSs)`, or with `--json` as `Progress: {…}` blocks (`State`: `WORKING`, `MUXING`, `WORKDONE`…; `Working`: `Progress`, `ETASeconds`, `Pass`, `PassCount`) **[web: HandBrake source]**. Mac GUI: queue "when done" action and notification prefs (`HBQueueDoneAction`, `HBQueueNotificationWhenDone`…), plus **Send file to** an app (`HBSendToApp`) **[web: HBPreferencesKeys.h]**. GUI banners → U1.
- **(b) Recipe — live progress from the CLI** (the regex was tested against sample lines):

```bash
#!/bin/zsh
# ~/bin/hb <in> <out> [preset]
in=$1 out=$2 preset=${3:-"Fast 1080p30"}; id="hb-$$"; last=-1
isletctl set $id --title "Encoding ${in:t}" --subtitle "$preset" --icon sf:film.stack --progress 0 --state running --source handbrake
HandBrakeCLI -i "$in" -o "$out" --preset "$preset" 2>/dev/null | tr -u '\r' '\n' | while IFS= read -r line; do
  [[ $line =~ "Encoding: task ([0-9]+) of ([0-9]+), ([0-9.]+) %( .*ETA ([0-9hms]+))?" ]] || continue
  p=${match[3]%.*}; (( p == last )) && continue; last=$p
  isletctl set $id --progress $(printf '%.3f' $(( match[3] / 100.0 ))) --trailing "$p%" \
    --subtitle "pass ${match[1]}/${match[2]}${match[5]:+ · ETA ${match[5]}}" >/dev/null
done
rc=${pipestatus[1]}
if (( rc == 0 )); then isletctl set $id --title "Encoded ${out:t}" --state success --progress 1 --ttl 60 --url "file://${${out:A}// /%20}"
else isletctl set $id --title "HandBrake failed" --subtitle "exit $rc" --state failure --priority high; fi
```

- **(c) Islet shows:** ring progress with `45%` in the right wing and ETA in the expanded view; green sneak at the end.

### 8.8 Transmission and qBittorrent

- **(a) Exposes**
  - **Transmission:** "done" script with env vars `TR_TORRENT_NAME`, `TR_TORRENT_DIR`, `TR_TORRENT_ID`, `TR_TORRENT_HASH`, `TR_TORRENT_LABELS`… (event-driven); `settings.json` keys `script-torrent-done-enabled/-filename` (snake_case `script_torrent_done_*` since 4.1; the Mac app stores them as `DoneScriptEnabled`/`DoneScriptPath` defaults and does honour them); RPC `POST :9091/transmission/rpc` with the `X-Transmission-Session-Id` 409 handshake; legacy `torrent-get` fields `percentDone`, `rateDownload`, `eta`, `status` (4 = downloading) still work in 4.x **[web: Transmission docs and source]**. On the Mac app, RPC requires enabling remote access in Settings **[UNVERIFIED]**.
  - **qBittorrent:** "Run external program" on torrent added/finished with `%N` name, `%F` content path, `%D` save path, `%I` v1 hash, `%Z` size… (quote them); WebUI API v2 `POST /api/v2/auth/login` (cookie `SID`) then `/api/v2/torrents/info?filter=downloading` (`progress` 0–1, `dlspeed`, `eta`) **[web: qBittorrent source and wiki]**.
- **(b) Recipes**

```sh
#!/bin/sh
# ~/.config/islet/torrent-done.sh — Transmission: Settings → Transfers → "Call script when download completes"
url="file://$(printf %s "$TR_TORRENT_DIR/$TR_TORRENT_NAME" | sed 's/ /%20/g')"
/opt/homebrew/bin/isletctl set "tr-$TR_TORRENT_ID" --title "$TR_TORRENT_NAME" --subtitle "Download complete" \
  --icon sf:arrow.down.circle.fill --state success --ttl 120 --url "$url" --source transmission
```

  qBittorrent → Settings → Downloads → "Run external program on torrent finished":
  `/opt/homebrew/bin/isletctl set qb-%I --title "%N" --subtitle "Download complete" --icon sf:arrow.down.circle.fill --state success --ttl 120 --source qbittorrent`

  Live progress for Transmission (poll; the session-id parsing and summary were tested against sample data):

```bash
#!/bin/zsh
# ~/.config/islet/plugins/transmission.10s.sh
RPC=http://127.0.0.1:9091/transmission/rpc
sid=$(curl -s -m 2 -o /dev/null -D - $RPC | sed -n 's/^X-Transmission-Session-Id: *\([^[:space:]]*\).*/\1/pI')
[[ -n $sid ]] || exit 0
j=$(curl -fsS -m 3 $RPC -H "X-Transmission-Session-Id: $sid" \
     -d '{"method":"torrent-get","arguments":{"fields":["name","percentDone","rateDownload","eta","status"]}}') || exit 0
jq -c '[.arguments.torrents[] | select(.status == 4)] as $d | select(($d|length) > 0) |
  {id:"transmission", title:(if ($d|length) == 1 then $d[0].name else "\($d|length) torrents" end),
   subtitle:"\((($d|map(.rateDownload)|add)/104857.6|floor)/10) MB/s", progress:($d|map(.percentDone)|add/length),
   state:"running", icon:"sf:arrow.down.circle", priority:"low", source:"transmission", sneak:false}' <<<"$j"
```

- **(c) Islet shows:** a low-priority ring with speed while downloading; a green sneak per finished torrent; click opens it in Finder. (If the client saves to `~/Downloads`, U4 may show partial files too; mute one of them.)

### 8.9 OBS Studio

- **(a) Exposes:** **obs-websocket v5**, bundled (`obs-websocket.plugin` inside OBS.app) with config `server_port: 4455`, `auth_required: true`, and `server_enabled: false` by default **[VERIFIED local, OBS 32.1.2 config keys]**; enable in Tools → WebSocket Server Settings. Events `RecordStateChanged {outputActive, outputState, outputPath}`, `StreamStateChanged`, `CurrentProgramSceneChanged`; `outputState` ∈ `OBS_WEBSOCKET_OUTPUT_STARTING|STARTED|STOPPING|STOPPED|PAUSED|RESUMED|RECONNECTING|RECONNECTED` **[web: obs-websocket protocol.md]**. Python client `obsws-python` (`EventClient`, handlers named `on_<snake_case_event>`) **[web]**. No URL scheme **[VERIFIED local]**. Event-driven.
- **(b) Recipe — REC/LIVE indicator with a running clock** (LaunchAgent from §0.1 running `python3 ~/.config/islet/bridges/obs.py`; `pip3 install obsws-python`; put the WebSocket password in `OBS_WS_PASSWORD`):

```python
#!/usr/bin/env python3
# ~/.config/islet/bridges/obs.py
import json, os, sys, time, urllib.request
import obsws_python as obs

API = json.load(open(os.path.expanduser("~/Library/Application Support/Islet/api.json")))
SRC = "com.obsproject.obs-studio"

def islet(method, path, body=None):
    req = urllib.request.Request(f"http://127.0.0.1:{API['port']}{path}", method=method,
        data=None if body is None else json.dumps(body).encode(),
        headers={"Authorization": f"Bearer {API['token']}", "Content-Type": "application/json"})
    try: urllib.request.urlopen(req, timeout=2)
    except Exception: pass

def on_record_state_changed(d):
    s = d.output_state.removeprefix("OBS_WEBSOCKET_OUTPUT_")
    if s == "STARTED":
        islet("POST", "/v1/activities", {"id": "obs-rec", "title": "REC", "icon": "sf:record.circle.fill",
              "tint": "red", "startedAt": time.time(), "priority": "high", "source": SRC})
    elif s in ("PAUSED", "RESUMED"):
        islet("PATCH", "/v1/activities/obs-rec", {"title": "REC paused" if s == "PAUSED" else "REC",
              "tint": "orange" if s == "PAUSED" else "red"})
    elif s == "STOPPED":
        islet("DELETE", "/v1/activities/obs-rec")
        path = d.output_path or ""
        islet("POST", "/v1/activities", {"id": "obs-saved", "title": "Recording saved",
              "subtitle": os.path.basename(path), "state": "success", "ttl": 20, "source": SRC,
              "url": "file://" + urllib.request.pathname2url(path)})

def on_stream_state_changed(d):
    s = d.output_state.removeprefix("OBS_WEBSOCKET_OUTPUT_")
    if s == "STARTED":
        islet("POST", "/v1/activities", {"id": "obs-live", "title": "LIVE", "icon": "sf:dot.radiowaves.left.and.right",
              "tint": "red", "startedAt": time.time(), "priority": "critical", "source": SRC})
    elif s == "RECONNECTING":
        islet("PATCH", "/v1/activities/obs-live", {"title": "Reconnecting…", "state": "warning"})
    elif s == "RECONNECTED":
        islet("PATCH", "/v1/activities/obs-live", {"title": "LIVE", "state": "running"})
    elif s == "STOPPED":
        islet("DELETE", "/v1/activities/obs-live")

try:
    cl = obs.EventClient(host="localhost", port=4455, password=os.environ.get("OBS_WS_PASSWORD", ""))
except Exception:
    sys.exit(1)            # OBS not running: launchd retries after ThrottleInterval
cl.callback.register([on_record_state_changed, on_stream_state_changed])
while getattr(getattr(cl, "base_client", None), "ws", None) is None or cl.base_client.ws.connected:
    time.sleep(5)          # exit when OBS quits so launchd reconnects later
sys.exit(1)
```

  (`base_client.ws.connected` is an obsws-python internal **[UNVERIFIED]**; without it the script simply keeps running until restarted.)
- **(c) Islet shows:** a red **REC 12:34** count-up (high priority, beats music) or a **LIVE** pill marked `critical` so it stays visible over fullscreen; a green "Recording saved" sneak that opens the file.


---

## 9. System, files and network

### 9.1 Finder

- **(a) Exposes**
  - **Folder Actions** (event): the handlers `adding folder items to` / `removing folder items from` are defined in StandardAdditions **[VERIFIED local]**, and System Events has `do folder action` **[VERIFIED local]**. Attach scripts with *Folder Actions Setup* (right-click a folder → Services → Folder Actions Setup…). Scripts live in `~/Library/Scripts/Folder Action Scripts/`.
  - `Finder.sdef` **[VERIFIED local]**: `reveal`, `select`, `eject`, `empty`, `update`, selection, windows.
  - Copy/AirDrop progress: Finder and browsers publish `NSProgress` for file operations; Islet's downloads watcher already subscribes on `~/Downloads` (U4). Subscribing on other folders (for example an external drive during a big copy) is a small extension of the same code **[UNVERIFIED that Finder copies publish per-file progress]**.
- **(b) Recipe — "new file landed" sneak for any folder** (screenshots, scans, an export folder):

```applescript
-- ~/Library/Scripts/Folder Action Scripts/Islet - New file.applescript
on adding folder items to thisFolder after receiving addedItems
  do shell script "$HOME/.config/islet/new-file.sh " & quoted form of (POSIX path of thisFolder) & " " & ¬
    quoted form of (POSIX path of (item 1 of addedItems)) & " " & (count of addedItems)
end adding folder items to
```

```bash
#!/bin/zsh
# ~/.config/islet/new-file.sh <folder> <first file> <count>   (chmod +x)
dir=${1%/} file=${2%/} n=${3:-1}
name=${dir:t}; id="folder-${name//[^A-Za-z0-9.:-]/-}"     # ids allow [A-Za-z0-9._:-]
sub=${file:t}; (( n > 1 )) && sub+=" + $(( n - 1 )) more"
url="file://${${${file//\%/%25}// /%20}//\#/%23}"
/opt/homebrew/bin/isletctl set "$id" --title "New in $name" --subtitle "$sub" \
  --icon sf:folder.fill.badge.plus --ttl 12 --source com.apple.finder --url "$url"
```
- **(c) Islet shows:** a folder icon sneak; clicking opens the new file. For drag-and-drop, Islet's own shelf already covers "drop here, AirDrop from here".

### 9.2 Time Machine

- **(a) Exposes:** `tmutil status` (poll) **[VERIFIED local]**. The first line is a header; the rest is an old-style plist that `plutil -convert json` reads **[VERIFIED local]** (idle: `{"Percent":"-1","ClientID":"com.apple.backupd","Running":"0"}`). While running it adds `BackupPhase` (`FindingBackupVol`, `MountingBackupVol`, `PreparingSourceVolumes`, `FindingChanges`, `SizingChanges`, `Copying`, `ThinningPreBackup`, `ThinningPostBackup`, `DeletingOldBackups`, `LazyThinning`, `HealthCheck*`…), `Percent`, `bytes`, `totalBytes`, `DestinationMountPoint`, and on recent releases a nested `Progress` dictionary with `Percent`/`TimeRemaining` **[web: tmstatus.sh; nested `Progress` UNVERIFIED]**. The `status` verb is undocumented in the man page. `tmutil latestbackup` gives the last completed backup **[VERIFIED local: usage]**. `backupd` has internal completion/error notification methods (`deliverBackupCompleteNotificationForDestination:`), but no public broadcast was found **[VERIFIED local: strings only]**; the completion banner is mirrored by U1.
- **(b) Recipe — backup progress widget** (15 s; prints nothing when idle):

```bash
#!/bin/zsh
# ~/.config/islet/plugins/timemachine.15s.sh
j=$(tmutil status 2>/dev/null | tail -n +2 | plutil -convert json -o - - 2>/dev/null) || exit 0
[[ $(jq -r .Running <<<"$j") == 1 ]] || exit 0
phase=$(jq -r '.BackupPhase // "Preparing"' <<<"$j")
pct=$(jq -r '(.Progress.Percent // .Percent // "-1") | tonumber' <<<"$j")
left=$(jq -r '(.Progress.TimeRemaining // .Remaining // empty) | tonumber | floor' <<<"$j" 2>/dev/null)
sub=$phase; [[ -n $left ]] && sub+=" · $((left/60)) min left"
(( pct < 0 )) && pct=-1
printf '{"id":"timemachine","title":"Time Machine","subtitle":"%s","icon":"sf:clock.arrow.circlepath","progress":%s,"state":"running","priority":"low","source":"com.apple.backup"}\n' "$sub" "$pct"
```

  When the backup finishes the widget prints nothing; add `--state success` handling by remembering the last state in `$TMPDIR` if you want a "Backup complete" sneak.
- **(c) Islet shows:** compact: circular-arrow clock + ring progress; expanded: phase and time left. Low priority, so music still wins the closed notch.

### 9.3 Tailscale

- **(a) Exposes:** `tailscale` CLI **[VERIFIED local, 1.102.4]**.
  - `tailscale status --json` (poll): top-level keys `BackendState` (`NoState`, `NeedsLogin`, `NeedsMachineAuth`, `Stopped`, `Starting`, `Running`, `InUseOtherUser` **[web: ipn/backend.go]**), `Self` (`Online`, `ExitNode`, `HostName`, `DNSName`, `TailscaleIPs`, `KeyExpiry`…), `Peer{}` (each with `ExitNode`, `Online`), `CurrentTailnet`, `Health` **[VERIFIED local: key names]**. `ExitNodeStatus` (`ID`, `Online`, `TailscaleIPs`) appears only while an exit node is in use **[VERIFIED local: absent when stopped; fields from ipnstate.go]**.
  - `tailscale debug watch-ipn` (event stream of IPN bus messages as indented multi-line JSON; `--initial`, `--count`) **[VERIFIED local: help; output format web: cli/debug.go]**. Debug subcommands are unstable across versions.
  - URL schemes `tailscale://` and `io.tailscale.ipn.macsys://` **[VERIFIED local]**.
  - Taildrop: received files land in `~/Downloads` on macOS, so U4 covers them **[web: tailscale.com/kb/1106]**.
- **(b) Recipe — VPN / exit-node pill** (warns on disconnect, shows the exit node):

```bash
#!/bin/zsh
# ~/.config/islet/plugins/tailscale.30s.sh
s=$(tailscale status --json 2>/dev/null) || exit 0
state=$(jq -r .BackendState <<<"$s")
exit_node=$(jq -r '[.Peer[]? | select(.ExitNode) | .HostName][0] // empty' <<<"$s")
key_days=$(jq -r '.Self.KeyExpiry // empty | sub("\\.[0-9]+";"") | fromdateiso8601? // empty | ((. - now)/86400|floor)' <<<"$s")
if [[ $state != Running ]]; then
  printf '{"id":"tailscale","title":"Tailscale %s","icon":"sf:network.slash","state":"warning","priority":"low","source":"tailscale","url":"tailscale://"}\n' "$state"
elif [[ -n $exit_node ]]; then
  printf '{"id":"tailscale","title":"Exit node","subtitle":"%s","icon":"sf:network.badge.shield.half.filled","trailing":"VPN","priority":"low","source":"tailscale"}\n' "$exit_node"
elif [[ -n $key_days && $key_days -lt 7 ]]; then
  printf '{"id":"tailscale","title":"Tailscale key expires in %s d","icon":"sf:key.fill","state":"warning","source":"tailscale"}\n' "$key_days"
fi
```

- **(c) Islet shows:** nothing when healthy and direct; a shield + exit-node name when routed; an amber "Stopped/NeedsLogin" pill otherwise.


---

## 10. Long-running terminal commands (any terminal, any shell)

**Goal:** every interactive command that takes longer than 10 s shows up in the notch: a spinner once it crosses the threshold, then a green "Done in 2m 14s" or a red "Exit 1" that beats music. It works in Terminal, iTerm2, Ghostty, Warp (see §6.7), and the VS Code/Cursor integrated terminals, because it lives in the shell, not the app.

**Design choices**

- `preexec` records the command and a start time (`$EPOCHREALTIME`); `precmd` computes the duration and the exit code (`$?` must be read on its first line) **[web: zsh manual]**.
- A background `sleep` per command posts the "running" state only if the command outlives the threshold, so short commands cost one short-lived `sleep` and never touch Islet. Set `ISLET_LIVE=0` to report only at the end.
- Interactive and full-screen programs (editors, pagers, `ssh`, `tmux`, REPLs, coding agents, `isletctl` itself) are ignored by regex.
- If you are **looking at** the terminal when the command ends (frontmost app's bundle id equals `$__CFBundleIdentifier`, which terminals set for their shells **[VERIFIED local: the variable is inherited from the launching app]**, via `lsappinfo front` **[VERIFIED local]**), success is shown without a sneak. Failures always sneak.
- `Ctrl-C` (exit 130) is shown as a quiet "Cancelled", not a failure.
- Every Islet call is backgrounded and disowned (`&!`), so a slow or missing Islet never delays your prompt; the whole file is skipped when `isletctl` isn't on `PATH` (for example on SSH hosts).

**Tested:** the zsh and bash versions below were syntax-checked and exercised on this Mac with a stub `isletctl` (a slow failing command, an ignored `vim`, a quick `ls`, a slow success and a Ctrl-C each produced the expected calls). fish is not installed here, so the fish version is **[UNVERIFIED]**.

### 10.1 zsh (default macOS shell)

```zsh
# ~/.config/islet/longcmd.zsh — source from ~/.zshrc:  source ~/.config/islet/longcmd.zsh
# Reports interactive commands that run longer than ISLET_MIN_SECS to the notch.
# Works in Terminal, iTerm2, Ghostty, VS Code/Cursor terminals, and Warp (if it runs your .zshrc hooks).
(( $+commands[isletctl] )) || return 0          # e.g. over SSH on a machine without Islet
zmodload zsh/datetime                           # $EPOCHREALTIME, $EPOCHSECONDS
autoload -Uz add-zsh-hook

typeset -g  ISLET_MIN_SECS=${ISLET_MIN_SECS:-10}  # threshold
typeset -g  ISLET_LIVE=${ISLET_LIVE:-1}           # 1 = show a spinner once the threshold passes
typeset -g  ISLET_QUIET_WHEN_FRONT=${ISLET_QUIET_WHEN_FRONT:-1}  # no sneak if you're looking at this terminal
# Interactive/full-screen programs: never report
typeset -g  ISLET_IGNORE='^(sudo )?(vi|vim|nvim|nano|emacs|hx|less|more|man|ssh|mosh|tmux|screen|top|htop|btop|watch|fzf|lazygit|tig|k9s|claude|codex|python3?|ipython|node|irb|psql|mysql|sqlite3|redis-cli|docker( compose)? (exec|run -it|attach)|tail -f|journalctl -f|log stream|isletctl|ghwatch|hb)( |$)'
typeset -g  _islet_cmd= _islet_t0= _islet_id= _islet_timer=

_islet_short() { local c=${1//$'\n'/ }; print -r -- "${c[1,60]}${${c[61]}:+…}" }

_islet_preexec() {
  _islet_t0=
  [[ $1 =~ $ISLET_IGNORE ]] && return
  _islet_cmd=$(_islet_short "$1")
  _islet_t0=$EPOCHREALTIME
  _islet_id="sh-$$-$EPOCHSECONDS"
  if (( ISLET_LIVE )); then
    # One cheap background sleeper per command; killed in precmd if the command is quick.
    { sleep $ISLET_MIN_SECS
      isletctl set "$_islet_id" --title "$_islet_cmd" --subtitle "Running in ${PWD:t}" \
        --icon sf:terminal.fill --progress -1 --state running --source shell --sneak false
    } >/dev/null 2>&1 &!
    _islet_timer=$!
  fi
}

_islet_precmd() {
  local ec=$?
  [[ -z $_islet_t0 ]] && return
  [[ -n $_islet_timer ]] && { kill $_islet_timer 2>/dev/null; _islet_timer= }
  local dt=$(( EPOCHREALTIME - _islet_t0 )); _islet_t0=
  (( dt < ISLET_MIN_SECS )) && return
  local s=${dt%.*} dur
  if (( s >= 3600 )); then dur="$((s/3600))h $(((s%3600)/60))m"
  elif (( s >= 60 )); then dur="$((s/60))m $((s%60))s"
  else dur="${s}s"; fi
  local sneak=true
  if (( ISLET_QUIET_WHEN_FRONT )) && [[ -n $__CFBundleIdentifier ]]; then
    local front=$(lsappinfo info -only bundleid "$(lsappinfo front)" | sed -n 's/.*bundleID="\([^"]*\)".*/\1/p')
    [[ $front == $__CFBundleIdentifier ]] && sneak=false
  fi
  if (( ec == 130 )); then                     # Ctrl-C: not a failure
    isletctl set "$_islet_id" --title "$_islet_cmd" --subtitle "Cancelled after $dur" \
      --icon sf:stop.circle --state warning --progress 1 --ttl 8 --source shell --sneak false >/dev/null 2>&1 &!
  elif (( ec == 0 )); then
    isletctl set "$_islet_id" --title "$_islet_cmd" --subtitle "Done in $dur · ${PWD:t}" \
      --icon sf:checkmark.circle.fill --state success --progress 1 --trailing "$dur" \
      --ttl 20 --source shell --sneak $sneak >/dev/null 2>&1 &!
  else
    isletctl set "$_islet_id" --title "$_islet_cmd" --subtitle "Exit $ec after $dur · ${PWD:t}" \
      --icon sf:xmark.octagon.fill --state failure --priority high --trailing "exit $ec" \
      --ttl 120 --source shell --sneak true >/dev/null 2>&1 &!
  fi
}

add-zsh-hook preexec _islet_preexec
add-zsh-hook precmd  _islet_precmd
```

### 10.2 bash (via bash-preexec, works with macOS's bash 3.2)

```bash
# ~/.config/islet/longcmd.bash — needs https://github.com/rcaloras/bash-preexec (works on macOS's bash 3.2)
# In ~/.bashrc, last lines:  source ~/.bash-preexec.sh; source ~/.config/islet/longcmd.bash
command -v isletctl >/dev/null || return 0
ISLET_MIN_SECS=${ISLET_MIN_SECS:-10}
ISLET_IGNORE='^(sudo )?(vi|vim|nvim|nano|less|more|man|ssh|tmux|screen|top|htop|watch|fzf|claude|codex|python3?|node|psql|isletctl)( |$)'
_islet_pre() {
  _islet_t0=
  [[ $1 =~ $ISLET_IGNORE ]] && return
  _islet_cmd=${1:0:60}; _islet_t0=$SECONDS; _islet_id="sh-$$-$(date +%s)"
}
_islet_post() {
  local ec=$?
  [[ -z $_islet_t0 ]] && return
  local dt=$(( SECONDS - _islet_t0 )); _islet_t0=
  (( dt < ISLET_MIN_SECS )) && return
  local dur="$((dt/60))m $((dt%60))s"; (( dt < 60 )) && dur="${dt}s"
  if (( ec == 0 )); then
    (isletctl set "$_islet_id" --title "$_islet_cmd" --subtitle "Done in $dur · ${PWD##*/}" \
      --icon sf:checkmark.circle.fill --state success --progress 1 --ttl 20 --source shell >/dev/null 2>&1 &)
  elif (( ec != 130 )); then
    (isletctl set "$_islet_id" --title "$_islet_cmd" --subtitle "Exit $ec after $dur · ${PWD##*/}" \
      --icon sf:xmark.octagon.fill --state failure --priority high --ttl 120 --source shell >/dev/null 2>&1 &)
  fi
}
preexec_functions+=(_islet_pre)
precmd_functions+=(_islet_post)
```

bash-preexec provides `preexec_functions`/`precmd_functions` on bash ≥ 3.1 through the DEBUG trap and must be sourced last in `.bashrc` **[web: rcaloras/bash-preexec]**.

### 10.3 fish

```fish
# ~/.config/fish/conf.d/islet.fish — fish_postexec gives the command line in $argv[1],
# the exit code in $status and the duration in $CMD_DURATION (ms)
function __islet_postexec --on-event fish_postexec
    set -l ec $status
    command -q isletctl; or return
    test $CMD_DURATION -lt 10000; and return
    string match -qr '^(sudo )?(vi|vim|nvim|less|man|ssh|tmux|top|htop|fzf|claude|codex|isletctl)( |$)' -- $argv[1]; and return
    set -l secs (math -s0 $CMD_DURATION / 1000)
    set -l cmd (string sub -l 60 -- $argv[1])
    set -l id sh-$fish_pid-(date +%s)
    if test $ec -eq 0
        isletctl set $id --title "$cmd" --subtitle "Done in "$secs"s · "(basename $PWD) \
            --icon sf:checkmark.circle.fill --state success --progress 1 --ttl 20 --source shell >/dev/null 2>&1 &
    else if test $ec -ne 130
        isletctl set $id --title "$cmd" --subtitle "Exit $ec after "$secs"s · "(basename $PWD) \
            --icon sf:xmark.octagon.fill --state failure --priority high --ttl 120 --source shell >/dev/null 2>&1 &
    end
    disown 2>/dev/null
end
```

### 10.4 Explicit wrapping (scripts, CI-like jobs, cron)

For non-interactive scripts, where hooks don't run, wrap the command: `isletctl run --title "nightly backup" -- restic backup ~/Documents`. It mirrors the command's lifecycle (spinner, then "Finished in 3:12" or "Failed (exit 1)"), passes stdin/stdout/stderr through untouched, and returns the command's exit code. For step-wise jobs, report progress yourself:

```zsh
#!/bin/zsh
steps=(lint test build deploy); n=${#steps}; i=0
for s in $steps; do
  isletctl set release --title "Release" --subtitle "$s" --steps $n --step $i --state running --sneak false
  make $s || { isletctl set release --title "Release failed" --subtitle "$s" --state failure --priority high; exit 1; }
  i=$(( i + 1 ))
done
isletctl set release --title "Released" --steps $n --step $n --state success --ttl 30
```

**(c) Islet shows:** compact: terminal icon + spinner (running), a check mark + duration (success), a cross + exit code (failure, high priority); sneak on completion unless the terminal is frontmost; expanded: the command line, directory and duration.


---

## 11. iPhone Shortcuts → Mac (LAN bridge)

The iPhone cannot open `islet://` URLs on the Mac, so these recipes use **Get Contents of URL** against Islet's **LAN bridge**: the same API on port **47832**, advertised over Bonjour as `_islet._tcp`, token still required, browser origins refused, 30 requests per 10 s per client (`docs/API.md`).

### 11.0 One-time setup

1. Islet → Settings → Integrations → enable the local-network bridge.
2. On the Mac: `scutil --get LocalHostName` gives the Bonjour name (use `http://<name>.local:47832`); `isletctl token` gives the token. Check from the Mac: `curl -s http://$(scutil --get LocalHostName).local:47832/v1/health`.
3. On the iPhone, build every request the same way:
   - **Get Contents of URL** → URL `http://<name>.local:47832/v1/<endpoint>`
   - **Method** POST (DELETE for dismissals)
   - **Headers**: `Authorization` = `Bearer <token>` (the header editor is under "Headers" **[web: Cassinelli's action reference]**; Apple's guide documents Method and a JSON/Form/File body **[web: Apple Shortcuts guide]**)
   - **Request Body**: JSON; add each field with the right type (Text, Number, Boolean).
   - Tip: put this in a helper shortcut "Islet POST" that takes the endpoint and fields, so the token lives in one place.
4. Personal automations: on iOS 26 these are created under Automation → **+** → trigger → *Run Immediately*; Apple's iOS 27 guide attaches automations from the shortcut editor and uses "Allow Running When Locked" **[web: Apple Shortcuts guide (iOS 27)]**. Wording differs by version; the triggers below exist in both.
5. **Limits.** The Mac must be awake and on the same network (or reachable over Tailscale: whether the bridge also listens on the `utun` interface is **[UNVERIFIED]**). iOS may ask for Local Network permission the first time Shortcuts reaches a LAN address **[UNVERIFIED]**. Accepting incoming connections needs no permission on the Mac **[web: Apple TN3179]**. The token is stored in plain text inside the shortcut; rotate it if you share the shortcut.

### 11.1 The recipes

| # | Trigger (iPhone) | Actions | Body sent to the Mac | Islet shows |
|---|---|---|---|---|
| 1 | **Alarm → Wake-up → Is Stopped** | *Get Upcoming Events* (1) → *Get Current Weather* → *Get Contents of URL* | `POST /v1/activities` `{"id":"morning","title":"Good morning","subtitle":"<Event> at <Start Date> · <Temperature>","icon":"sf:sun.max.fill","ttl":1800,"priority":"normal"}` | A sneak on the Mac as you sit down; a sun pill for 30 min, below the calendar countdown |
| 2 | **Alarm → Is Snoozed** | *Get Contents of URL* | `POST /v1/timer` `{"seconds":540,"title":"Snoozed"}` | A 9-min orange countdown ring |
| 3 | **Siri / Action button: "Tea timer"** (no trigger exists for "a timer started", and Shortcuts cannot read a running timer **[web: Start Timer action; negative UNVERIFIED]**) | *Start Timer* 4 min → *Get Contents of URL* | `POST /v1/timer` `{"seconds":240,"title":"Tea"}` | The same countdown on the Mac as on the phone |
| 4 | **Focus → Work → When Turning On** (and a twin *When Turning Off* with `"on":false`) | *Get Contents of URL* | `POST /v1/focus` `{"name":"Work","on":true}` | iPhone-style indigo Focus pill in the notch |
| 5 | **Leave → Home** (only useful when the Mac stays at home) | *Get Contents of URL* ×2 | `POST /v1/media/command` `{"command":"pause"}` then `POST /v1/notify` `{"title":"Left home","subtitle":"Paused the music","icon":"sf:figure.walk"}` | Music on the home Mac pauses; a short sneak |
| 5b | **Arrive → Office** (Mac docked at the office) | *Get Contents of URL* | `POST /v1/focus` `{"name":"Office","on":true}` | Focus pill switches as you walk in |
| 6 | **Battery Level → Falls Below 20%** / **Charger → Is Connected** | *Get Battery Level* → *Get Contents of URL* | `POST /v1/activities` `{"id":"iphone-battery","title":"iPhone <Battery Level>%","icon":"sf:iphone.gen3","progress":<Battery Level ÷ 100>,"state":"warning","tint":"orange","ttl":900}`; on charger connect send `"state":"running","tint":"green","title":"iPhone charging"` | An iPhone pill with a battery ring on the Mac; turns green when plugged in |
| 7 | **CarPlay → Disconnects** | *Get Current Location* → *Get Address from Location* → *Get Contents of URL* | `POST /v1/activities` `{"id":"parked","title":"Parked","subtitle":"<Street>","icon":"sf:car.fill","url":"maps://?ll=<Latitude>,<Longitude>","ttl":14400,"priority":"low"}` | When you reach your desk, a low-priority "Parked · Main St" pill; click opens Maps at the car |
| 8 | **NFC → "Desk" tag** | *Get Contents of URL* ×2 | `POST /v1/focus` `{"name":"Deep Work","on":true}` then `POST /v1/timer` `{"seconds":1500,"title":"Deep work"}` | Tap the phone on the desk tag: Focus pill + 25-min countdown |
| 8b | **NFC → "Washer" tag** | *Get Contents of URL* | `POST /v1/timer` `{"seconds":3300,"title":"Laundry"}` | A 55-min laundry countdown on the Mac |
| 9 | **Sleep → Wind Down Begins** | *Get Contents of URL* ×2 | `POST /v1/focus` `{"name":"Sleep","on":true}` then `POST /v1/notify` `{"title":"Wind down","subtitle":"Wrap up in 30 min","icon":"sf:bed.double.fill"}` | Sleep pill and a gentle sneak on the Mac |

Trigger names follow Apple's current Shortcuts guide: Alarm (Is Snoozed / Is Stopped; Any, Existing, or Wake-up), Sleep (Wind Down Begins / Bedtime Begins / Waking Up), Arrive / Leave, CarPlay (Connects / Disconnects), Battery Level (Equals / Rises Above / Falls Below), Charger (Is Connected / Disconnected), Focus (When Turning On / Off), NFC, Wi-Fi, App opened/closed **[web: Apple Shortcuts guide, setting triggers / travel triggers / event triggers]**.

**Dates and numbers.** For countdowns to a real time (for example "train leaves at 08:12" from a Calendar event), send `endsAt` as *Format Date → ISO 8601* (Islet parses ISO-8601 with or without fractional seconds and with offsets, per `Sources/IsletCore/HTTP.swift`) or as Unix seconds. Send `progress` as a Number between 0 and 1 (or 1–100).


---

## 12. What this catalogue implies for Islet (gaps worth closing)

Ordered by how many recipes above each would simplify:

1. **Managed "bridges" folder.** Supervise long-running scripts in `~/.config/islet/bridges/` (restart with back-off, log to a file) the way widgets are supervised. This replaces the LaunchAgent step in the Docker, OBS, Tailscale `watch-ipn` and `log stream` recipes, and it is the #1 friction point today (widgets are killed after 15 s).
2. **Distributed-notification rules in `config.json`.** For example `{"notification": "com.spotify.client.PlaybackStateChanged", "activity": {"title": "{Name}", "subtitle": "{Artist}"}}`. This removes the Hammerspoon dependency for broadcasters (Music, Spotify, screen lock, any app) at zero permission cost.
3. **Built-in unread badges (U5).** Read Dock badge labels (`lsappinfo` `StatusLabel`, falling back to the `AXStatusLabel` attribute for apps that report NULL, such as Messages and WhatsApp) and show one "Unread" pill. This covers Slack, Mail, Discord, Teams, WhatsApp and Telegram with no setup.
4. **CLI and URL parity.** Add `isletctl set --ends-at/--started-at/--action "Title=URL"` and `islet://activity?…&url=&steps=&step=&endsAt=`. Today countdowns and buttons need `curl`, and Shortcuts/BTT/KM users can't set a click URL through `islet://`.
5. **Outgoing hooks.** Run a script or open a URL when Islet state changes (Focus toggled from the notch, an activity's action tapped, a call started or ended). This enables "call starts → Slack status 'In a call'" and "Focus on → Slack DND" without polling.
6. **OBS as a first-class source.** A small built-in obs-websocket v5 client (password in Keychain) gives streamers REC/LIVE with a count-up and scene name. The Python bridge (§8.9) proves the model.
7. **GitHub webhook adaptor.** A `POST /v1/hooks/github` that maps `workflow_run`/`check_suite` payloads to activities, so `gh webhook forward --events=workflow_run --url=http://127.0.0.1:47831/v1/hooks/github` works. `gh webhook forward` cannot add the bearer header, so this endpoint would need a per-hook secret in the URL, or a `gh`-specific allowance. Design carefully.
8. **Folder progress beyond `~/Downloads`.** Let users add folders (an export directory, an external drive) to the `NSProgress` subscription list. This helps Compressor/HandBrake/Premiere exports and large Finder copies.
9. **Ship importable Shortcuts.** Sign the §11 recipes with `shortcuts sign` and link them from Settings, with the host and token prefilled via an import question.
10. **Drop Teams-specific plans.** The local API is gone (MC1266901). Invest in U1/U2 quality (helper-process attribution, per-app mute rules) instead.

---

## 13. Sources

**Local (this Mac, read-only):** `Info.plist` `CFBundleURLTypes` and `.sdef` files of Music, Spotify, Podcasts, Safari, Chrome, Brave, zoom.us, Microsoft Teams, Slack, Discord, Messages, FaceTime, Phone, Mail, Calendar, Reminders, Notes, Visual Studio Code, Terminal, Docker, Shortcuts, OBS, Time Machine, Tailscale, Figma, Outlook, Telegram, WhatsApp, VLC, Home, Clock; StandardAdditions and System Events dictionaries (folder actions); strings in the Music, Spotify, Podcasts and `backupd` binaries; `--help` output of `gh` 2.72.0, `docker` 29.0.1 (`events`, `desktop status`), `tailscale` 1.102.4 (`status`, `debug watch-ipn`), `shortcuts`, `tmutil`, `brew` 6.0.20; `tmutil status` and `tailscale status --json` key names; OBS `obs-websocket` config keys; `lsappinfo` read-only queries; Islet's own `docs/API.md` and `Sources/` (`URLCommand.swift`, `AgentHooks.swift`, `ScriptPlugins.swift`, `HTTP.swift`, `isletctl/main.swift`).

**Media and chat**
- Spotify notification keys: https://gist.github.com/loretoparisi/6092634d34e97a062029b078215b6bdc
- Music/iTunes playerInfo: https://dev.to/technocoder/finding-distributed-notifications-on-macos-catalina-c9p , https://github.com/tternes/distnote/blob/master/README.md
- MediaRemote adapter: https://github.com/ungive/mediaremote-adapter
- Teams API retirement: https://mc.merill.net/message/MC1266901 ; history: https://github.com/AntoineGS/teams-status-rs , https://github.com/kosmonautica/StreamDeckMSTeams_Udo , https://www.msxfaq.de/teams/apps/teams_3rd_party_client_api_beschreibung.htm
- Zoom: https://dustin.lol/post/2021/better-zoom-mute/ , https://www.brunerd.com/blog/2022/03/07/respecting-focus-and-meeting-status-in-your-mac-scripts-aka-dont-be-a-jerk/ , https://devforum.zoom.us/t/alternative-to-deprecated-client-url-schemes/53526
- Slack: https://docs.slack.dev/interactivity/deep-linking/ , https://docs.slack.dev/reference/methods/dnd.setSnooze , https://docs.slack.dev/reference/methods/users.setPresence
- Discord: https://docs.discord.com/developers/topics/oauth2 , https://docs.discord.com/developers/topics/rpc , https://gist.github.com/ghostrider-05/8f1a0bfc27c7c4509b4ea4e8ce718af0
- Messages: https://zekesnider.com/the-making-of-jared/ , https://davidbieber.com/snippets/2020-05-20-imessage-sql-db/ , https://gist.github.com/stephancasas/06322088ed0071f9e2dcddeee06974fe
- Dock badges via lsappinfo: https://github.com/FelixKratz/SketchyBar/discussions/317
- FaceTime URLs: https://developer.apple.com/library/archive/featuredarticles/iPhoneURLScheme_Reference/FacetimeLinks/FacetimeLinks.html

**Browsers**
- Arc: https://raw.githubusercontent.com/raycast/extensions/main/extensions/arc/src/arc.ts , https://www.atlassian.com/blog/announcements/atlassian-acquires-the-browser-company
- Firefox: https://bugzilla.mozilla.org/show_bug.cgi?id=125419 , https://developer.mozilla.org/en-US/docs/Mozilla/Add-ons/WebExtensions/manifest.json/host_permissions
- Chrome: https://developer.chrome.com/docs/extensions/develop/concepts/network-requests , https://developer.chrome.com/docs/extensions/develop/concepts/match-patterns , https://developer.chrome.com/docs/extensions/reference/api/downloads , https://developer.chrome.com/blog/local-network-access
- Safari developer settings: https://support.apple.com/guide/safari/use-the-developer-tools-in-the-develop-menu-sfri20948/mac

**Tasks and notes**
- Things: https://culturedcode.com/things/support/articles/2803573/ , https://culturedcode.com/things/download/Things3AppleScriptGuide.pdf
- Todoist: https://developer.todoist.com/api/v1/ , https://raw.githubusercontent.com/Doist/todoist-api-python/main/todoist_api_python/api.py
- OmniFocus: https://inside.omnifocus.com/url-schemes , https://omni-automation.com/script-url/index.html , https://inside.omnifocus.com/applescript
- Fantastical: https://flexibits.com/fantastical/help/integration
- Obsidian: https://obsidian.md/help/uri , https://github.com/coddingtonbear/obsidian-local-rest-api , https://publish.obsidian.md/shellcommands/Events/File+content+modified , https://github.com/Vinzent03/obsidian-advanced-uri
- Notion: https://developers.notion.com/reference/versioning , https://developers.notion.com/reference/query-a-data-source , https://developers.notion.com/docs/upgrade-guide-2025-09-03 , https://developers.notion.com/reference/webhooks-events-delivery
- Linear: https://linear.app/developers/graphql , https://linear.app/developers/filtering , https://linear.app/developers/webhooks
- Figma: https://developers.figma.com/docs/rest-api/comments-endpoints/ , https://developers.figma.com/docs/rest-api/webhooks-events/
- 1Password: https://www.1password.dev/cli/reference/commands/whoami/ , https://github.com/1Password/op-js/issues/227 , https://www.1password.dev/cli/app-integration/

**Developer tools**
- Xcode Behaviors: https://help.apple.com/xcode/mac/current/en.lproj/dev66189ede4.html ; shell env: https://www.jessesquires.com/blog/2023/12/06/xcode-shell-env/ ; Xcode Cloud webhooks: https://developer.apple.com/tutorials/data/documentation/xcode/configuring-webhooks-in-xcode-cloud.json , https://www.polpiella.dev/xcode-cloud-webhooks
- VS Code: https://code.visualstudio.com/docs/debugtest/tasks , https://code.visualstudio.com/api/references/vscode-api , https://code.visualstudio.com/updates/v1_93 , https://code.visualstudio.com/docs/configure/command-line
- Cursor hooks: https://cursor.com/docs/hooks , https://www.infoq.com/news/2025/10/cursor-hooks/
- iTerm2: https://iterm2.com/python-api/prompt.html , https://iterm2.com/documentation-triggers.html , https://iterm2.com/documentation-escape-codes.html , https://iterm2.com/documentation-scripting.html
- Ghostty: https://ghostty.org/docs/install/release-notes/1-3-0 , https://ghostty.org/docs/config/reference , https://ghostty.org/docs/vt/osc/9 , https://ghostty.org/docs/features/applescript
- Warp: https://docs.warp.dev/terminal/more-features/notifications , https://docs.warp.dev/features/uri-scheme , https://docs.warp.dev/support-and-community/troubleshooting-and-support/known-issues
- Docker: https://docs.docker.com/reference/cli/docker/system/events/ , https://docs.docker.com/reference/cli/docker/desktop/status/
- GitHub CLI: https://cli.github.com/manual/gh_run_watch , https://cli.github.com/manual/gh_run_list , https://cli.github.com/manual/gh_pr_checks , https://docs.github.com/en/webhooks/testing-and-troubleshooting-webhooks/using-the-github-cli-to-forward-webhooks-for-testing
- Homebrew: https://github.com/Homebrew/brew/blob/main/Library/Homebrew/cmd/outdated.rb , https://docs.brew.sh/Manpage
- Shells: https://zsh.sourceforge.io/Doc/Release/Functions.html , https://zsh.sourceforge.io/Doc/Release/User-Contributions.html , https://github.com/rcaloras/bash-preexec , https://github.com/fish-shell/fish-shell/blob/master/doc_src/language.rst
- Coding agents: https://code.claude.com/docs/en/hooks , https://developers.openai.com/codex/config-advanced

**Automation hubs**
- Raycast: https://github.com/raycast/script-commands/blob/master/README.md , https://developers.raycast.com/information/lifecycle/deeplinks
- Alfred: https://www.alfredapp.com/help/workflows/triggers/external/
- Hammerspoon: https://www.hammerspoon.org/docs/hs.distributednotifications.html , https://www.hammerspoon.org/docs/hs.http.html , https://www.hammerspoon.org/docs/hs.caffeinate.watcher.html , https://www.hammerspoon.org/docs/hs.usb.watcher.html , https://www.hammerspoon.org/docs/hs.wifi.watcher.html , https://www.hammerspoon.org/docs/hs.urlevent.html
- BetterTouchTool: https://docs.folivora.ai/docs/1102_apple_script.html , https://docs.folivora.ai/docs/scripting/url-scheme/ , https://community.folivora.ai/t/send-web-request-action-with-bettertouchtool/29792
- Keyboard Maestro: https://wiki.keyboardmaestro.com/trigger/URL , https://wiki.keyboardmaestro.com/action/Execute_a_Shell_Script , https://wiki.keyboardmaestro.com/Triggers
- Stream Deck: https://github.com/mjbnz/streamdeck-api-request , https://github.com/data-enabler/streamdeck-web-requests , https://docs.elgato.com/streamdeck/sdk/introduction/getting-started
- Home Assistant: https://www.home-assistant.io/integrations/rest_command/ , https://developers.home-assistant.io/docs/api/rest/ , https://www.home-assistant.io/docs/automation/trigger/
- Shortcuts on Mac: https://www.apple.com/newsroom/2025/06/macos-tahoe-26-makes-the-mac-more-capable-productive-and-intelligent-than-ever/ , https://www.macstories.net/stories/macos-26-tahoe-the-macstories-review/4/ , https://support.apple.com/guide/shortcuts-mac/run-shortcuts-from-the-command-line-apd455c82f02/mac
- Shortcuts on iPhone: https://support.apple.com/guide/shortcuts/setting-triggers-apde31e9638b/ios , https://support.apple.com/guide/shortcuts/travel-triggers-apd8ebfc4e8e/ios , https://support.apple.com/guide/shortcuts/event-triggers-apd932ff833f/ios , https://support.apple.com/guide/shortcuts/request-your-first-api-apd58d46713f/ios , https://matthewcassinelli.com/actions/get-contents-of-url/ , https://matthewcassinelli.com/actions/start-timer/ , https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy

**Media production, system, network**
- Compressor: https://support.apple.com/guide/compressor/submit-a-job-to-compressor-in-terminal-cpsr9be73312/mac , https://support.apple.com/guide/compressor/common-command-options-cpsr9be734f8/mac
- HandBrake: https://raw.githubusercontent.com/HandBrake/HandBrake/master/test/test.c , https://github.com/HandBrake/HandBrake/blob/master/libhb/hb_json.c , https://github.com/HandBrake/HandBrake/blob/master/macosx/HBPreferencesKeys.h
- Transmission: https://github.com/transmission/transmission/blob/main/docs/Scripts.md , https://github.com/transmission/transmission/blob/main/docs/rpc-spec.md , https://github.com/transmission/transmission/blob/main/docs/Editing-Configuration-Files.md , https://github.com/transmission/transmission/blob/main/macosx/PrefsController.mm
- qBittorrent: https://github.com/qbittorrent/qBittorrent/blob/master/src/gui/optionsdialog.cpp , https://github.com/qbittorrent/qBittorrent/wiki/WebUI-API-(qBittorrent-5.0)
- OBS: https://github.com/obsproject/obs-websocket/blob/master/docs/generated/protocol.md , https://github.com/aatikturk/obsws-python
- Time Machine: https://github.com/matteocorti/tmstatus.sh/blob/master/tmstatus.sh , https://keith.github.io/xcode-man-pages/tmutil.8.html
- Tailscale: https://github.com/tailscale/tailscale/blob/main/ipn/ipnstate/ipnstate.go , https://github.com/tailscale/tailscale/blob/main/ipn/backend.go , https://tailscale.com/kb/1080/cli , https://tailscale.com/kb/1106/taildrop

