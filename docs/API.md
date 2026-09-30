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
islet://ask?q=What%20is%20a%20monad&provider=claude
islet://open   islet://close   islet://toggle   islet://settings
```

`islet://ask` opens the Ask box in the island with the question filled in and the field focused. It **never sends**: you press Return. `q` is optional (up to 4,000 characters). `provider` is optional and picks the provider for this session: `on-device`, `claude` (or `anthropic`), `chatgpt` (or `openai`), `claude-code`, `codex`; an unknown name is an error. There is no HTTP or `isletctl` equivalent, by design: nothing outside the Ask box can spend money on your API keys. See [AI.md](AI.md).

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
