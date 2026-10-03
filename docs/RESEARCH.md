# Research: what Islet had to work out

*Snapshot: 30 September 2026, with the macOS 27 findings re-checked for 0.3.*

This is the reasoning behind Islet's design: what macOS actually does, what it refuses to do, and what that
left Islet to build. The measurements marked [local] were taken on a 14" MacBook Pro running macOS 27.0.1;
everything else cites a public source. Current performance figures live in [CHANGELOG.md](../CHANGELOG.md),
measured per release rather than quoted here.

## 2. What goes wrong in notch apps, and what Islet does

| # | What goes wrong in a notch app | What Islet does |
|---|---|---|
| 1 | **Now Playing keeps breaking** | Four layers: MediaRemote bridge (own clean-room helper, verified on macOS 27) → Music/Spotify distributed notifications → AppleScript enrichment → `POST /v1/media` push. An end-to-end test drives a fake player through the bridge. |
| 2 | **CPU, battery, memory drain** | Event-driven everything; one deadline timer instead of polling; perpetual animations run in Core Animation; the pointer is tracked by a trigger window, not a global mouse monitor. **Measured: 0.0% idle, 0.0% with music animating, ≤0.6% with a live countdown, 65–85 MB.** `scripts/perf.sh` enforces budgets. |
| 3 | **Abandonment, licensing, subscriptions** | MIT licence, clean-room code (no GPL reuse), no accounts, no licence server, config in a plain JSON file. |
| 4 | **Fullscreen and accidental opening** | Fullscreen detection (window list + menu-bar presence, notch-aware); hover needs a short dwell *and* slow pointer; per-app "hide" and "show in fullscreen" rules; critical items still break through. |
| 5 | **Multi-monitor, clamshell, notch geometry** | Geometry from `auxiliaryTopLeft/RightArea`; synthetic pill on notchless screens; panels rebuilt (debounced) on display, wake and Space changes; display modes: notched / main / all. |
| 6 | **HUD replacement conflicts** | Default is observe, don't hijack: CoreAudio volume listener and an event-driven brightness callback, no permission. Replacing the system HUD is an explicit opt-in. |
| 7 | **Sleep/wake instability** | Rebuild on wake; single-instance guard; discovery file owned per process. |
| 8 | **Trust and permission friction** | Nothing is requested at launch. Every permission is opt-in from Settings, with a sentence on why. Local build is signed with a stable identity so grants survive rebuilds. |
| 9 | **Janky animations, bloat** | Five motion styles including Minimal and Off, Reduce Motion honoured, every "wow" has an off switch; modules toggle individually. |
| 10 | **Menu-bar overlap** | Idle island is invisible (the hardware notch is already there). With Accessibility, Islet measures the menu bar and sizes the wings to the free space, down to icon-only wings that stay in the menu bar row; without it, the wings are capped at 36 pt. Only drawn pixels take clicks (section 8). |
| 11–12 | Shelf and calendar bugs | Bookmarked shelf items survive renames; all-day events never raise alerts. |

## 3. What people ask for most

