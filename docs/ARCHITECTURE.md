# Architecture

```
┌────────────────────────── Islet.app (menu-bar agent) ──────────────────────────┐
│                                                                                │
│  Islet (AppKit + SwiftUI)                                                       │
│   AppModel (@Observable) ── implements IsletBackend for the API                 │
│   IslandWindowController ×display ── IslandPanel (level 27) + TriggerPanel (26) │
│   PointerCoordinator ── hover intent, click-through, drag-to-shelf              │
│   Views: IslandView → Compact / Sneak / HUD / Bubble / Expanded tabs            │
│                                                                                │
│  IsletSystem (adapters to macOS)                                               │
│   LocalAPIServer (Network.framework) · SystemNowPlayingBridge (perl helper)     │
│   AppleMusic/Spotify providers · AudioMonitor · BrightnessMonitor · Battery     │
│   CalendarService · MicUsageMonitor · CameraMonitor · FullscreenDetector        │
│   NotificationMirror (AX) · DownloadsWatcher · UnlockMonitor · ShelfService     │
│   ScriptPluginRunner · ClipboardMonitor · SystemStatsSampler · AIAssist         │
│                                                                                │
│  IsletCore (pure Swift, no AppKit, fully unit-tested)                           │
│   ActivityCenter · Presenter · MediaArbiter · HoverIntent · NotchGeometry       │
│   HTTP parser + APIRouter · URLCommand · AgentHooks · ScriptPlugins             │
│   CallDetector · NotificationParser · DownloadTracker · SmartIcon · Settings    │
└────────────────────────────────────────────────────────────────────────────────┘
        ▲ isletctl (CLI)   ▲ islet:// URLs   ▲ HTTP (loopback / LAN bridge)   ▲ plugins
```

## Principles

- **All decisions live in `IsletCore`, and they are pure.** What the island shows, which player wins, when hover opens it, which icon an activity gets, how a hook payload maps to an activity, how a notification banner is parsed: all are value types with an injected clock, covered by `swift test`. The system layer only turns macOS events into calls on that core.
- **Event-driven, no polling.** CoreAudio, IOKit, EventKit, CoreMediaIO, distributed notifications, file-system events and Accessibility observers push changes. Time-based state (expiry, sneak peeks, HUD timeout) is served by **one** timer scheduled for the next deadline (`ActivityCenter.nextDeadline`). The only timers that run are for things you can see (a countdown text) or things that are in flight (a download growing, a script's schedule).
- **Animations that never stop run in Core Animation** (equalizer, spinner, urgent glow), so the window server interpolates them and Islet's process stays near 0% CPU.
- **Pointer tracking is dormant until needed.** An invisible trigger window over the notch has a tracking area; global mouse monitors are installed only after the pointer enters it and are removed when the island closes and the pointer leaves.
- **Every permission is opt-in**, requested only when the user switches the feature on.
- **Private APIs are isolated and capability-checked:**
  - MediaRemote runs in a helper process;
  - DisplayServices and CoreBrightness are `dlsym`'d;
  - Foundation Models is weak-linked.

  If Apple removes one, that feature turns off and the rest keeps working.

## The island state machine

`Presenter.present(_:)` turns the inputs into one `IslandPresentation`: activities, HUD, sneak peek, now playing, battery event, expanded display and fullscreen suppression. The options are:

```
hidden · idle · hud(HUDEvent) · sneak(Activity) · compact(nowPlaying | activity | battery) · expanded
```

Precedence: suppressed (fullscreen) → only HUD or critical; expanded; HUD; sneak; high-priority activity; battery event; playing media; other activities; paused media (optional); idle.

`AppModel.bubbles(for:)` picks up to two more items (media or activities) for the detached bubbles, iPhone-style, with an overflow count.

## Now Playing pipeline

```
MediaRemote (any app, browsers) ──perl helper──▶ SystemNowPlayingBridge ─┐
Music.app distributed notification ─────────────▶ AppleMusicProvider ─────┤
Spotify distributed notification ───────────────▶ SpotifyProvider ────────┼─▶ MediaArbiter ─▶ nowPlaying
POST /v1/media (extensions, scripts) ──────────────────────────────────────┘
```

`MediaArbiter` rules: playing beats paused; the most recent wins; direct integrations beat the generic bridge for the same track; missing fields (artwork, duration, position) are filled from any source describing the same track; paused sources expire after 15 minutes.

The helper (`Helpers/MediaRemoteBridge`) is a tiny Objective-C dylib that `/usr/bin/perl` loads. It streams JSON lines, takes `get` / `cmd N` / `seek S` on stdin, and exits when the pipe closes.

## Local API security

- Loopback bind.
- Bearer token in a `0600` discovery file (reused across launches).
- Constant-time comparison.
- `Host` must be localhost (DNS-rebinding defence) and web-page `Origin`s are refused (CSRF). Extension origins are allowed with the token.
- 1 MB body limit; 5 s request timeout.
- The LAN bridge reuses the same router with any `Host` allowed, and adds a per-client rate limit.

## Build and packaging

- SwiftPM only; the Command Line Tools are enough.
- `scripts/bundle.sh`:
  1. builds the release products;
  2. compiles the helper for `arm64e`, `arm64` and `x86_64`;
  3. assembles `Islet.app` (Info.plist, icon, helper, CLI, API docs);
  4. signs it. Locally that's ad-hoc with an identifier-based designated requirement, so privacy grants survive rebuilds. With `SIGN_IDENTITY` set it uses Developer ID with the hardened runtime.
- Two quirks of the CLT toolchain on the macOS 27 SDK:
  - `@State` is a macro whose plugin only ships with Xcode, so views use the property-wrapper type via `typealias ViewState = SwiftUICore.State`.
  - swift-testing's macro plugin needs `-plugin-path` (the Makefile passes it).

## Tests

| Layer | How | Count |
|---|---|---|
| Core logic | `swift test`: presenter, activity center, arbiter, hover intent, HTTP parser, router (auth, CSRF, rebinding), URL scheme, hooks, plugins, settings, calls, notifications, downloads, smart icons | 118 |
| System adapters | `swift test`: real sockets (API server, LAN rate limit, malformed requests), IOKit/Music/Spotify/MediaRemote parsers, script runner (timeouts, exit codes, big output), Safari/Chrome partials, shelf persistence, discovery-file permissions | 14 |
| End to end | `make e2e`: launches the real app with isolated config and port; drives CLI, HTTP, URL scheme, zsh hook, plugins and the LAN bridge; checks window level and placement, single instance, clean shutdown, idle CPU and memory | 51 (+1 media, opt-in) |
| Performance | `make perf`: CPU per island state against budgets | 7 states |
| Visual | `make snapshots`: renders 21 island states to PNG offline | — |
