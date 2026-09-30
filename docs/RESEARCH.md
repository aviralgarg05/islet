# Research: the Mac notch-app market, what's broken, and what Islet does about it

*Snapshot: 30 September 2026. The full reports, with sources, are in [`docs/research/`](research/):*

| Report | What it covers |
|---|---|
| [01 — Market analysis](research/01-market-analysis.md) | ~60 apps and libraries, pricing, licenses, activity, a 12-app × 35-feature matrix |
| [02 — Pain points](research/02-pain-points.md) | GitHub issues, Reddit, HN and press, ranked by frequency and severity |
| [03 — Integration feasibility](research/03-integrations-feasibility.md) | 17 integrations, exact APIs, permissions, graded A–D, several verified on macOS 27 |
| [04 — Dynamic Island feature catalogue](research/04-dynamic-island-feature-catalog.md) | iPhone (through iOS 27), Mac menu-bar Live Activities, Android equivalents, prioritized synthesis |
| [05 — App integration catalogue](research/05-app-integration-catalogue.md) | ~50 Mac apps: what each exposes (notifications, AppleScript, URL schemes, CLIs, webhooks), a recipe, and what Islet shows; 42 hooks verified on this Mac |

---

## 1. The market in one page

**Paid and closed:** NotchNook ($25 or $3/mo), Alcove ($14.99), DynamicLake Pro ($13.99, plugin market), Droppy ($9.99, formerly open source), Seam ($19.90), MediaMate (≈$8, HUD-focused), Dynamic Notch ($5.99), plus 15+ smaller apps (MacNotch on Setapp, Perch, NotchNest, NotchBay, Crest, OneNotch, NotchSpace…). Most are one-time purchases between $6 and $25.

**Open source:** Boring Notch (≈10.9k★, GPL-3.0), its fork Atoll (≈4.8k★, GPL-3.0, notched MacBooks only), NotchDrop (MIT, shelf only), SuperIsland (no license file), DynamicNotch, MewNotch (GPL-3.0), Cyclop (MIT, signed).

**The fastest-growing niche is coding-agent monitoring:** Vibe Island ($19.99), and open-source Vibe Notch (2.5k★), CodeIsland (2.4k★), Open Island (2.0k★), Ping Island and Notchi (1k★ each), all less than a year old.

**What changed in 2026:**
- **NotchNook is effectively gone.** A dispute took down lo.cafe's domain and license servers; Setapp dropped it on 22 Sep and Homebrew disabled its cask on 19 Sep. Its paying users are looking for a replacement.
- **Apple broke Now Playing** for third-party apps in macOS 15.4 (MediaRemote now checks entitlements) and has not added a public API. Almost every app relies on one workaround: the `mediaremote-adapter` trick of running code inside Apple-signed `/usr/bin/perl`.
- **macOS 27** redrew the menu bar as one window (breaking Bartender and Ice) and added an overflow chevron for items hidden by the notch.
- **The iPhone 18 Pro** shows up to three Live Activities in a smaller island, and **iOS 27** puts Siri in the island. **macOS 26+** already shows iPhone Live Activities as a menu-bar pill, with no public API to read them.
- **Licensing risk is real:** Atoll's author had Droppy's repo taken down over GPL-3.0; anything forked from Boring Notch or Atoll inherits GPL.

**The white space** (report 01 §4): no product is at once *permissively licensed, signed, plugin-first, good on non-notch and multi-display setups*, and covers both the classic features and agent monitoring.

## 2. What users complain about (ranked)

