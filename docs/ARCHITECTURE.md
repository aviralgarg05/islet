# Architecture

Islet is a menu bar agent (no Dock icon) built with SwiftPM from four targets: `IsletCore`, `IsletSystem`, the `Islet` app and the `isletctl` CLI.

```
┌──────────────────────────── Islet.app (menu bar agent) ────────────────────────────┐
│                                                                                    │
│  Islet (AppKit + SwiftUI)                                                          │
│   AppModel (@Observable): state, module switches, IsletBackend for the API         │
│   IslandWindowController ×display: IslandPanel (level 27) + TriggerPanel (26)      │
│   PointerCoordinator: hover intent, click-through, drag to shelf, swipes           │
│   TimerController · ApprovalController · AskController · AgentUsageModel           │
│   SalesModel · StocksModel · ToolUsageModel · TeleprompterController · MirrorModel │
│   Views: IslandView → compact / sneak / HUD / bubbles / expanded                   │
│          expanded tabs: Home · Today · Shelf · Widgets · Clipboard · System · Ask  │
│          tools under More: Mirror · Teleprompter · Stocks · Sales                  │
│                                                                                    │
│  IsletSystem (adapters to macOS)                                                   │
│   LocalAPIServer (Network.framework) · SystemNowPlayingBridge (perl helper)        │
│   AppleMusic/Spotify providers · AudioMonitor · AudioOutputs · BatteryMonitor      │
│   BrightnessMonitor · MediaKeyInterceptor · CalendarService · MicUsageMonitor      │
│   CameraMonitor · FullscreenDetector · NotificationMirror (AX) · UnlockMonitor     │
│   DownloadsWatcher · ClipboardMonitor · SystemStatsSampler · ShelfService          │
│   MenuBarInspector · MenuBarLiveActivityMonitor (AX) · ScriptPluginRunner          │
│   UsageWatcher · AskService · KeychainStore · AIAssist · PowerAssertion            │
│   GlobalHotkey · ToolsService (sales, stocks, AI usage) · CameraMirror             │
│                                                                                    │
│  IsletCore (pure Swift, no AppKit, unit-tested)                                    │
│   ActivityCenter · Presenter · MediaArbiter · HoverIntent · NotchGeometry          │
│   MenuBarLayoutEngine · MenuBarLiveActivities · LiveActivityCatalog                │
│   ActivityTemplate · TimerEngine · DurationParser · ApprovalQueue · RiskRules      │
│   Ask providers and stream decoders · SSEParser · AgentUsage · AgentHooks          │
│   HTTP parser + APIRouter · URLCommand · ScriptPlugins · GestureMap · KeepAwake    │
│   CallDetector · NotificationParser · DownloadTracker · SmartIcon · IsletSettings  │
│   SalesAPI · StocksAPI · OpenRouter/Copilot/Ollama usage · TeleprompterPlayback    │
└────────────────────────────────────────────────────────────────────────────────────┘
   ▲ isletctl (CLI, hooks, status line, MCP)   ▲ islet:// URLs
   ▲ HTTP (loopback, optional LAN bridge)      ▲ script widgets
```

## Principles

