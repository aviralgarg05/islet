# Islet API

Anything that can run a command, open a URL or send an HTTP request can put a **live activity** in the notch. There are four ways in, all backed by the same model:

| Surface | Best for |
|---|---|
| `isletctl` CLI | shell scripts, git hooks, Makefiles, coding-agent hooks |
| HTTP API on `127.0.0.1` | programs, browser extensions, Hammerspoon, Home Assistant |
| `islet://` URL scheme | Shortcuts, Raycast, Alfred, BetterTouchTool, Stream Deck, Keyboard Maestro |
| Script widgets | anything you'd write as an xbar/SwiftBar plugin |

---

## Live activities

An activity is identified by `id`. Sending the same `id` again **updates** it (fields you omit keep their value), so a script can create an activity and then just send `progress` updates.

```json
{
  "id": "deploy-web",
  "title": "Deploying web",
  "subtitle": "step 3 of 5 · migrating",
  "icon": "sf:paperplane.fill",
  "progress": 0.6,
  "state": "running",
  "tint": "#0A84FF",
  "priority": "normal",
  "ttl": 0,
  "url": "https://github.com/me/web/actions/runs/1",
  "actions": [{ "title": "Logs", "url": "https://github.com/me/web/actions/runs/1" }]
}
```

| Field | Type | Meaning |
|---|---|---|
| `id` | string, 1–128 of `[A-Za-z0-9._:-]` | Stable identity. Omit to get a generated one. |
| `title` | string | **Required when creating.** |
| `subtitle` | string | Second line. Send `""` to clear. |
| `icon` | string | `sf:<SF Symbol>`, `emoji:🚀`, `app:<bundle id>`, `url:https://…png`, `file:/path.png`, or a bare symbol name / single emoji. Omit it and Islet picks one from the text (smart icons). |
| `trailing` | string | Short text for the right-hand wing (`"42%"`, `"3/5"`, `"Done"`). Default: derived from the countdown, steps or progress. |
| `progress` | number | `0…1`, or `1…100` (read as a percentage), or negative for an indeterminate spinner. |
| `steps`, `step` | int | Segmented progress ("step 2 of 5"): a stepper bar and `2/5` in the wing. |
| `state` | `info` `running` `success` `warning` `failure` `waiting` | Drives the default icon and colour. `success`/`failure` auto-dismiss after 10 s unless `ttl` is set. |
| `tint` | string | `#RRGGBB`, `#RGB`, `#RRGGBBAA` or a system colour name (`red`, `orange`, `yellow`, `green`, `mint`, `teal`, `cyan`, `blue`, `indigo`, `purple`, `pink`, `brown`, `gray`). |
| `priority` | `low` `normal` `high` `critical` (or 0–3) | `high` beats playing music for the closed island; `critical` breaks through fullscreen. |
| `relevance` | 0–100 | Orders activities of the same priority (ActivityKit's relevance score). |
| `ttl` | seconds | Auto-dismiss. `0` = stay until removed. |
| `endsAt` | ISO-8601 or Unix seconds/ms | Live countdown to this moment. |
| `startedAt` | ISO-8601 or Unix seconds/ms | Live count-up from this moment (calls, stopwatches, recordings). |
| `staleAt` | date | After this the activity dims and sinks below fresh ones. |
| `url` | URL | Opened when the island is clicked while showing this activity. |
| `actions` | `[{title, url, dismiss?}]` | Buttons in the expanded island (up to 2). `url` may be any scheme: `https`, `shortcuts://`, `raycast://`, `file://`… |
| `sneak` | bool | Briefly expand to announce the change. Default: on create (normal priority and up) and when a run finishes. |
| `source` | string | Who sent it; used for grouping, muting and app rules. Use a bundle id to get that app's icon. |

**What shows in the closed island**, highest first: volume/brightness HUD → a new or updated activity (the "sneak peek") → `high`/`critical` activities → battery events → playing music → other activities. With "Activities shown together" at 2 or 3, the next ones appear as detached bubbles beside the notch, like the iPhone.

### Templates

A template gives an activity the look of an iPhone Live Activity of its kind: a ride with a moving car, a score with two team badges, a flight board. It changes what the wings, the dropped pill, the sneak peek, the bubble and the expanded row show. Every surface follows one rule: what it is on the left, the one value that changes on the right.

Pick one with `template`. Without it, Islet looks up `source` in its catalogue of 137 apps with Live Activities (by bundle id, app name or alias, for example `com.ubercab.UberClient`, `Uber` or `Flighty`) and uses that app's template when the activity has the data for it. Failing that, the fields decide: `teams` → score, `flight` → flight, `route` → route, `stageLabels` → stages, `trackerIcon` or an eta `phase` → eta, `metrics` → workout, only `endsAt` or `startedAt` → timer, anything else → progress (the generic look).

| Field | Type and limits | Meaning |
|---|---|---|
| `template` | `eta` `stages` `flight` `route` `score` `timer` `workout` `gauge` `live-audio` `media` `agent` `progress` | The layout. `""` goes back to automatic. |
| `compactShort` | string, ≤ 5 characters | What the bubble shows ("3–1", "12m"). Default: derived from the template. |
| `trackerIcon` | icon | The glyph that rides the ETA track (`sf:car.fill`, `sf:bicycle`). |
| `phase` | string, ≤ 24 characters | eta: `pickup` `enroute` `arrived` `delivered`. flight: `predeparture` `boarding` `airborne` `landed` (derived from the times when omitted). Other text is shown as it is (agents: "Testing"). |
| `stageLabels` | up to 8 strings, ≤ 24 characters each | Named stages, with `step` (1-based) marking the current one. |
| `stageSymbols` | up to 8 icons | One glyph per stage; the current one leads the wings. |
| `teams` | exactly 2 of `{abbr, name, score, tint}` | `abbr` ≤ 4 characters, `name` ≤ 32, `score` ≤ 7 (text or number), `tint` a colour. |
| `period` | string, ≤ 12 characters | "Q4", "67'", "Bot 7". `endsAt` or `startedAt` adds a game clock. |
| `flight` | `{number, from, to, departs, arrives, gate, terminal, seat, status, carousel}` | `number` ≤ 10 characters, airport codes ≤ 4, `gate`/`terminal`/`seat`/`carousel` ≤ 6, `status` ≤ 24 ("On time" green, "Delayed…" amber, "Cancelled" or "Diverted" red). |
| `route` | `{mode, line, lineTint, stopsLeft, instruction, distance}` | `mode`: walk, bus, tram, train, subway, ferry, car or bike. `line` ≤ 6 characters, `stopsLeft` 0–999, `instruction` ≤ 80, `distance` ≤ 10 ("200 m"). |
| `metrics` | up to 3 of `{label, value, unit}` | Live values; `value` (text or number) ≤ 10 characters, `label` ≤ 12, `unit` ≤ 8. |

On update, omitted fields keep their value, as elsewhere. An empty string or array clears a field, including one inside `flight`, `route` or a team (`trackerIcon`, like `icon`, can only be replaced). `flight` and `route` merge field by field, so `{"flight":{"gate":"C4"}}` changes only the gate, and `teams` merges by position, so `{"teams":[{"score":103},{"score":98}]}` changes only the scores. A value over its limit is rejected with `422` and the field's name. Responses also carry `trackSpan`, the seconds the ETA track covers.

Some updates open the island briefly on their own, unless they carry `"sneak": false`: a ride arriving, an order reaching its next stage, a score changing, a gate change, a flight turning delayed, cancelled or back on time, boarding starting, and a transit trip two stops from its stop or at it.

Numbers roll when they change. Timer rings and waveforms run on Core Animation and never redraw the view; minute counts refresh once a minute. Motion Off freezes them and Reduce Motion stops the waveforms. The island stays black: the tint colours glyphs, rings, bars and keylines only, and tints too dark to read on black (Uber's black, JetBlue's navy) are lifted until they reach 3:1 contrast.

**`eta`**: a ride or delivery arriving. Wings: the icon, then "4 min" (or the car and "Here" once `phase` is `arrived`). Sneak and row: a 10-step track with the tracker riding it. Its start is fixed by the first `endsAt`, so the car moves at a steady pace; if the ETA grows, the car holds still rather than going back. Send `progress` to place it yourself.

```json
{"id": "ride", "source": "com.ubercab.UberClient", "title": "Grey Prius · 7ABC123", "subtitle": "Arriving",
 "template": "eta", "trackerIcon": "sf:car.fill", "phase": "enroute", "endsAt": "2026-10-01T08:14:00Z"}
```

**`stages`**: an order or parcel moving through named stages. Wings: the current stage's glyph, then the ETA or "2/4". Sneak: a bar with a dot per stage and the labels under it.

```json
{"id": "order", "title": "Swiggy", "subtitle": "Your order is being prepared", "template": "stages",
 "stageLabels": ["Placed", "Preparing", "On the way", "Delivered"],
 "stageSymbols": ["checkmark.circle.fill", "frying.pan.fill", "bicycle", "house.fill"],
 "steps": 4, "step": 2, "endsAt": "2026-10-01T19:40:00Z"}
```

**`flight`**: a departure board. Wings follow the phase: the gate and time to departure, then time to landing, then the baggage belt. Sneak and row: "SFO 08:05 ✈ JFK 16:40" with a status chip; the plane moves along the line as the flight progresses.

```json
{"id": "ua1234", "title": "UA 1234 to New York", "template": "flight",
 "flight": {"number": "UA 1234", "from": "SFO", "to": "JFK", "departs": "2026-10-01T15:05:00Z",
            "arrives": "2026-10-01T20:40:00Z", "gate": "B22", "terminal": "3", "seat": "14C", "status": "On time"}}
```

**`route`**: a transit leg or a navigation step. Wings: the line badge, or without a `line` a turn arrow (when `instruction` says left or right) or the mode's glyph; then stops left, the distance to the turn, or minutes to `endsAt`.

```json
{"id": "muni", "title": "N Judah to Ocean Beach", "template": "route", "endsAt": "2026-10-01T08:21:00Z",
 "route": {"mode": "tram", "line": "N", "lineTint": "#0A84FF", "stopsLeft": 3, "instruction": "Get off at Carl & Cole"}}
```

**`score`**: two teams. Wings: each team's badge and score, both sides the same width (in the narrow wings the abbreviation sits over the score). Dropped pill: the period between them. Sneak: period, game clock and `subtitle` as the last play.

```json
{"id": "game", "title": "Lakers at Celtics", "subtitle": "Tatum makes 3-pt jump shot", "template": "score", "period": "Q4",
 "teams": [{"abbr": "LAL", "name": "Lakers", "score": 102, "tint": "#FDB927"},
           {"abbr": "BOS", "name": "Celtics", "score": 98, "tint": "#007A33"}]}
```

**`timer`**: a countdown (`endsAt`) or count-up (`startedAt`). Wings: the glyph inside a ring that drains to the end and turns red for the last 10 seconds, then `m:ss`.

```json
{"id": "tea", "title": "Tea", "icon": "sf:cup.and.saucer.fill", "tint": "orange", "template": "timer", "endsAt": "2026-10-01T08:04:32Z"}
```

**`workout`**: live session metrics. Wings: the activity glyph and the elapsed time, or a rest countdown while `endsAt` is ahead. Sneak and row: the metrics.

```json
{"id": "run", "title": "Morning run", "icon": "sf:figure.run", "tint": "#FC4C02", "template": "workout",
 "startedAt": "2026-10-01T07:30:00Z",
 "metrics": [{"value": 5.2, "unit": "km"}, {"value": "5:31", "unit": "/km"}, {"value": 148, "unit": "bpm"}]}
```

**`gauge`**: a level filling or draining (charging, a budget, disk space). Wings: a ring with the percentage inside, then the time to `endsAt`. Row: the ring, "Full in 32 min" and up to two metrics.

```json
{"id": "charge", "title": "Supercharging", "icon": "sf:bolt.car.fill", "tint": "#E82127", "template": "gauge",
 "progress": 0.72, "endsAt": "2026-10-01T08:32:00Z", "metrics": [{"value": 150, "unit": "kW"}, {"value": "$7.40"}]}
```

**`live-audio`**: calls, recordings and voice assistants. Wings: the app glyph, then the elapsed time, or a waveform without `startedAt`. The waveform moves while `state` is `running`. Detected calls use this template.

```json
{"id": "call", "title": "FaceTime", "subtitle": "Mum", "icon": "sf:video.fill", "tint": "green", "template": "live-audio",
 "startedAt": "2026-10-01T08:00:00Z"}
```

**`media`**: Now Playing from a source other than a local player (those use the Now Playing card). Wings: the glyph and an equaliser, `trailing` when sent, or the elapsed time with `startedAt`.

```json
{"id": "np", "title": "Midnight City", "subtitle": "M83", "icon": "sf:music.note", "tint": "#FA2D48", "template": "media", "state": "running"}
```

**`agent`**: an AI agent, build or CI run. Wings: the glyph, then `trailing`, "Needs you" while `waiting`, the `phase`, or "3/7". The bubble adds a dot coloured by state.

```json
{"id": "pr-42", "title": "Fix login flow", "icon": "sf:arrow.triangle.pull", "template": "agent", "state": "running",
 "phase": "Testing", "steps": 7, "step": 3}
```

**`progress`**: the generic look: icon, title, bar or ring, percentage.

```json
{"id": "build", "title": "Release build", "subtitle": "Compiling 142/310", "template": "progress", "progress": 0.46}
```

From the command line, `--template` sets the layout and `--json` sends the richer fields from a file or standard input (flags given with it win):

```bash
isletctl set ride --title "Grey Prius" --template eta --ends-in 240 --icon sf:car.fill
echo '{"title":"Lakers at Celtics","teams":[{"abbr":"LAL","score":3},{"abbr":"BOS","score":1}],"period":"Q2"}' \
  | isletctl set game --json -
```

**Live Activities mirrored from the menu bar** (iPhone activities that macOS shows beside the clock) take the icon, tint and template of their app from the same catalogue. The catalogue is generated from [`research/07-live-activity-apps.json`](research/07-live-activity-apps.json) (119 apps with evidence of a Live Activity) plus Islet's own additions; after editing either, run `scripts/gen-live-activity-apps.py` to regenerate `Sources/IsletCore/LiveActivityApps.swift`.

---

## HTTP API

- **Where:** `http://127.0.0.1:47831` (the port is configurable; if it's taken Islet picks another).
- **Discovery:** `~/Library/Application Support/Islet/api.json` (mode `0600`) contains `{"port", "token", "pid"}`. `isletctl` reads it for you.
- **Auth:** every endpoint except `GET /v1/health` needs `Authorization: Bearer <token>` (or `X-Islet-Token: <token>`). `isletctl token` prints it.
- **Safety:** the server binds to loopback only, rejects requests whose `Host` isn't localhost (DNS rebinding) and requests with a web-page `Origin` (CSRF). Browser extensions (`chrome-extension://`, `moz-extension://`, `safari-web-extension://`) are allowed but still need the token. Bodies are JSON, ≤ 1 MB, with `Content-Length`.

| Method & path | Body | Result |
|---|---|---|
| `GET /v1/health` | — | `{"ok":"true","version":"…"}` (no token needed) |
| `GET /v1/state` | — | presentation, activities, now playing, battery |
| `GET /v1/activities` | — | activities in display order |
| `POST /v1/activities` | activity | `201` + the activity (upsert) |
| `PUT` / `PATCH /v1/activities/{id}` | partial activity | the updated activity |
| `DELETE /v1/activities/{id}` | — | `204`, or `404` |
| `DELETE /v1/activities?source=NAME` | — | `{"removed": n}` |
| `POST /v1/notify` | `{title, subtitle?, icon?, tint?, ttl? (6), priority?, source?}` | a short-lived notification |
| `POST /v1/timer` | `{seconds, title?, id?}` | a countdown activity |
| `POST /v1/hud` | `{kind: volume\|brightness\|keyboardBrightness\|microphone, value: 0…1, muted?, label?}` | shows the HUD |
| `POST /v1/focus` | `{name, on}` | iPhone-style Focus pill |
| `POST /v1/media` | `{title, artist?, album?, isPlaying?, duration?, elapsed?, bundleID?, appName?, artworkURL?}` | report playback from any player |
| `DELETE /v1/media` | — | clear it |
| `POST /v1/media/command` | `{command: play\|pause\|togglePlayPause\|next\|previous\|seek, position?}` | controls whatever is playing |
| `POST /v1/island/open`, `/v1/island/close` | — | expand / collapse |
| `POST /v1/hooks/{provider}` | the agent's own hook payload | see [Coding agents](INTEGRATIONS.md#coding-agents) |

Errors are JSON: `{"error": "'progress' must be between 0 and 1 …"}` with `400`, `401`, `403`, `404`, `405`, `411`, `413`, `422` or `429`.

```bash
TOKEN=$(isletctl token)
curl -s -X POST http://127.0.0.1:47831/v1/activities \
  -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
  -d '{"id":"backup","title":"Backing up","progress":0.3}'
```

### Local-network bridge (iPhone Shortcuts)

Off by default. When enabled (Settings → Integrations), the same API is also served on the local network at port `47832` and advertised over Bonjour as `_islet._tcp`. The token is still required, browser origins are still refused, and each client is limited to 30 requests per 10 seconds. See [iPhone recipes](INTEGRATIONS.md#iphone).

---

## `isletctl`

The CLI ships inside the app: `Islet.app/Contents/MacOS/isletctl`. Put it on your `PATH`:

```bash
ln -sf /Applications/Islet.app/Contents/MacOS/isletctl /opt/homebrew/bin/isletctl
```

```text
isletctl notify <title> [--subtitle S] [--icon ICON] [--tint COLOR] [--ttl SECONDS]
isletctl set <id> [--title T] [--subtitle S] [--progress P] [--state STATE] [--trailing TEXT]
                  [--icon ICON] [--tint COLOR] [--priority P] [--ttl S] [--steps N --step K]
                  [--url URL] [--relevance 0-100] [--stale-in SECONDS] [--sneak true|false]
                  [--ends-in SECONDS] [--started-ago SECONDS] [--action "Title=URL"]
                  [--template NAME] [--json FILE|-]   (a full activity from a file or stdin; flags win)
isletctl rm <id>                      remove an activity
isletctl clear --source NAME          remove all activities from a source
isletctl ls                           list activities (JSON)
isletctl timer <90s|5m|1h> [--title T]
isletctl run [--title T] -- <command…>   mirror a command in the notch; exit code passes through
isletctl hud <volume|brightness|keyboardBrightness> <0-1>
isletctl media <play|pause|playpause|next|previous>
isletctl focus <name> [on|off]
isletctl open | close                  (or press ⌃⌥I; change it in Settings → General)
isletctl hook <claude|codex|AGENT> [JSON]   forward an agent hook payload (stdin or last argument)
isletctl state | health | token
```

`isletctl hook` never fails the calling agent: it exits 0 within ~1.5 s even when Islet isn't running.

---

## `islet://` URL scheme

```text
islet://notify?title=Build%20done&subtitle=main&icon=sf:hammer&tint=green&ttl=5
islet://activity?id=deploy&title=Deploying&progress=0.4&state=running&priority=high
islet://activity?id=pizza&title=Pizza&endsIn=1200&url=https://…&actionTitle=Track&actionURL=https://…&steps=4&step=2
islet://dismiss?id=deploy
islet://timer?minutes=25&title=Focus
islet://hud?kind=volume&value=0.5
islet://media/playpause     (play, pause, next, previous)
islet://focus?name=Work&state=on
islet://open   islet://close   islet://toggle   islet://settings
```

---

## Script widgets

Put executables in `~/.config/islet/plugins/`. The file name sets the refresh interval, xbar-style: `cpu.10s.sh`, `prs.5m.py`, `weather.1h.rb` (default 5 minutes; never more often than once a second). Output can be:

1. **xbar/SwiftBar text**: existing plugins work unchanged. The first line is the header, then `---`, then items. Supported parameters: `href=`, `shell=`/`bash=` with `param1=`…, `color=`, `sfimage=`, `refresh=true`, `disabled=true`, and submenus (`--`).
2. **An Islet activity as JSON**: `{"id":"cpu","title":"CPU 42%","progress":0.42}` becomes a live activity.

Scripts get `ISLET=1`, `SWIFTBAR=1`, `XBARDarkMode=true` and Homebrew on `PATH`, and are killed after 15 s.

---

## Settings file

Everything in Settings lives in `~/.config/islet/config.json` (or `$XDG_CONFIG_HOME/islet/config.json`) and reloads live when edited, so it can live in your dotfiles. Unknown keys are ignored; a bad value falls back to its default without breaking the rest. Example:

```json
{
  "sizePreset": "compact",
  "theme": "black",
  "animationStyle": "fluid",
  "maxConcurrent": 3,
  "hapticsMode": "direct",
  "mutedSources": ["noisy-script"],
  "appRules": [
    { "bundleID": "us.zoom.xos", "showInFullscreen": true, "tint": "blue" },
    { "bundleID": "com.valvesoftware.steam", "hideIsland": true }
  ]
}
```
