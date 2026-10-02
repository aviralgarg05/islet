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

A template gives an activity the look of an iPhone Live Activity of its kind: a ride with a moving car, a score with two team badges, a flight board. It changes what the wings, the sneak peek, the bubble and the expanded row show. Every surface follows one rule: what it is on the left, the one value that changes on the right.

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

**`score`**: two teams. Wings: each team's badge and score, both sides the same width (in the narrow wings the abbreviation sits over the score). Sneak: the same wings, with the period, game clock and `subtitle` as the last play below them.

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
| `GET /v1/state` | — | presentation, activities, now playing, battery, and `calendar` (see below) |
| `GET /v1/activities` | — | activities in display order |
| `POST /v1/activities` | activity | `201` + the activity (upsert) |
| `PUT` / `PATCH /v1/activities/{id}` | partial activity | the updated activity |
| `DELETE /v1/activities/{id}` | — | `204`, or `404` |
| `DELETE /v1/activities?source=NAME` | — | `{"removed": n}` |
| `POST /v1/notify` | `{title, subtitle?, icon?, tint?, ttl? (6), priority?, source?}` | a short-lived notification |
| `POST /v1/timer` (or `/v1/timers`) | `{seconds \| in, title?, id?}` | `201` + the timer; see [Timers](#timers) |
| `GET /v1/timers` | — | timers: ringing first, then by end time, then paused |
| `PATCH /v1/timers/{id}` (or `/v1/timers`) | `{action: pause\|resume\|add\|stop\|restart\|snooze, seconds?, in?}` | the timer, or `204` after `stop`; `404` for an unknown id |
| `DELETE /v1/timers/{id}` | — | stops it: `204`, or `404` |
| `POST /v1/pomodoro` | `{action: start\|stop\|toggle}` | `201` + the Pomodoro timer, or `204` when it stopped |
| `POST /v1/hud` | `{kind: volume\|brightness\|keyboardBrightness\|microphone, value: 0…1, muted?, label?}` | shows the HUD |
| `POST /v1/focus` | `{name, on}` | iPhone-style Focus pill |
| `POST /v1/media` | `{title, artist?, album?, isPlaying?, duration?, elapsed?, bundleID?, appName?, artworkURL?}` | report playback from any player |
| `DELETE /v1/media` | — | clear it |
| `POST /v1/media/command` | `{command: play\|pause\|togglePlayPause\|next\|previous\|seek\|skipForward\|skipBackward\|toggleShuffle\|toggleRepeat, position?}` | controls the player on show: the one picked in the island, or the newest (see [Media commands](#media-commands)) |
| `GET /v1/awake` | — | keep-awake status |
| `POST /v1/awake` | `{minutes?}` (omitted or `0` = until turned off, up to `1440`) | keeps the Mac awake; returns the status |
| `DELETE /v1/awake` | — | lets the Mac sleep again; returns the status |
| `POST /v1/island/open`, `/v1/island/close` | — | expand / collapse |
| `POST /v1/hooks/{provider}` | the agent's own hook payload | see [Coding agents](INTEGRATIONS.md#coding-agents) |
| `POST /v1/hooks/{provider}?wait=N` | a hook payload that asks for a decision | held until answered in the notch: `200` + the JSON the hook prints, or `204` (see [Approvals](#approvals-long-poll)) |

Errors are JSON: `{"error": "'progress' must be between 0 and 1 …"}` with `400`, `401`, `403`, `404`, `405`, `411`, `413`, `422`, `429` or `503`.

```bash
TOKEN=$(isletctl token)
curl -s -X POST http://127.0.0.1:47831/v1/activities \
  -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
  -d '{"id":"backup","title":"Backing up","progress":0.3}'
```

`GET /v1/state` (and `isletctl state`) includes `"calendar": {"events": "fullAccess", "reminders": "notDetermined", "upcoming": 3}`: what macOS allows for calendars and for reminders (`notDetermined`, `fullAccess`, `writeOnly` for "Add events only", `denied` or `restricted`), read afresh for each request, and how many timed events are left today. It never includes a title. Meeting reminders (ids starting with `meeting-`, source `calendar`) carry the meeting's title, so `GET /v1/activities` and `/v1/state` always leave them out. To a script they aren't there: changing or removing one by its id gets a `404`, and `DELETE /v1/activities?source=calendar` removes only your own `calendar` activities and counts only those.

Live Activities mirrored from the menu bar (ids starting with `live-`, sources `live-activity` or starting with `live-activity:`, such as `live-activity:uber`) belong to the mirror. Creating, changing or removing one, or sending that source, gets a `403` whether or not the id exists. `GET /v1/activities` and `/v1/state` leave them out, and `/v1/debug/menubar` leaves out their text, unless **Let scripts read Live Activities** (Settings → Advanced → Local API) is on; see [LIVE-ACTIVITIES.md](LIVE-ACTIVITIES.md).

### Media commands

| `command` | What it does |
|---|---|
| `play`, `pause`, `togglePlayPause`, `next`, `previous` | The usual transport controls. |
| `seek` | Jump to `position` (seconds). |
| `skipForward`, `skipBackward` | 15 s forward or back, worked out from the current position so it works with any player. If Islet doesn't know the position, the player's own 15 s skip is used. |
| `toggleShuffle`, `toggleRepeat` | Shuffle on or off; repeat cycles off → all → one. Players that don't report shuffle or repeat may ignore them, and the island only shows these buttons for players that do. |

A `503` means no player is available for the command. With several players at once, commands go to the one the island shows: through the system's Now Playing when that is the same app, otherwise to Music or Spotify directly (which needs Automation for that player, allowed in Settings → Permissions).

### Keep awake

`POST /v1/awake` stops the display (and so the Mac) from going to sleep while idle, like `caffeinate -d`. It uses a public power assertion and needs no permission.

```bash
curl -s -X POST http://127.0.0.1:47831/v1/awake -H "Authorization: Bearer $TOKEN" -d '{"minutes": 60}'
# {"active":true,"since":"2026-09-30T20:00:00Z","until":"2026-09-30T21:00:00Z","minutesLeft":60}
```

- A new request replaces the current one; `DELETE` ends it early.
- While it's on, a live activity with a cup icon counts down (or shows "On" when it has no end), with a **Turn off** button.
- On battery below 20% it turns itself off (and a new request is refused: the reply says `"active": false`). It never outlives Islet: quitting releases it.
- `minutes` outside 0–1440 gets a `422`.
### Timers

Timers live in Islet rather than in the activity list: they survive a relaunch, can be paused and extended, and ring when they end. Each timer shows up as an activity with the same `id` (source `timer`), and dismissing that activity stops the timer.

```bash
curl -s -X POST http://127.0.0.1:47831/v1/timer -H "Authorization: Bearer $TOKEN" \
  -d '{"in": "in 20 minutes to take the pizza out"}'
```

```json
{"id": "timer-1", "title": "Take the pizza out", "duration": 1200, "status": "running",
 "endsAt": "2026-09-30T18:05:10Z", "createdAt": "2026-09-30T17:45:10Z"}
```

| Field | Meaning |
|---|---|
| `id` | `timer-1`, `timer-2`, … (the lowest free number), your own `id` (not one starting with `live-`), or `pomodoro`. Commands also accept the number alone (`2`) or the title. |
| `status` | `running`, `paused` or `ringing` |
| `duration` | Seconds it was started with; `restart` runs it again for this long. |
| `endsAt` | Running: when it ends. Ringing: when it ended. Absent while paused. |
| `remaining` | Paused only: seconds left. |
| `phase` | Pomodoro only: `focus`, `shortBreak` or `longBreak`. |

**`in`** takes what you'd type or say: `20m`, `90s`, `1h 30m`, `1h30`, `25 min`, `half an hour`, `an hour and a half`, `tea 4m`, `for 10 min`, `in 20 minutes to take the pizza out`, `at 18:30` (or `18.30`), `at 6pm`. Words that aren't part of the length become the title (`title` wins if you send both). Clock times roll forward to their next occurrence, and a number on its own means minutes. Anything unreadable, zero or longer than 24 hours is a `422` with a hint.

**Actions.** `pause` keeps the time left; `resume` counts down from there; `add` adds `seconds` or `in` (default 60), and restarts a ringing timer for just that long; `snooze` rings again in 5 minutes (or `seconds`); `restart` runs the full length again; `stop` removes it. `PATCH /v1/timers` without an id acts on the ringing timer, or else the newest one.

**When a timer ends** it rings: the island opens on Home with Stop, Snooze 5 min and Restart (unless you've hidden the island for the app in front or for fullscreen apps), the chosen sound plays, and the activity turns critical, so it pops up over fullscreen apps too. A timer that ended more than an hour before Islet could ring it (the Mac was asleep or Islet wasn't running) is dropped instead.

**Pomodoro.** 25 minutes of focus, a 5-minute break, and a 15-minute break after every 4th round, moving on by itself. Change the lengths in Settings → Timers, or with the `pomodoro` key in the settings file.
### Approvals (long-poll)

`POST /v1/hooks/{provider}?wait=N` is for blocking agent hooks (`provider` is `claude`, `codex` or `cursor`; `N` is 1 to 3600 seconds). It maps the agent's status like the plain hook endpoint. If the payload asks for a decision (Claude Code `PermissionRequest`, `PreToolUse` for `AskUserQuestion` or `ExitPlanMode`, Codex `PermissionRequest`, Cursor `beforeShellExecution` or `beforeMCPExecution`) and approvals are on, Islet shows a card and holds the request until:

- you answer: `200` with exactly the JSON the hook must print, for example `{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}` for Claude Code and Codex, or `{"permission":"allow"}` for Cursor;
- there is no decision (N seconds or the wait in Settings pass, **Answer in the terminal** is chosen, a later event settles it, the island is hidden for a fullscreen app, or approvals are off): `204` with no body. For Cursor, **Answer in the terminal** is `200` with `{"permission":"ask"}`.

The reply never contains the activity JSON, because hooks print whatever comes back. Events that don't ask for a decision return `204` at once. If the client disconnects, the card is withdrawn. At most 16 requests wait at once; more get `503`. `wait` outside 1 to 3600 is a `400`. The local-network bridge never shows cards.

No endpoint accepts a decision. Answers come only from clicks on the card, so a script holding the token can show a card but can't approve anything. `isletctl hook <agent> --wait N` is the client for this; see [Approvals from the notch](INTEGRATIONS.md#approvals-from-the-notch).

### Local-network bridge (iPhone Shortcuts)

Off by default. When enabled (Settings → Advanced → iPhone bridge), a second listener serves a small part of the API on the local network at port `47832`, advertised over Bonjour as `_islet._tcp` under the name "Islet". It is plain HTTP, so anyone on the same network can read requests, token included. It only takes what a Shortcut needs to put something in the island:

| Route | Limits |
|---|---|
| `GET /v1/health` | No token needed. |
| `POST /v1/notify`, `POST /v1/timer`, `POST /v1/focus` | Priority tops out at `high`. Timer ids get a `lan-` prefix. |
| `POST /v1/activities`, `PUT /v1/activities/{id}` | Ids get a `lan-` prefix (a new id when none is given). `url` and `actions` are dropped. `icon`, `trackerIcon` and `stageSymbols` keep only symbols, emoji and app icons. Priority tops out at `high`. |

Everything else is `403`: the bridge can't read activities or state, remove anything, send agent hooks, or control media, the HUD, keep awake or the island.

The bridge has its own token, shown in Settings → Advanced → iPhone bridge with **Copy** and **New token**, and kept in `~/Library/Application Support/Islet/lan.json` (mode `0600`); `isletctl token --lan` prints it. The local API's token is refused on the bridge, and the bridge's token is refused on the local API. A missing or wrong token gets `401` as soon as the headers arrive, before the body is read. Bodies are limited to 16 KB (`413`). 8 connections are served at once (`503`), at most 2 of them from one client (`429`), and a connection is closed if its headers haven't arrived within 2 seconds. Each client gets 30 requests per 10 seconds (`429`). For both per-client limits, an IPv6 /64 counts as one client. Browser origins are refused. See [iPhone recipes](INTEGRATIONS.md#iphone).

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
isletctl timer <90s|5m|1h 30m|"tea 4m"|"at 18:30"> [--title T] [--id ID]   prints the id
isletctl timer ls                     timers (JSON)
isletctl timer pause|resume|stop|restart|snooze [ID]   no ID: the ringing or newest timer
isletctl timer add [ID] <1m>
isletctl pomodoro [start|stop|toggle] (toggle when left out)
isletctl run [--title T] -- <command…>   mirror a command in the notch; exit code passes through
isletctl hud <volume|brightness|keyboardBrightness> <0-1>
isletctl media <play|pause|playpause|next|previous|forward|rewind|shuffle|repeat>
isletctl media seek <90s|2m|1:30|0>   jump to a place in the track (0: the start)
isletctl awake [15m|1h|2h|on|off|status]   keep the Mac awake (default: until turned off; up to 24h)
isletctl focus <name> [on|off]
isletctl open | close                  (or press ⌃⌥I; change it in Settings → Keyboard shortcuts)
isletctl hook <claude|codex|AGENT> [JSON]   forward an agent hook payload (stdin or last argument)
isletctl statusline [-- <command…>]    Claude Code status line: record plan usage, run your own line
isletctl hook <claude|codex|cursor> --wait N   wait up to N s for an answer in the notch, print it
isletctl state | health | token
isletctl token --lan                  the iPhone bridge's token (not the local API's)
isletctl debug menubar [--watch]      what Islet sees in the menu bar (see LIVE-ACTIVITIES.md)
isletctl mcp                          run as an MCP server on stdio (see MCP.md)
```

`isletctl hook` never fails the calling agent: it exits 0 within ~1.5 s even when Islet isn't running.

With `--wait N`, events that ask for a decision wait up to N seconds for an answer in the notch, and the answer is printed on stdout for the agent. Every failure (Islet not running, API off, no answer) still exits 0 and prints nothing, so the agent asks in the terminal instead. Other events are sent and forgotten as before.

`isletctl token --lan` prints the iPhone bridge's token from `lan.json`, even while Islet isn't running, and says so if the bridge has never been turned on.

`isletctl statusline` is a Claude Code status line command. It reads the JSON Claude passes on stdin and saves the plan limits, model and context use to `~/Library/Application Support/Islet/usage/claude.json` (mode 0600, written only when a figure changes). Then it runs `<command…>` with the same stdin and passes its output and exit code through; if Claude Code stops the status line early, the command is stopped too. A single argument runs with `/bin/sh -c`, which is how Claude stores a command line; several arguments run directly, without a shell. With no command it prints a short line such as `Opus 5.5 · 42% context · 5h 62%`. It never contacts the app or the network, and its own work takes a few milliseconds. See [Usage limits](INTEGRATIONS.md#usage-limits).

`isletctl timer` reads the same phrases as the API's `in`, with one difference: a bare number is seconds (`isletctl timer 300`), as it always was. Quote phrases with spaces: `isletctl timer "in 20 minutes to check the oven"`.

---

## `islet://` URL scheme

```text
islet://notify?title=Build%20done&subtitle=main&icon=sf:hammer&tint=green&ttl=5
islet://activity?id=deploy&title=Deploying&progress=0.4&state=running&priority=high
islet://activity?id=pizza&title=Pizza&endsIn=1200&url=https://…&actionTitle=Track&actionURL=https://…&steps=4&step=2
islet://dismiss?id=deploy
islet://timer?minutes=25&title=Focus
islet://timer?in=20m&title=Pizza          (in= reads "tea%204m", "1h%2030m", "at%2018:30"; a bare number is minutes)
islet://timer?action=pause&id=timer-1     (pause, resume, add, stop, restart, snooze; no id: the ringing or newest timer)
islet://timer?action=add&in=1m
islet://pomodoro?action=start             (start, stop, toggle)
islet://hud?kind=volume&value=0.5
islet://media/playpause     (play, pause, next, previous, forward, rewind, shuffle, repeat)
islet://awake?for=1h        (15m, 2h, 1h30m or a number of minutes; islet://awake alone = until turned off)
islet://awake/off
islet://focus?name=Work&state=on
islet://ask?q=What%20is%20a%20monad&provider=claude
islet://open   islet://close   islet://toggle   islet://settings
```

Any app or web page can open these URLs, and they carry no token, so they are limited:

- Activities they create or dismiss get ids starting with `url-` (`id=deploy` becomes `url-deploy`), so a link can't replace or remove an activity made by Islet, the API or the Live Activity mirror. `source=live-activity` is refused.
- `url` and `actionURL` must be `https`.
- Icons are limited to `sf:`, `emoji:` and `app:`.
- `priority=critical` is treated as `high`.

Use the local API or `isletctl` when you need more.

Siri can open these links through a shortcut: see [Siri and Shortcuts](SHORTCUTS.md).

`islet://ask` fills in the Ask box and never sends; there is no HTTP or `isletctl` equivalent. See [AI.md](AI.md#islet-ask).

---

## Script widgets

Put executables in `~/.config/islet/plugins/`. The file name sets the refresh interval, xbar-style: `cpu.10s.sh`, `prs.5m.py`, `weather.1h.rb` (default 5 minutes; never more often than once a second). Output can be:

1. **xbar/SwiftBar text**: existing plugins work unchanged. The first line is the header, then `---`, then items. Supported parameters: `href=`, `shell=`/`bash=` with `param1=`…, `color=`, `sfimage=`, `refresh=true`, `disabled=true`, and submenus (`--`).
2. **An Islet activity as JSON**: `{"id":"cpu","title":"CPU 42%","progress":0.42}` becomes a live activity.

Scripts get `ISLET=1`, `SWIFTBAR=1`, `XBARDarkMode=true` and Homebrew on `PATH`, and are killed after 15 s.

---

## Settings file

Everything in Settings lives in `~/.config/islet/config.json` (or `$XDG_CONFIG_HOME/islet/config.json`) and reloads live when edited, so it can live in your dotfiles. Unknown keys are ignored and kept; a bad value falls back to its default without breaking the rest, and a file that doesn't parse is never written over (see the end of this section). Example:

```json
{
  "sizePreset": "compact",
  "theme": "black",
  "animationStyle": "fluid",
  "maxConcurrent": 3,
  "hapticsMode": "direct",
  "mutedSources": ["noisy-script"],
  "timerSound": "Glass",
  "pomodoro": { "focusMinutes": 25, "shortBreakMinutes": 5, "longBreakMinutes": 15, "longBreakEvery": 4 },
  "appRules": [
    { "bundleID": "us.zoom.xos", "showInFullscreen": true, "tint": "blue" },
    { "bundleID": "com.valvesoftware.steam", "hideIsland": true }
  ]
}
```

Placement, look and motion keys:

| Key | Default | Meaning |
|---|---|---|
| `hoverToOpen` | `true` | Open the island when the pointer reaches it (after `openDelay`, 0.18 s); `false` opens it on click. |
| `notchlessStyle` | `"pill"` | Displays without a notch: `"pill"` (floating in the menu bar), `"notch"` (a notch shape at the top edge), `"hover"` (nothing until the pointer reaches the top edge) or `"hidden"`. Replaces `showOnNonNotchDisplays`, which is read once: `false` becomes `"hidden"`. |
| `fullscreenBehaviour` | `"hide"` | Over a full screen app: `"show"`, `"hideMusic"` (activities, timers and HUDs stay) or `"hide"` (only HUDs and critical alerts). An app rule's `showInFullscreen` keeps everything. Replaces `hideInFullscreen`, which is read once: `false` becomes `"show"`. |
| `glassLevel` | `0.6` | Glass theme, 0 to 1: towards 0 the black under the notch melts further down and the glass darkens; at 1 the island is glass right from the bottom of the menu bar. |
| `outline` | `false` | A faint edge round the island so it shows on a dark wallpaper. Always drawn, firmer, with Increase Contrast. |
| `glassOnNotchless` | `false` | With the Glass theme, the closed island on a display without a notch is glass too. |
| `animationSpeed` | `"normal"` | `"relaxed"`, `"normal"` or `"quick"`: how long the island's springs and fades take. The playing indicator keeps its own pace. |

An app rule's `tint` is a colour name or any hex value (`"#2F7CF6"`); anything else means the app's own colour. Its `priority` (`"low"`, `"normal"`, `"high"` or `"critical"`) ranks the app's activities and mirrored notifications in place of their own.

Now Playing, closed island, HUD, gestures and battery keys:

| Key | Default | Meaning |
|---|---|---|
| `mediaShowsRemainingTime` | `true` | Time left (rather than the track length) right of the scrubber. Tapping the label switches it. |
| `songChangePeek` | `true` | Show a new song for a moment below the notch when the track changes, for as long as `alertDuration`. |
| `peekOnHover` | `true` | While the island opens on click (`hoverToOpen: false`), resting the pointer on the notch shows what's playing until it leaves. |
| `songProgressRing` | `false` | A thin ring round the artwork beside the notch that fills as the song plays. |
| `meetingReminderMinutes` | `10` | Minutes before a meeting that it shows beside the notch, counting down: `0` (off), `5`, `10`, `15` or `30`. Other values become the nearest. |
| `meetingRemindUntilJoined` | `true` | A meeting that has started stays, glowing, until you join it, dismiss it or it ends. `false`: it goes 5 minutes after the start. |
| `meetingRemindersNeedLink` | `true` | Only meetings with a call link remind you. All-day events, cancelled meetings and declined invitations never do. |
| `pausedMusicTimeout` | `10` | Seconds the closed island keeps paused music before it hides (0–300; `0` = right away, `-1` = never). Replaces `showPausedMedia`, which is read once: `true` becomes `-1`. |
| `visualiserStyle` | `"bars"` | The playing indicator: `"bars"`, `"slim"`, `"dots"`, `"wave"`, `"pulse"`, `"mirror"` (bars reflected round a centre line), `"vinyl"` (the artwork turns like a record), `"gif"` (a sticker, below) or `"off"`. |
| `sticker` | `{"id": "cat"}` | The `"gif"` look's sticker. `id`: `"cat"`, `"jelly"`, `"notes"`, `"record"`, `"star"`, or `"custom-"` and the id of one added in Settings (kept as animated PNGs in `~/Library/Application Support/Islet/stickers`, at most 12). `offsetX` and `offsetY`: points from where it sits, -12 to 12 (positive is right and down; it never leaves the menu bar row). `scale`: 0.6 to 1.6. `whenIdle` (`false`): the sticker stays, still, beside the notch when nothing is playing. An unknown id is the cat. |
| `musicColour` | `"artwork"` | The playing indicator, the progress ring and the open island's progress bar: `"artwork"`, `"accent"` (the artwork's colour while `accentColor` is `"auto"`) or `"white"`. Replaces `visualiserColour`, which is read once. |
| `artworkCornerRadius` | `5` | Artwork corners beside the notch, 0 (square) to 10 (round). The song peek and the open island scale it to their size. |
| `hudEnabled`, `brightnessHUDEnabled` | `false` | The volume and display brightness HUDs. Off in a new setup, since macOS shows its own; a config from before this that leaves them out keeps them on. |
| `keyboardHUDEnabled`, `microphoneHUDEnabled` | `true` | The keyboard brightness HUD (only while `replaceSystemHUD` is on) and the microphone HUD. The keys still work with a HUD off, and the API's `hud` follows the same switches. |
| `hudStyle` | `"compact"` | `"compact"` (in the wings beside the notch) or `"detailed"` (just below the notch, with a percentage). |
| `hudColour` | `"white"` | Every HUD: `"white"`, `"accent"` or `"colourful"` (volume green, brightness yellow, keyboard light blue, microphone orange). |
| `notchWidthAdjust`, `notchHeightAdjust` | `0` | Points added to the notch so the closed island lines up with it: width −20 to +20, height −4 to +4. |
| `gesturesEnabled` | `true` | Two-finger swipes on the island. |
| `swipeDownToOpen`, `swipeUpToClose` | `true` | Open and close by swiping. |
| `swipeMedia` | `true` | Swipe sideways over music. |
| `swipeMediaAction` | `"track"` | `"track"` (next or previous) or `"seek"` (10 s). |
| `swipeCyclesActivities` | `true` | Swipe sideways over a closed activity to show the next one. |
| `reverseSideSwipes` | `false` | Swipe right (rather than left) for the next song or activity. |
| `batteryLowThreshold` | `20` | Low battery warning, 5–50%. |
| `batteryCriticalThreshold` | `10` | Second, urgent warning; always below the low one. |
| `batteryChargedAlert` | `0` | Tell me when charging reaches this level (50–100; `0` = off). |
| `clipboardEnabled` | `false` | Clipboard history. Switching it off forgets everything, pinned items too. |
| `clipboardLimit` | `30` | Items kept, 1–500. Pinned items are never dropped. |
| `clipboardSkipSecrets` | `true` | Skip passwords copied in a browser, where password manager extensions copy as the browser. A copy a Chromium browser says came from a known password manager extension (`org.chromium.source-url`) is always skipped. From another extension's page, text shaped like a password is skipped (one line, no spaces, 8–128 characters, three of lower case, upper case, digits and symbols). From a web page, only text that also looks generated: Safari's strong passwords, or mixed case whose letters don't make words. "Windows11", "COVID-19", UUIDs, links, paths, email addresses and domain names are kept. |
| `clipboardIgnoredApps` | `[]` | Bundle ids whose copies are never kept, beside the password managers that always are. |
| `shelfKeepFor` | `86400` | Seconds a file stays on the shelf before the shelf lets it go (the file itself stays where it is): Settings offers `3600`, `86400`, `604800` and `0` (until you remove it). Other values from 60 to 2592000 (30 days) work too. A config from before this setting keeps `0`. |
| `islandPages` | Home, Today and Shelf in the capsule | The switcher's order: `{"bar": [...], "more": [...], "hidden": [...]}` with page names (`home`, `today`, `shelf`, `widgets`, `clipboard`, `stats`, `shortcuts`, `weather`, `todos`, `note`, `converter`, `emoji`, `mirror`, `teleprompter`, `stocks`, `sales`). At most four pages that are on show in the capsule; `hidden` ones are left out of the switcher. Home is always in the capsule, and pages not named go at the end of the list they come in. |
| `todosEnabled`, `noteEnabled`, `converterEnabled`, `emojiEnabled` | `false` | The To-dos, Note, Converter and Emoji pages under More ([Tools](TOOLS.md)). |
| `systemStatsEnabled` | `false` | The System page under More: CPU and memory, measured only while it is open. |
| `emojiTypes` | `false` | A click on an emoji types it into the app you were typing in instead of copying it. Needs Accessibility. |

The old `hapticFeedback: false` is read as `"hapticsMode": "off"`; use `hapticsMode` from now on.

If `config.json` stops parsing (a missing comma while you edit it), Islet keeps the settings it had and writes nothing over the file until it parses again. If it is already broken when Islet starts, Islet uses the copy of the last version that parsed, which it keeps in `~/Library/Application Support/Islet/config-last-good.json` (outside the config folder, so your dotfiles never see it), or its defaults when there is no copy; Advanced says which. Settings → Advanced says which line has the error and offers **Replace…**, which keeps a copy as `config.json.broken` and writes the settings in use. Keys Islet doesn't know, from a newer version or your own notes, survive a save. Keys that were replaced by newer ones (`hapticFeedback`, `showPausedMedia`, `hideInFullscreen`, `showOnNonNotchDisplays`, `visualiserColour`, `fullscreenAllowList`, `hideForApps`, `launchAtLogin`) are read once and dropped on save.