- **All decisions live in `IsletCore`, and they are pure.** What the island shows, which player wins, when hover opens it, how the closed island fits the menu bar, which icon and template an activity gets, how a hook payload maps to an activity or an approval card, when a timer rings: all are value types with an injected clock, covered by `swift test`. `IsletCore` imports only Foundation and CoreGraphics. The system layer turns macOS events into calls on that core.
- **Event-driven.** Changes arrive as callbacks from macOS. The few timers that do run are listed under [Performance rules](#performance-rules), each with the condition that starts it.
- **Looping motion runs in Core Animation**, so the window server animates it and Islet's process does no per-frame work.
- **Pointer tracking is dormant until needed.** An invisible trigger window over the notch has a tracking area. Global mouse monitors are installed only after the pointer enters it, and removed once the island is closed and the pointer has left. The island panel ignores the mouse except over the parts that are drawn, so clicks beside it reach the menu bar, and with the island open, a click just outside it or beside the page switcher reaches the window underneath (`expandedRect` only delays closing). A peek that opens under the pointer takes no clicks until the pointer has left it (`PeekPointerGuard`), and the monitors stay on until then so the leaving is seen; only a peek's part in the menu bar row arms opening. What keeps the open island open while the pointer is away (pinned, a drag in or out, a slider, any menu, a text field) is one rule, `IslandHold`.
- **Every permission is opt-in.** Islet asks for one only when the user switches on, or asks to use, a feature that needs it. See [Privacy rules](#privacy-rules).
- **Private and undocumented interfaces are isolated and checked before use:**
  - MediaRemote runs in a helper process;
  - DisplayServices and CoreBrightness are loaded with `dlopen` and resolved at run time;
  - Live Activity mirroring depends on how MenuBarAgent builds and labels its menu bar window;
  - Foundation Models (public, macOS 26 and later) is weak-linked, so the same build runs on macOS 14.

  If Apple removes or changes one, that feature turns off and the rest keeps working.

## How events flow

1. A source reports a change: a CoreAudio, CoreMediaIO or IOKit listener, a distributed or Darwin notification, an EventKit change, a file-system event, an Accessibility observer, a local API request, an `islet://` URL or a script widget's output.
2. The `IsletSystem` adapter calls back on the main queue. The API server, Accessibility scans and usage watching do their work on their own queues first.
3. `AppModel` applies the change to an `IsletCore` value (`ActivityCenter.apply`, `MediaArbiter.update`, `BatteryEventDetector.ingest`); `TimerController` does the same with `TimerEngine.perform`. A change to activities, the HUD, Now Playing or a battery event then calls `reschedule()`.
4. `reschedule()` arms **one** timer for the next deadline: the earliest of `ActivityCenter.nextDeadline` (activity expiry and staleness, the sneak peek, the HUD), `MediaArbiter.nextDeadline` (a paused player timing out, a track stuck past its end, or a bare clip from an unknown app that has played long enough to show), `CallDetector.nextDeadline` (an app that has held the microphone long enough to show, or a quiet "Microphone in use" becoming a call), `SongPeek.nextDeadline` (a new song settling, or its peek ending), `MeetingReminders.nextDeadline` (a meeting reminder showing, counting down a minute, starting or going), the next reminder falling due, the next event starting or ending, and the end of a battery event. When it fires, `expireNow()` clears what is due and arms the next one; waking from sleep runs it too, since timers don't count time asleep. With nothing due, no timer exists.
5. SwiftUI observes `AppModel`. `IslandView` asks for `presentation(for:)`, which runs `Presenter.present` on that display's inputs.
6. When the island's silhouette changes, the view posts `isletLayoutChanged`: the trigger windows follow the new shape, and the menu bar is measured if a measurement is due.

Settings follow the same path. The Settings window saves after a quarter of a second without changes, `config.json` is watched for edits made by hand, and `applyModules()` starts or stops each module to match, without a relaunch.

## The island state machine

`Presenter.present(_:)` turns the inputs into one `IslandPresentation`: activities, HUD, sneak peek, now playing, battery event, expanded display, suppression and the activity brought forward by a swipe. The options are:

```
hidden · idle · hud(HUDEvent) · sneak(Activity) · songPeek(NowPlaying) · compact(nowPlaying | activity | battery) · expanded
```

Precedence: suppressed (a full screen app with `fullscreenBehaviour` set to hide everything, or a per-app rule) → only the HUD or a critical sneak peek; expanded; HUD; sneak peek; a new song (`SongPeek`: once it has played for 0.6 s, for `alertDuration`, never the first song after launch or one shown a moment ago), or, while the island opens on click, the song under the resting pointer (`peekOnHover`); the activity brought forward by a sideways swipe (unless a critical one is on top); high-priority activity; battery event; playing media, or media paused a moment ago (`PausedMusic`, for `pausedMusicTimeout` seconds, so the pause is seen); other activities; paused media kept for good (`pausedMusicTimeout` of -1); idle.

Full screen is decided per display, whichever app is in front (`FullscreenCoverage`): a display whose menu bar has gone and whose frontmost ordinary window spanning it has no other app's window in front is in full screen (the same app's small windows in front, such as a browser's "Press Esc" bubble, don't count against it), and that app's rule is the one that counts. With Accessibility, `AXFullScreen` confirms it, each call with a 0.1 s limit since it runs on the main thread; with the menu bar set to hide itself everywhere, only a confirmed window counts. `FullscreenDetector` looks again 0.6 s and 2 s after an app comes to the front or the Space changes. With `fullscreenBehaviour` set to hide music only, the music drops out of every step on that display (its bubble too). On a display without a notch set to show only on hover (`notchlessStyle`), the closed island and its peeks wait until the pointer reaches the top edge (`Presenter.untilHover`); HUDs, critical alerts and the open island don't.

`AppModel.bubbles(for:)` picks up to one fewer than `maxConcurrent` extra items (media or activities) for the detached bubbles, iPhone-style, with an overflow count. The default of 3 gives two bubbles; 1 turns them off. A battery event shows no bubbles.

## Motion

The island moves on one spring family, and its numbers live in `IslandMotion` (IsletCore), so the transitions and the frames on the motion contact sheets come from the same maths. Views reach them through `Motion` in `DesignSystem.swift`.

- **Springs.** Open: response 0.47, damping 0.76, lively with a touch of overshoot. Close: 0.54 and 0.90, landing without a bounce. Settle (0.30, 0.86) for small moves in place, and two quicker ones for a bubble settling and a glyph's bounce. "Animation speed" scales every response, delay and fade (`Motion.pace`).
- **Shape first, content after.** A move to a bigger shape (idle or compact to a peek, anything to the open island) springs the shell open at once; the content fades and scales in from 0.98 0.1 s later, and the page switcher follows 0.06 s after that, its capsule and then its discs rising 6 pt as they fade in (`SwitcherReveal`, `RiseIn`). A move to a smaller shape fades the switcher and the content out in under 0.1 s and closes the shell on the close spring 0.06 s later. `IslandView` tells the two apart by each presentation's rank (`IslandLayout.rank`) and remembers the shape it came from (`ShapeHistory`).
- **Squash and stretch.** Besides the open spring's own overshoot, the shell widens a couple of points on each side as it lands and pulls in a little on the way back (`IslandMotion.stretch`). It never pulls inside the shape it is closing to, so the closed island never ends up narrower or wider than the notch and its wings. A shape that is one width from top to bottom (the closed island, the open island without a stem) stretches as a whole, so the closed island never grows a lip below its row; a stemmed one stretches only its body, so its stem stays the width of the row (`IslandMotion.stretchedStem`). Growing into a shape in the menu bar row (an activity growing out of the notch) it doesn't stretch at all: beside the wings there is only `IslandMotion.rowRoom` (the menu bar's clearance less the hover response) before the nearest menu bar item, and the open spring's own overshoot takes it. The bounce when something new arrives is held to the same room (`IslandMotion.pulseWidthScale`), and the closed island bounces only sideways. The squash is a `KeyframeAnimator` around the shell's surface only, sampled from that function, and plays once per change of presentation.
- **The closed row stays.** Compact, the compact HUD and both peeks are one view (`IslandRow`), so moving between them keeps the row beside the notch in place. A new activity's glyph arrives with one soft bounce, a trailing value of another kind (a waveform becoming a timer) cross-morphs, and a peek's body fades in under the row once the shell has dropped. Symbols change with replace transitions and numbers with numeric text transitions (`AnimationStyle.symbolSwap`, `numberSwap`, timed by `inPlace`).
- **Liquid bubbles.** A bubble buds out of the island's side, or out of the bubble nearer the island, joined to it by a short bridge that stretches, thins and snaps, and settles with a small overshoot; leaving, it is pulled back in. `GooBud` is an animatable transition modifier: while it runs, a Canvas under the bubble draws what it grows from, the bubble and the bridge in black, blurs them and cuts at half opacity (twice, for a crisp edge), so they flow together where they come close. The bubble's own disc and icon ride on top, outside the blur, and the bubbles sit under the island, so the goo seems to come out from under its edge. What the goo grows from is drawn only while the bridge is there, a point inside the island's edges, so the blur's soft edge never shows beside or below it. Beside a glass pill ("Glass on displays without a notch") the goo is cut away under the island (`GooCap.seeThrough`), so it flows out of the glass's edge rather than showing through it. At rest the Canvas is gone. Bubbles still only sit in the menu bar row: none grows taller than the row and the bridge is never thicker than the bubble.
- **Bubbles and the shell.** Bubbles that come or go as the shell changes shape fade instead, because the island's side may not be where they are (the Glass theme's open island has only a notch-wide stem in the row), and new ones wait until a closing shell has closed. Fading bubbles stay where they were while the island grows away from them: an offset cancels the move of their place in the layout, so they never drift over the menu bar. A leaving bubble keeps the transition from the last update it was drawn in, so `IslandView` draws leaving bubbles for one more update wearing the right one (`BubbleHistory`).
- **The silhouette.** `IslandSilhouette` solves the outline for every shape, and every number moves continuously with the shape's parameters. A body a few points wider than the stem leans out in a long S down the side rather than stepping out, and the bottom corners keep their radius while the body is short, so the compact-to-peek morph never shows square "ears" under the row, with or without a notch. A floating pill's round end has no straight side for an S to fit in (squeezed in, it reads as a nub), so while the shape is still mostly a pill its end sweeps out in one convex curve, and the S grows in as the shoulders fill out (`IslandSilhouette.tilt`). Each curve of the side meets the next on the line between their controls, so the side never has a corner.
- **Less motion.** Reduce Motion (the system's or Islet's), the Minimal and Off styles and Low Power Mode get plain short fades, or nothing with Off (`AnimationStyle.effective`): no goo, squash, stagger or bounce, and symbols and numbers swap with a fade instead of morphing or rolling. With Off the page switcher's highlight and the Glass theme's melt don't move either.
- **Nothing runs at rest.** Every transition is a SwiftUI animation that ends. The goo's Canvas and the switcher's stagger are re-evaluated each frame only while their transition runs; no timer, display link or `TimelineView` drives motion.
- **Contact sheets.** `Islet --snapshot-motion <dir>` (`make motion-snapshots`) renders each transition (a bubble splitting and merging, opening, closing, the sneak peek, the song peek, an activity growing out of the notch and going back into it, a glyph morph and the first frames of a peek's shoulders) frozen at 0, 0.15, 0.3, 0.5, 0.7, 0.85 and 1 of its length. Snapshots can't run animations, so `IslandView(frame:)` takes an explicit time and drives the same views and transition modifiers with the progress `IslandMotion` gives for it.

## Menu bar measurement

The closed island always sits in the menu bar row, with a wing either side of the notch; `closedLayout` only sets how wide the wings are. It is `auto` by default, and `wings` always uses the wing width from Settings. (An old `drop` value, which hung a pill below the notch, loads as `auto`.) With `auto`, `IslandWindowController.measureMenuBar()` finds what is beside the notch and `MenuBarLayoutEngine.wingWidth` sizes the wings:

- Both wings take the narrower of the free space on each side, less 6 pt of clearance and capped at the wing width from Settings, so the island stays centred.
- 34 pt or more gives wings with an icon and a short value. Anything less still gives icon-only wings of 26 pt, which may cover the nearest menu bar item in part or in full. An overflow chevron a few points from the notch, for example, sits under the right wing while the island is showing something.
- Without Accessibility nothing can be measured, and the wings are capped at 36 pt, or 26 pt (icon-only) on a display narrower than 1500 pt. A display without a menu bar row gets wings at the width from Settings.
- Width changes under 4 pt are ignored, so a status item that retitles itself doesn't make the wings twitch.
- The room left beyond each wing decides how many bubbles fit in the menu bar row (`AppModel.fittedBubbles`). Bubbles never hang below the row or cover a menu bar item: those that don't fit are counted in the wing instead ("+2"). The menu bar is measured with either width setting, and until it has been, nothing goes beside the island.
- A sneak peek keeps the wings in the row and opens a body below it for a moment. The detailed HUD keeps only a notch-wide stem in the row, with one short line below it.
- While the pointer rests on the closed island it widens 3 pt each side (`NotchGeometry.hoverGrown`), not under Reduce Motion. It never grows downwards, so it doesn't hang below the notch or out of the menu bar row. The open island in the Glass theme has the same stem-and-body shape: a notch-wide black stem in the row, so the menu bar beside the notch stays in view and clickable, and a glass body from the bottom of the menu bar. Right under the stem the black melts a short way into the glass (`GlassMelt`): a fade of under 20 pt at the default glass level, reaching further down only towards Black. An approval card, whose header uses the whole row, keeps the full-width shape.
- On a display without a notch the closed island is a pill inside the row by default (`IslandMetrics.floats`), with bubbles at its height. `IslandShape` draws the pill as the same outline inset from the top edge with rounded top corners, so opening and peeks morph out of it without a jump.

`MenuBarInspector` reads frames only (no titles or values) through Accessibility, off the main thread. On macOS 27 it reads the frontmost app's menus and one MenuBarAgent window, which gives every status item's frame. Items collapsed behind the overflow chevron aren't drawn, so they don't count, but the chevron itself always does. On earlier systems it asks the apps that own status items. That list is built once, rebuilt at the next measurement once it is 15 minutes old and kept current from launch and quit notifications, because asking an app without status items waits for a timeout and wakes it.

A measurement runs only while the island is drawn on that display. Otherwise the controller notes that one is due and measures when the island appears. Triggers: the panels being rebuilt, an app being activated, launched or quit (after 0.35 s), MenuBarAgent's items changing (reported by Live Activity mirroring), and the pointer reaching the island (at most every 2 s, since macOS doesn't always announce hidden items being revealed).

## Now Playing pipeline

```
MediaRemote (any app, browsers) ──perl helper──▶ SystemNowPlayingBridge ─┐
Music.app distributed notification ─────────────▶ AppleMusicProvider ─────┤
Spotify distributed notification ───────────────▶ SpotifyProvider ────────┼─▶ MediaArbiter ─▶ nowPlaying
POST /v1/media (extensions, scripts) ──────────────────────────────────────┘
```

`MediaArbiter` keeps one snapshot per source, so several players can be live at once, one per app (`available`): the bridge's (a Chrome video), Spotify's and Music's own, and one pushed through the API. A player picked in the open island (`pick(player:at:)`) is shown and controlled while it is live, until another player starts playing after the pick or the picked one goes. Commands go to the player on show (`MediaRoute`): through the bridge only when the bridge is reporting that app, since MediaRemote controls whichever app macOS treats as now playing; otherwise Music and Spotify through their own integrations, and nowhere for a player the bridge no longer reports. Without a pick, the rules are: playing beats paused; the most recent wins; direct integrations beat the generic bridge for the same track; missing fields (artwork, duration, position, shuffle and repeat) are filled from any source describing the same track; paused sources expire after 15 minutes, on time rather than at the next media update; a track that still says it is playing 5 s past its end (browsers often never report that a video finished) shows as stopped and goes 2 minutes after its end; each report from the system bridge replaces everything the bridge said before, browser videos included, so closing a browser window clears its video; sources switched off in Settings (`disabledMediaSources`) are ignored. Music and Spotify count as themselves when the bridge reports them, so switching one off hides it whichever path reports it, and switching off "Other apps" doesn't hide them.

macOS 15.4 and later refuse MediaRemote to non-Apple processes, so the helper (`Helpers/MediaRemoteBridge`) is a small Objective-C dylib that `/usr/bin/perl`, an Apple platform binary, loads. Release builds load only the copy inside their own bundle. The helper streams JSON lines, takes `get`, `cmd N`, `seek S`, `shuffle N` and `repeat N` on stdin, and exits when the pipe closes. If it exits, it is restarted after a growing delay. If it keeps exiting within a minute of starting, the bridge gives up after five restarts (`HelperRestarts`) until the user presses **Try again** on the Now Playing page or the Mac wakes, and meanwhile the Music and Spotify providers fetch artwork and position themselves (AppleScript, and Spotify's oEmbed endpoint for cover art). They send Apple Events to a player only once macOS reports Automation for it as allowed; see [Privacy rules](#privacy-rules).

## Live Activity mirroring

`MenuBarLiveActivityMonitor` shows the Live Activities macOS puts in the menu bar (from the iPhone, and Mac ones such as Shortcuts) as island activities, each app with its own source (`live-activity:uber`), so muting one app leaves the others. It needs Accessibility, and only starts once that has been granted.

- It reads MenuBarAgent's menu bar window through `MenuBarAgentScanner`, including activities collapsed into the overflow. Only MenuBarAgent's own items and the Live Activity renderer's content are read. Other apps' items are recorded by frame and bundle ID and never walked into.
- `MenuBarLiveActivities` recognises an activity by MenuBarAgent's own labels, read in every language from its `MenuBarCore.loctable`, and treats `com.apple.menuextra.*` items (battery, Now Playing and the like) as system items. `LiveActivityCatalog` supplies the app's icon, tint and template.
- It wakes on the Darwin notifications posted when a Live Activity record changes, on MenuBarAgent's items appearing, disappearing or moving, and on changes to each mirrored item's own element. Scans run on a utility queue. While at least one activity is mirrored, a safety rescan runs every 15 s in case a change wasn't announced.
- `LiveActivityClock` works out from two readings whether a clock counts down or up, so Islet animates it itself instead of reading the menu bar every second.
- `MirrorTracker` keeps an item dismissed in the island hidden until it leaves the menu bar, and dims one whose text hasn't changed for 30 minutes (`staleAt`).
- Clicking a mirrored activity presses the original item (revealing the overflow first when needed). No URL or API can trigger that press.
- Mirrored activities are left out of API responses unless `shareMirroredActivities` is on. What is read stays in memory.

See [LIVE-ACTIVITIES.md](LIVE-ACTIVITIES.md).

## Templates

An activity's template sets what its wings, bubble, sneak peek and expanded row show: `eta`, `stages`, `flight`, `route`, `score`, `timer`, `workout`, `gauge`, `live-audio`, `media`, `agent` or `progress`. `Activity.resolvedTemplate` uses the one sent; otherwise the catalogue's template for the activity's source, when the activity carries the data it needs (`fits`); otherwise one inferred from the fields present.

- `LiveActivityCatalog` holds 137 apps, generated from `docs/research/07-live-activity-apps.json` by `scripts/gen-live-activity-apps.py`.
- `RGBA.readableOnBlack` (`Contrast.swift`) lifts dark brand tints until they reach 3:1 contrast against the island's black.
- `TemplateLimits` sets each field's maximum length, and `ActivityCenter.apply` refuses longer values, which the island would cut off.
- Time-based text redraws only when it can change (`templateRefresh`): every second for clocks, once a minute (aligned to the deadline) for minute counts, otherwise never.
- Countdown rings, call waveforms and the breathing stage capsule are Core Animation layers (`TemplateLayers.swift`).

Field reference: [API.md](API.md#templates).

## Timers

`TimerEngine` (`IsletCore`) holds every timer and the Pomodoro cycle as one value with an injected clock. `TimerController` keeps one, saves it to `timers.json` in the support folder after every change, and shows each timer as an activity from the `timer` source.

- It arms a single wall-clock wake-up for the soonest end, so a Mac that sleeps through the end still rings on wake. With no running timer nothing is scheduled.
- At launch it restores saved timers and catches up. A timer that ended more than an hour before Islet could ring it is dropped instead.
- A ringing timer plays `timerSound`, opens the island on Home (unless the island is hidden for the app in front or a fullscreen app) and becomes a critical activity with Stop, Snooze 5 min and Restart.
- Dismissing a timer's activity stops the timer. There can be 20 timers, of up to 24 hours each.
- `DurationParser` reads lengths such as "tea 4m", "1h 30m" and "at 18:30" for the island, the API, `islet://timer`, `isletctl timer` and the MCP `start_timer` tool.

## Approvals (long-poll)

Coding agents can ask for permission, ask a question or present a plan as a card in the notch: Claude Code `PermissionRequest` and `PreToolUse` for `AskUserQuestion` and `ExitPlanMode`, Codex `PermissionRequest`, and Cursor `beforeShellExecution` and `beforeMCPExecution`.

1. `isletctl hook <agent> --wait N` adds where the agent runs (terminal, tmux or WezTerm pane) and posts the hook's payload to `POST /v1/hooks/{agent}?wait=N`. Events that don't ask for a decision are sent without `wait`, with a 1.5 s timeout.
2. `APIRouter` maps the status as usual. If `ApprovalRequest.parse` finds a decision to make, the request is held. `LocalAPIServer`'s 5 s timeout applies only until a request has arrived, so a held request stays open.
3. `ApprovalController` parks the request, queues a card, and shows it a quarter of a second later, so the terminal can print its own prompt first. It opens and pins the island. Clicks in the first half second after a card appears are ignored, so a double-click can't answer a card nobody has seen.
4. The wait ends when the user answers, after N seconds or the wait in Settings (`approvalWait`, 300 s by default), whichever is shorter, when a later hook event settles the card (answered in the terminal, tool ran, turn ended), or when the client hangs up. If the island is hidden (a fullscreen app or a per-app rule), requests go back to the terminal at once.
5. The reply is `200` with exactly the JSON the hook prints (`ApprovalOutput`), or `204` for no decision, in which case `isletctl` prints nothing and the agent asks in the terminal.

No endpoint accepts a decision: answers come only from clicks on the card. `RiskRules` add friction to risky calls (a second click or a hold, no "Always") without blocking them. **Terminal** brings the agent's terminal forward, activating only apps that are already running and driving tmux and WezTerm with fixed arguments. Nothing polls while cards wait: each has one expiry work item. The LAN bridge never takes part. See [INTEGRATIONS.md](INTEGRATIONS.md#approvals-from-the-notch).

## Ask

The Ask box (the Ask tab of the expanded island) sends a question to one of five providers: Apple's on-device model, Claude or ChatGPT with the user's API key, or the local `claude` and `codex` CLIs with the user's existing login.

- `AskController` (app) holds the draft, the streaming answer and, when follow-ups are on (off by default), the last six turns, in memory only. It batches streamed text so the island redraws at most 20 times a second.
- `AskService` (`IsletSystem`) runs the request. Nothing runs until a question is asked, and nothing is logged.
  - API providers use an ephemeral `URLSession` with no cache, cookies or credential store, created on first use. It talks only to `api.anthropic.com` and `api.openai.com` over HTTPS and refuses redirects, so the key header never follows one. OpenAI requests set `store` to false. Answers stream as Server-Sent Events through `SSEParser` and a decoder per provider.
  - CLIs run from an argument array (no shell), in an empty working folder (`ask/` in the support folder, so no project settings, MCP config or CLAUDE.md load), with a minimal environment, stdin closed and output capped at 256 KB. Stopping sends SIGTERM, then SIGKILL.
  - On-device answers use Foundation Models when Apple Intelligence is ready.
- API keys live in the login Keychain (service `dev.islet.Islet.ai`), never in `config.json`, logs or child processes.
- Timeouts: 30 s between bytes from an API, 120 s for a whole answer.
- The island panel takes the keyboard only while the Ask field is in use. It never activates Islet, so focus returns to the app you were in.
- The Ask shortcut (`ctrl+option+a` by default) only opens the box, and `islet://ask` fills in the question without sending it. The local API can't ask anything.

See [AI.md](AI.md).

## MCP

`isletctl mcp` is a Model Context Protocol server on stdio, started by the agent or chat app that uses it. It runs in the `isletctl` process, outside the app. It speaks JSON-RPC 2.0, one message per line, and offers six tools (`notify`, `show_progress`, `finish`, `dismiss`, `start_timer`, `list_activities`). Each tool call becomes a local API request, with the port and token from the discovery file. Activities it creates get ids starting with `mcp-`, so a tool can't replace Islet's own, and a `show_progress` task dims after 15 minutes without an update. See [MCP.md](MCP.md).

## Usage limits

Claude Code and Codex plan usage come from local files. Nothing polls and nothing goes over the network.

- **Claude Code.** Settings → Coding agents → Usage limits → **Show Usage…** sets `isletctl statusline` as Claude Code's status line, wrapping any existing one. On each update it writes the plan usage Claude passes on stdin to `usage/claude.json` in the support folder (mode 0600, in a 0700 folder), only when a figure changed, then runs the user's own status line. `UsageWatcher` follows the file with vnode sources on the file and its folder.
- **Codex.** An FSEvents stream on `~/.codex/sessions` (5 s latency), set up only if that folder exists. On each event only the last 64 KB of the newest `rollout-*.jsonl` is read.

`AgentUsageModel` shows the figures on the Home tab. It posts one activity when a window first crosses 90%, and a high-priority one at 100% (`UsageAlertTracker`). The first reading after launch only sets the baseline, so relaunching doesn't repeat an alert. Both sources are on by default (`claudeUsageEnabled`, `codexUsageEnabled`).

`ToolUsageModel` adds OpenRouter (the user's key, `GET /api/v1/key`), Copilot (a GitHub key with Plan read access, this month's premium request usage) and Ollama (`/api/ps` on 127.0.0.1) to Home, each off by default. They are asked for only when the island opens and the figures are older than the source allows (`ToolUsageSource.freshFor`), so nothing polls. See [Integrations](INTEGRATIONS.md#openrouter-copilot-and-ollama).

## Tools

The Mirror, Teleprompter, Stocks and Sales pages (`AppModel+Tools.swift`) start off and are listed under More once on (`IslandPage.switcher`). `syncToolPages()` runs when the island opens or closes, the page changes or settings change, and starts only what the page on show needs:

- **Mirror.** `CameraMirror` (IsletSystem) owns an `AVCaptureSession` with the default camera, made the first time the page shows. It runs only while the Mirror page is open, and stops while the screen is locked or asleep (`MirrorModel` watches both only while the page shows); the preview is an `AVCaptureVideoPreviewLayer`, so frames never reach Islet's code.
- **Teleprompter.** `TeleprompterPlayback` (IsletCore) keeps the position as an anchor and a start time, so pausing reads exactly where the text had got to. The page hands the rest of the way to one linear SwiftUI animation, and the deadline timer stops it at the end (`endsAt`). An up-and-down scroll over a script goes to the teleprompter before the swipe recogniser (`IslandHostingView.onScroll`, `Teleprompter.scrollDistance`); a sideways one, or any on the empty page, stays a swipe. The script is `teleprompter.txt` (0600) in the support folder.
- **Stocks.** `StocksSchedule`: on opening the page if the prices are a minute old, then every two minutes, only while the page is open.
- **Sales.** `SalesSchedule`: every 15 minutes while Sales is on, a store is connected, the screen is unlocked (an `UnlockMonitor` runs only then) and Low Power Mode is off (its change moves the deadline); at midnight, so "Today" turns over; and on opening the page if the figures are a minute old. `SalesAPI` builds each store's request for today and reads its replies, page by page (at most ten).

Each model reports its next moment to `AppModel.reschedule()`, which keeps the one deadline timer. `ToolsService` sends every request: an ephemeral `URLSession` made on first use, no cookies, cache or credential store, HTTPS only to the hosts the tool names (or HTTP to Ollama on 127.0.0.1), redirects refused, and replies read as they arrive and dropped past 8 MB.

## Local API security

- Loopback bind, on port 47831 by default. If that port is taken, an ephemeral one, which clients read from the discovery file.
- Bearer token (`Authorization: Bearer …` or `X-Islet-Token`) in a `0600` discovery file (`api.json` in the support folder), reused across launches and removed on quit. The health check (`GET /v1/health`) is the only request that works without it.
- Constant-time token comparison.
- `Host` must be localhost (DNS-rebinding defence) and web-page `Origin`s are refused (CSRF). Browser-extension origins and `Origin: null` are allowed, still with the token.
- 16 KB header limit and 1 MB body limit; chunked bodies are refused. A connection that hasn't delivered a whole request within 5 s is dropped.
- At most 16 long-polls (`?wait=`) are held at once; more get `503`.
- A wrong token, a refused route or an oversized `Content-Length` is answered as soon as the headers arrive, before the body is read. The server then reads and drops what is left of the declared body, for 5 s at most, before closing: closing with data unread resets the connection, and a client still uploading (URLSession) would lose the answer. These connections still count against the connection limits, and at most 16 drain at once.
- The LAN bridge (off by default, port 47832, advertised over Bonjour as `_islet._tcp` under the name "Islet") is a second listener with its own token (`lan.json`, `0600`). The API token is refused there, and the bridge token is refused on loopback. It uses the router's `.lan` scope: any `Host`, but only notify, timer, Focus and simple activities (no links or buttons, no file or remote icons, ids under `lan-`, priority at most high); everything else gets `403`. It limits each client to 30 requests per 10 s and 2 open connections (IPv6 clients per /64), bodies to 16 KB and connections to 8, closes connections whose headers haven't arrived within 2 s, and never takes part in approvals.
- `islet://` URLs need no token, so they can do less: their activities get ids starting with `url-`, links must be https, icons are symbols, emoji or app icons, and priority tops out at high.

## Performance rules

`CONTRIBUTING.md` asks every change to avoid polling while idle, use Core Animation for looping motion and stay within the `make perf` budgets.

- **No polling while idle.** Changes arrive from CoreAudio, CoreMediaIO and IOKit listeners, EventKit, distributed and Darwin notifications, file-system events (vnode sources and FSEvents) and Accessibility observers.
- **One deadline timer** for time-based island state (see [How events flow](#how-events-flow)). The timers engine and keep awake each arm one timer for their own end, and each approval card has one expiry.
- **The timers that repeat run only while their feature needs them:**

  | What | How often | Only while |
  |---|---|---|
  | Clipboard history | reads `NSPasteboard.changeCount` once a second (macOS has no change notification) | clipboard history is on and the screen is unlocked with the displays awake |
  | Downloads | once a second while a partial file grows (file growth doesn't change the folder), every 30 s after 15 s without growth, and stops after 10 quiet minutes | a partial download is in the folder |
  | System stats | every 2 s | the System tab is open |
  | Sales | every 15 minutes, through the deadline timer | Sales is on with a store connected, the screen is unlocked and Low Power Mode is off |
  | Stocks | every 2 minutes, through the deadline timer | the Stocks page is open |
  | Script widgets | each script's interval from its file name (5 minutes by default), with a 15 s timeout | widgets are on and the screen is unlocked with the displays awake |
  | Live Activity mirroring | a safety rescan every 15 s | at least one activity is mirrored |
  | Hover intent | every 50 ms | an open or close decision is pending |
  | Clock text | SwiftUI `TimelineView`: every second for clocks, every minute for minute counts | the text is on screen |

- **Transitions end.** Opening, closing, peeks, bubbles and glyph swaps are one-shot SwiftUI animations (see [Motion](#motion)); once they finish nothing is left running.
- **Looping motion is Core Animation.** The equaliser, spinners, countdown rings, call waveforms, the breathing stage capsule and the urgent glow are layer animations, which the window server runs. SwiftUI's `repeatForever` and `symbolEffect` redraw the view every frame, so they aren't used for these. The equaliser, spinner and glow run at 30 fps at most. The glow pulses six times, then stays steady. Content that has gone stale stops its looping motion.
- **Nothing slow runs on the main thread.** Notification Center is read on a utility queue with a 0.25 s limit per Accessibility call, and each banner is mirrored once (`BannerDeduper`), remembered only once its words could be read, so one caught while Notification Center was still filling it in is read again at the next look. Shelf files on another disk or a share are checked in the background, and dimmed if their volume doesn't answer within 2 s.
- **In the background session** (fast user switching) nothing reads the menu bar, banners or keys, and the pointer isn't followed (`SessionWork`). After sleep the panels are made again once the displays settle (`DisplayPolicy`), and the key tap and shortcuts are set up afresh. Accessibility granted or taken away while Islet runs starts or stops what uses it at once.
- **The menu bar is measured only while the island is drawn** on that display, and off the main thread. Live Activity mirroring reads it only when a notification or Accessibility event says something changed, apart from its safety rescan.
- **Budgets.** `make perf` measures CPU in seven island states: at most 0.5% idle, 1.5% in each compact state and 3% expanded with Now Playing. `make e2e` checks idle CPU under 1% and memory under 150 MB.

## Privacy rules

- **Permissions only for features the user switches on or asks to use.** Calendar and Reminders access is requested from Settings or the Allow buttons on the Today tab. macOS asks only once: after a refusal, or with "Add events only", those buttons open Privacy & Security at the right page instead, and Islet reads the access again when it becomes active (back from System Settings), when the island opens while the calendar can't be read, and for `GET /v1/state`, starting the calendar with a fresh event store the moment access arrives. Accessibility is requested when the user switches on replacing the system HUD, or presses an Allow or Grant button in Settings. If the HUD option is on at launch but Accessibility has been taken away, Islet doesn't ask again: it leaves the volume and brightness keys to macOS and Settings shows the missing permission. Notification mirroring, menu bar measurement and Live Activity mirroring use it only once it has been granted. Automation (AppleScript to Music and Spotify) is used only when the MediaRemote bridge isn't running or is reporting another player (a Spotify song picked in the island while a Chrome video is the system's now playing), and only once it has been granted: Islet checks without prompting (`AEDeterminePermissionToAutomateTarget`, off the main thread, never launching the player) once per player per launch, and again when that player opens or comes to the front, or one of its controls is pressed in the island, while macOS has no lasting answer. The prompt itself comes only from Allow in Settings → Permissions. macOS asks for Downloads folder access the first time the downloads module reads the folder.
- **Off by default:** clipboard history, download progress, notification mirroring, script widgets, the LAN bridge, replacing the system HUD, reminders, the camera mirror, the teleprompter, stocks, sales, and OpenRouter, Copilot and Ollama usage. The camera is asked for only from the Mirror page's **Allow camera** or Settings → Permissions, and runs only while that page is open.
- **Accessibility reads are narrow and stay in memory.** Menu bar measurement reads frames only. Live Activity mirroring reads only MenuBarAgent's items and the renderer's content. Notification mirroring reads the text a banner shows and ignores the Notification Center panel. None of it is written to disk or logs.
- **Clipboard history** lives in memory. It skips content marked concealed, transient or auto-generated (the nspasteboard.org conventions), copies from password managers and from apps the user lists (`clipboardIgnoredApps`), and, with `clipboardSkipSecrets` (on by default), one-line text that looks like a password when a browser copied it, since password manager extensions copy as the browser. Switching it off forgets everything, pinned items too. When Islet copies the API token, it marks it concealed and keeps it off Universal Clipboard.
- **On disk:** `config.json` in `~/.config/islet` (or `$XDG_CONFIG_HOME/islet`), and `api.json` (0600), `shelf.json`, `timers.json`, `usage/claude.json` (0600) and `teleprompter.txt` (0600) in `~/Library/Application Support/Islet`. API, store, OpenRouter and GitHub keys are in the Keychain (service `dev.islet.Islet.ai`).
- **Files are never lost to a parse error.** `SettingsFile` (`IsletCore`) reads `config.json` as loaded, missing or unreadable (with the line). Unreadable keeps the settings in use and refuses every save until the file parses or the user chooses Replace in Advanced, which keeps a copy as `config.json.broken`. Each file that parses (read or saved) is also copied to `config-last-good.json` in the support folder, so a file already broken at launch starts from that copy (`SettingsFile.open()`) instead of the defaults. Saving merges into the file, so keys this build doesn't know survive. An unreadable `shelf.json` or `timers.json` is moved to `<name>.corrupt` before the store starts empty (`JSONStore.start`); if it can't be moved, the store doesn't save that session. Shelf items on a volume that isn't mounted stay, dimmed, instead of being pruned.
- **What leaves the Mac:** an Ask question sent to a cloud provider, directly or through its CLI, and a model-list request when a key is saved or the list is refreshed; images given to Islet as URLs (activity icons, artwork); and Spotify cover art from `open.spotify.com` when the MediaRemote bridge isn't running. Once turned on: today's sales from the stores the user connects, stock prices from Yahoo Finance while the Stocks page is open, and usage from OpenRouter and GitHub with the keys the user pasted. Islet never reads another app's sign-in tokens. Smart icons and notification summaries use the on-device model or nothing.
- **Script widgets run only if trusted:** the user must own the script and its folder, and nobody else may be able to write to them. The first time in a session that a widget's menu item would run a command, Islet shows the command and asks.
- **Hide from screenshots** (`hideFromScreenCapture`, off by default) sets the island panel's `sharingType` to `.none`, which keeps it out of screenshots. ScreenCaptureKit is reported to ignore `sharingType` from macOS 15, so some screen-sharing and recording apps may still show the island, and Settings says so; this hasn't been checked on macOS 26 or 27. While it is on, glass surfaces draw their solid fill, because a window kept out of captures can lose the backdrop Liquid Glass samples and draw it black.

## Build and packaging

- SwiftPM only; the Command Line Tools are enough.
- `scripts/bundle.sh` (`make app`):
  1. builds the release products;
  2. compiles the helper for `arm64e`, `arm64` and `x86_64`;
  3. assembles `Islet.app` (Info.plist, icon, helper, CLI, API docs), taking the version from the newest `CHANGELOG.md` heading;
  4. signs the app and CLI with the hardened runtime. Locally that's ad-hoc with an identifier-based designated requirement, so privacy grants survive rebuilds. With `SIGN_IDENTITY` set it signs with that Developer ID identity and a timestamp.
- `scripts/release.sh` (`make release`) zips the app and writes its SHA-256 and release notes; `PUBLISH=1` also pushes and creates the GitHub release.
- Two quirks of the CLT toolchain on the macOS 27 SDK:
  - `@State` is a macro whose plugin only ships with Xcode, so views use the property-wrapper type via `typealias ViewState = SwiftUICore.State`.
  - swift-testing's macro plugin needs `-plugin-path` (the Makefile passes it).
- It builds with the macOS 26 SDK too (Xcode 26 and Swift 6.3, as on GitHub's runners). APIs only the macOS 27 SDK has sit behind `#if compiler(>=6.4) && canImport(FoundationModels, _version: 2.0)`: FoundationModels is version 2 in the macOS 27 SDK and 1.5 in 26.5. Today that is the on-device model's `LanguageModelError` in `OnDeviceAsk.swift`; a macOS 26 SDK build reads those errors from their description instead.

## Tests

| Layer | How |
|---|---|
| Core logic | `make test`: presenter, motion (springs, stagger, squash, the bubbles' bridge, the silhouette's continuity), activity centre, arbiter (hidden apps, bare clips, the newest position), full screen per display, call settling, banner de-duplication, mirrored Live Activity dismissals and staleness, peek and hold rules, session, wake and permission decisions, hover intent, gestures, keep awake, HTTP parser, router (auth, CSRF, rebinding), URL scheme, hooks and approvals, risk rules, templates and catalogue, timers and durations, menu bar layout and Live Activity recognition, Ask decoders, usage parsing (Claude, Codex, OpenRouter, Copilot, Ollama), status line setup, settings, calls, notifications, downloads, smart icons, sales requests and replies for seven stores, stock quotes and sparklines, teleprompter pace and position, tool refresh schedules |
| System adapters | `make test`: real sockets (API server, held long-polls, LAN rate limit, LAN token, early 401, body and connection limits, malformed requests), IOKit/Music/Spotify/MediaRemote parsers, script runner (output, exit codes, timeouts), Safari/Chrome partial downloads, shelf persistence, discovery-file permissions, Ask service with fake transports and CLIs, tools service with fake transports (pages, host limits, refused redirects, offline), Keychain queries, usage file watching, hook installer, menu bar inspector |
| End to end | `make e2e`: launches the real app with isolated config and port; drives the CLI, HTTP, URL scheme, agent and zsh hooks, plugins, MCP and the LAN bridge; checks window level and placement, single instance, clean shutdown, idle CPU and memory. `make e2e-media` adds the MediaRemote bridge, which skips itself if something is playing. |
| Performance | `make perf`: CPU in seven island states against the budgets above |
| Visual | `make snapshots`: renders every island state to PNG offline, with sample content and a scratch config. `make motion-snapshots`: renders each transition as a contact sheet of frames frozen part of the way through. `make settings-snapshots`: renders every Settings page in light and dark, and a page of search results, in a child process whose home folder is temporary |