1. **Notifications in the notch**: the top open request. → *Built:* mirroring from every app (including iPhone notifications macOS forwards), opt-in, experimental, with per-app mute, tint and priority, and optional on-device one-line summaries.
2. **Now Playing from any app** → *Built* (see #1 above).
3. **Per-display and per-context visibility** → *Built:* display modes, fullscreen rules, per-app rules.
4. **Animation control** → *Built:* Fluid / Snappy / Smooth / Minimal / Off.
5. **Size control** → *Built:* Compact (default) / Standard / Large / Custom presets.
6. **AI coding-agent status** → *Built:* Claude Code, Codex and a generic agent protocol; "waiting for you" is high priority with a glow; segmented plan steps.
7. **AirPods/headphones and output switching** → *Built:* output-device card on connect (no Bluetooth permission needed). *Not built:* per-bud battery (private keys, Bluetooth permission).
8. Lyrics, more calendar providers, better shelf, external-display brightness, Caffeine, Pomodoro, lock-screen widgets → lyrics, the shelf, keep awake and the Pomodoro are built; the rest are roadmap or script-widget territory.

## 4. The iPhone Dynamic Island, and what carries over

Apple's model has four presentations, reused unchanged for CarPlay, the Watch Smart Stack and the Mac menu bar:
- **compact:** leading and trailing views around the camera;
- **minimal:** one attached view plus a detached circle when several activities run;
- **expanded:** on long-press or briefly for an alert;
- **Lock Screen card.**

Islet adopts the same contract so it feels familiar and could bridge to a Mac ActivityKit if Apple ships one:

| iPhone concept | Islet |
|---|---|
| Compact leading + trailing | Wings beside the notch |
| Minimal + detached bubble, up to 3 on iPhone 18 Pro | Up to 3 at once: island + 2 bubbles, "+N" overflow, left or right placement |
| Expanded on long-press / alert | Hover or click to expand; new activities "sneak" open for a configurable 1–6 s |
| ActivityKit relevance, stale date, deep link | `relevance`, `staleAt` (dims), `url` (click opens) |
| Timers, stopwatches, calls | `endsAt` countdowns, `startedAt` count-ups, automatic call timer (FaceTime, Zoom, Teams, Slack, Discord, Meet-in-browser…) |
| System splashes (charging, low battery, Focus, silent) | Charging and low-battery (with Battery Settings button), Low Power Mode, output device, volume/brightness HUD, Focus pill, "Welcome back" digest on unlock, download finished |
| Spring morphing, blur-crossfade, numeric text | One spring family (open 0.47 s at 0.76 damping, close 0.54 s at 0.90), scaled by Animation speed, blur-replace transitions, numeric-text countdowns, arrival bounce |
| Haptics | Trackpad haptics for direct actions only by default (open, press, drop); optional for important alerts |

**No API exposes the iPhone's Live Activities on the Mac.** ActivityKit is marked unavailable on macOS. macOS 26 and later show them in the menu bar, though, and since 0.2 Islet mirrors whatever MenuBarAgent draws there through Accessibility (section 8). It also covers the iPhone in two other ways:
- It mirrors the iPhone notifications macOS forwards.
- It accepts events from **iPhone Shortcuts automations** (alarm, Focus, arrive/leave, battery level) over an opt-in, token-protected local-network bridge.

## 5. Feasibility decisions

| Integration | Approach | Permission | Grade |
|---|---|---|---|
| Notch geometry | `safeAreaInsets` + auxiliary areas (185×32 pt on 14") | none | A |
| Window | Non-activating panel at level `mainMenu+3`, all Spaces, fullscreen-auxiliary | none | A |
| Now Playing (any app) | Own Objective-C helper loaded into `/usr/bin/perl` (Apple-signed), JSON over a pipe; commands via stdin | none | B (Apple could close it) |
| Music / Spotify | Distributed notifications; AppleScript only for extras; Spotify art via oEmbed | Automation (only if needed) | A |
| Volume | CoreAudio property listeners | none | A |
| Brightness | `DisplayServicesRegisterForBrightnessChangeNotifications`: **verified** it delivers `{value}` on macOS 27; auto-brightness filtered out | none | C (private) |
| Battery | IOKit power-source notifications | none | A |
| Calendar | EventKit full access; meeting links detected in URL, location and notes | Calendars | A |
| Calls | CoreAudio per-process objects (`kAudioProcessPropertyIsRunningInput`): **verified** readable | none | A |
| Camera / mic in use | CoreMediaIO / CoreAudio "running somewhere" | none | A |
| Notifications | Accessibility observer on Notification Center banners | Accessibility | C |
| Downloads | Folder watcher; Safari `.download` Info.plist has real progress | Downloads folder | B |
| Focus | Shortcuts automation → `islet://focus` (no public read API) | none | B |
| On-device AI | Foundation Models (`LanguageModelSession`), weak-linked; plain prompts (the `@Generable` macro needs Xcode) | Apple Intelligence | B (model reported `modelNotReady` on this Mac, so fallback rules are the default) |
| Fullscreen | Window list: front app spans the display *and* no menu-bar window there (handles below-notch fullscreen) | none | B |
| Packaging | SwiftPM + script-assembled bundle; works with Command Line Tools only. macOS 27 SDK turns `@State` into a macro whose plugin only ships with Xcode, so Islet uses the property wrapper type directly. | n/a | n/a |

## 6. Connecting to every app

Four built-in hooks cover most apps with no per-app work:
- **notification-banner mirroring** (chat, mail, reminders, anything that notifies);
- **call detection** from per-app microphone use (every call app, including browser calls);
- **Now Playing** (every player that reports to macOS);
- **Dock badge counts** (unread counts for Slack, Mail, Messages; roadmap).

For the rest, the catalogue gives a recipe per app: AppleScript dictionaries (Things, OmniFocus, Mail, Music), URL schemes, CLIs (`gh`, `docker`, `tmutil`, `tailscale`), editor tasks, shell hooks, and widgets that poll cloud APIs.

It also records dead ends:
- Teams retired its local meeting API on 30 June 2026, so there's no mute state.
- Discord's voice RPC is partner-only.
- Messages has no incoming-message event.
- Todoist, Notion, Linear, Figma and GitHub only push webhooks to public HTTPS addresses.

## 7. What's next

- **Signed and notarised releases.** This needs a paid Apple Developer ID. Until then, builds are ad-hoc signed with the hardened runtime.
- **Siri through App Intents.** The Command Line Tools can compile intents but can't produce the metadata the system reads (Xcode's `appintentsmetadataprocessor`). A CI job with Xcode could. Until then, Siri reaches Islet through Shortcuts.
- **Per-bud AirPods battery**, **external-display brightness** and a **notification inbox**.
- **Remote channels** (ntfy/SSE subscriptions) so CI and servers can push without being on the same Mac.

## 8. Second round: parity, Live Activities, AI, glass and the menu bar (30 September 2026)

### The macOS 27 menu bar

Measured on a 14" MacBook Pro running macOS 27.0.1 [local]:
- The notch spans x 663.5–848.5 pt. The Window Server draws the whole bar as one window, so status items can only be located through Accessibility.
- `MenuBarAgent` owns the system items and the overflow chevron that macOS 27 adds when items don't fit beside the notch. Collapsed items keep reporting frames stacked on the chevron (x 873–915 here), so a naive reading makes the right-hand side look full. Ignoring them leaves 48.5 pt free to the right of the notch.
- Free space on the left depends on the frontmost app's menus: 40.5 pt with Chrome, 191.5 pt with WhatsApp, 340.5 pt with Discord.
- MenuBarAgent's own menu bar window lists every item, overflow included, with its frame, and reading it takes a few milliseconds. Asking every app for its status items took over a second and woke each one.

What Islet does: it reads that window only while the closed island is visible, sizes the wings to the free space (34 pt or more for an icon and a value, otherwise 26 pt icon-only wings that stay in the row), keeps clear of the chevron whenever there's room, and ignores width changes under 4 pt. Panels use the transient collection behaviour, so Mission Control hides them. Sources: [Badgeify](https://badgeify.app/macos-27-golden-gate-menu-bar-changes/), [Michael Tsai](https://mjtsai.com/blog/2026/09/25/golden-gate-and-the-notch/), [boring.notch #1513](https://github.com/TheBoredTeam/boring.notch/issues/1513) and [#1059](https://github.com/TheBoredTeam/boring.notch/issues/1059).

### iPhone Live Activities on the Mac

- They reach the Mac through `replicatord` and are drawn by `WidgetRenderer_Activities`; no iPhone app code runs on the Mac [local]. Apple's support note is [120684](https://support.apple.com/en-us/120684). Timers and stopwatches from the iPhone don't appear on the Mac ([iDownloadBlog](https://www.idownloadblog.com/2025/06/28/how-to-use-live-activities-mac/)).
- On macOS 27 the pill is a MenuBarAgent item whose accessibility label is "Live Activity", translated into 41 languages in `MenuBarCore.loctable`; its menu has "End Live Activity" ([ipsw-diffs](https://github.com/blacktop/ipsw-diffs/blob/main/macOS/27_0_26A428_vs_27_2_26B5086k_Mac18,5/LOCALIZATIONS/FileSystem/System/Library/CoreServices/MenuBarAgent.app/Contents/Resources/MenuBarCore.loctable.md)). Every other system item has a `com.apple.menuextra.*` identifier.
- `liveactivitiesd` posts Darwin notifications when activity records change, which gives a trigger without polling [local].
- On macOS 26 Control Center hosted each activity as its own status item ([Thaw #722](https://github.com/thaw-app/Thaw/issues/722), [Ice #656](https://github.com/jordanbaird/Ice/issues/656)). Islet 0.2 targets macOS 27 and hasn't been tested on 26.

Islet recognises activities by that label in every language, the identifier, the menu command or the renderer process; keys each one by its element; reads its text; works out whether a clock counts up or down; and opens the original only when you click it. How much text a pill exposes varies by app, and that hasn't been checked against every app yet.

A catalogue built from 119 apps with evidence of a Live Activity (137 in Islet, with its own additions) gives each an icon, a colour and one of twelve layouts: ride or delivery ETA, stages, flight, route, score, timer, workout, gauge, live audio, media, agent and progress. Parcels are a gap: none of the big carriers ship one.

### AI

- **Apple Intelligence.** Foundation Models work from a Command Line Tools build, including structured output and tool calling without the `@Generable` macro [local]. The on-device model on the test Mac reported `modelNotReady`, so every AI feature has a plain fallback. Context is 4,096 tokens on-device ([WWDC26 session 319](https://developer.apple.com/videos/play/wwdc2026/319/)).
- **Siri.** App Intents compile, but the system only finds them through metadata that Xcode generates ([Apple forums](https://developer.apple.com/forums/thread/759160?page=2), [WWDC26 session 345](https://developer.apple.com/videos/play/wwdc2026/345/)). Shortcuts can already run anything Islet exposes, and "Use Model" in Shortcuts gives Apple Intelligence answers with no model code in Islet.
- **Claude and ChatGPT.** Both stream over plain HTTPS. OpenAI's Responses API stores responses unless told not to, so Islet sends `store: false` ([OpenAI reference](https://developers.openai.com/api/reference/resources/responses/methods/create)). Claude Code and Codex can answer with their own login when run headless ([Claude Code](https://code.claude.com/docs/en/headless), [Codex](https://learn.chatgpt.com/docs/non-interactive-mode)).
- **Approvals from the notch.** Claude Code's `PermissionRequest` hook takes an allow or deny decision and falls back to the terminal prompt on timeout ([hooks reference](https://code.claude.com/docs/en/hooks)); Codex and Cursor have equivalents ([Codex](https://learn.chatgpt.com/docs/hooks), [Cursor](https://cursor.com/docs/agent/hooks)).
- **Usage limits.** Claude Code gives its status-line command the 5-hour and weekly percentages ([status line](https://code.claude.com/docs/en/statusline)); Codex writes them into its session logs [local]. Islet reads only what these tools publish for the purpose. It never reads another app's login token or calls an endpoint meant for that tool's own client.

### Liquid Glass

- All the glass APIs (`glassEffect`, `GlassEffectContainer`, `NSGlassEffectView`) build with the Command Line Tools on macOS 26 and later [local].
- Apple keeps the iPhone island black and puts glass on floating controls, not status chrome ([HIG: materials](https://developer.apple.com/design/human-interface-guidelines/materials), [WWDC25 session 219](https://developer.apple.com/videos/play/wwdc2025/219/)). Glass beside the hardware notch shows the wallpaper at its edges.
- Glass can't sample glass behind it, so cards inside a glass panel should be plain fills ([Apple](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views)).
- Another notch app saw glass freeze in a window that never becomes key ([Atoll #304](https://github.com/Ebullioscopic/Atoll/issues/304)), so beside a notch Islet uses it only while expanded (a closed pill on a display without a notch is glass only with *Glass on displays without a notch*, off by default).

What Islet does: the Glass theme keeps the menu bar row black, fades glass in below it once the island has grown, and uses plain fills for cards.

### Parity with 22 notch apps

Islet already led on extensibility (API, CLI, URL scheme, script widgets, agent hooks), idle cost and a Now Playing bridge that works on macOS 27. It trailed on everyday depth: a scrubber that seeks, an output picker, timers you can run from the island, an agenda with reminders, gestures, approvals and usage limits, which 0.2 adds. 0.2 also adds the weather and time-synced lyrics. Still missing: a notification inbox, Bluetooth device batteries, and signed builds with automatic updates.