| # | Pain point | Evidence (report 02) | Islet's answer |
|---|---|---|---|
| 1 | **Now Playing keeps breaking** | boring.notch #417 is its most-voted issue (54 👍, 58 comments); stable release broken for ~8 months | Four layers: MediaRemote bridge (own clean-room helper, verified on macOS 27) → Music/Spotify distributed notifications → AppleScript enrichment → `POST /v1/media` push. An end-to-end test drives a fake player through the bridge. |
| 2 | **CPU, battery, memory drain** | NotchNook 40–100% CPU; boring.notch 26–41% idle (2,243 leaked timers); Atoll 100%; MediaMate 8 GB leak | Event-driven everything; one deadline timer instead of polling; perpetual animations run in Core Animation; the pointer is tracked by a trigger window, not a global mouse monitor. **Measured: 0.0% idle, 0.0% with music animating, ≤0.6% with a live countdown, 65–85 MB.** `scripts/perf.sh` enforces budgets. |
| 3 | **Abandonment, licensing, subscriptions** | NotchNook offline; Alcove license resets stalled; Droppy DMCA | MIT license, clean-room code (no GPL reuse), no accounts, no license server, config in a plain JSON file. |
| 4 | **Fullscreen and accidental opening** | island covers video; opens when reaching for tabs or the menu bar | Fullscreen detection (window list + menu-bar presence, notch-aware); hover needs a short dwell *and* slow pointer; per-app "hide" and "show in fullscreen" rules; critical items still break through. |
| 5 | **Multi-monitor, clamshell, notch geometry** | notch jumps displays, misplaced after sleep | Geometry from `auxiliaryTopLeft/RightArea`; synthetic pill on notchless screens; panels rebuilt (debounced) on display, wake and Space changes; display modes: notched / main / all. |
| 6 | **HUD replacement conflicts** | key interception breaks fine steps and external displays; duplicate HUDs | Default is observe, don't hijack: CoreAudio volume listener and an event-driven brightness callback, no permission. Replacing the system HUD is an explicit opt-in. |
| 7 | **Sleep/wake instability** | disappears after sleep (boring.notch #336) | Rebuild on wake; single-instance guard; discovery file owned per process. |
| 8 | **Trust and permission friction** | unsigned builds, over-asking | Nothing is requested at launch. Every permission is opt-in from Settings, with a sentence on why. Local build is signed with a stable identity so grants survive rebuilds. |
| 9 | **Janky animations, bloat** | "wobbly" animation toggle ≈83 👍 | Five motion styles including Minimal and Off, Reduce Motion honoured, every "wow" has an off switch; modules toggle individually. |
| 10 | **Menu-bar overlap** | covers menu items, fights menu-bar managers | Idle island is invisible (the hardware notch is already there); everything outside the island is click-through; bubbles avoid Apple's Live Activity pill area by placement setting. |
| 11–12 | Shelf and calendar bugs | file promises, all-day date shifts | Bookmarked shelf items survive renames; all-day events never raise alerts. |

## 3. What people want most (report 02 §2, report 04 §4)

1. **Notifications in the notch**: the top open request. → *Built:* mirroring from every app (including iPhone notifications macOS forwards), opt-in, experimental, with per-app mute, tint and priority, and optional on-device one-line summaries.
2. **Now Playing from any app** → *Built* (see #1 above).
3. **Per-display and per-context visibility** → *Built:* display modes, fullscreen rules, per-app rules.
4. **Animation control** → *Built:* Fluid / Snappy / Smooth / Minimal / Off.
5. **Size control** → *Built:* Compact (default) / Standard / Large / Custom presets.
6. **AI coding-agent status** → *Built:* Claude Code, Codex and a generic agent protocol; "waiting for you" is high priority with a glow; segmented plan steps.
7. **AirPods/headphones and output switching** → *Built:* output-device card on connect (no Bluetooth permission needed). *Not built:* per-bud battery (private keys, Bluetooth permission).
8. Lyrics, more calendar providers, better shelf, external-display brightness, Caffeine, Pomodoro, lock-screen widgets → partly built (shelf, timers); the rest are roadmap or script-widget territory.

## 4. The iPhone Dynamic Island, and what carries over (report 04)

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
| Spring morphing, blur-crossfade, numeric text | Per-style springs (expand ≈0.42 s/0.78, collapse ≈0.34 s/0.92), blur-replace transitions, numeric-text countdowns, arrival bounce |
| Haptics | Trackpad haptics for direct actions only by default (open, press, drop); optional for important alerts |

**Reading the iPhone's own island on the Mac is not possible.** No API exposes other apps' Live Activities, and macOS 26+ already shows them in the menu bar. Islet coexists with that pill and covers the iPhone in two ways:
- It mirrors the iPhone notifications macOS forwards.
- It accepts events from **iPhone Shortcuts automations** (alarm, Focus, arrive/leave, battery level) over an opt-in, token-protected local-network bridge.

## 5. Feasibility decisions (report 03, plus probes on this machine)

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
| Packaging | SwiftPM + script-assembled bundle; works with Command Line Tools only. macOS 27 SDK turns `@State` into a macro whose plugin only ships with Xcode, so Islet uses the property wrapper type directly. | — | — |

## 6. Connecting to every app (report 05)

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

- **Metaball split animation** between the island and its bubbles; long-press/Force-Click expanded detail; two-finger swipe to cycle activities.
- **Per-bud AirPods battery** (private IOBluetooth keys, opt-in).
- **Lyrics** line for Now Playing; external-display brightness via DDC.
- **Signed and notarized releases** (Developer ID) and a Homebrew cask.
- **Remote channels** (ntfy/SSE subscriptions) so CI and servers can push without being on the same Mac.
