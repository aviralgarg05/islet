# macOS Notch / "Dynamic Island" Apps: Competitive Market Analysis

**Snapshot date:** 2026-09-30
**Scope:** Every notable macOS app that turns the MacBook notch (or a simulated notch/pill on non-notch displays) into a Dynamic-Island-style surface, plus adjacent notch utilities (notch hiders, notch decorators, AI-agent notch monitors) and the open-source frameworks they are built on.

**Method.**
- GitHub star/fork counts, licenses, push dates and release tags were pulled live from the GitHub REST API (`gh api`) on 2026-09-30. Treat them as a point-in-time snapshot.
- Versions and minimum macOS were cross-checked against the Homebrew cask API (`formulae.brew.sh/api/cask/*.json`), the Mac App Store, and vendor sites.
- Prices come from vendor sites or storefronts (Gumroad, LemonSqueezy, App Store). Where the only source is a competitor's comparison page, the figure is marked **(3rd-party claim)**.

**Legend for the tables:**

| Mark | Meaning |
|---|---|
| ✅ | Supported (documented by the vendor or visible in the source code) |
| ◐ | Partial, beta, release-candidate only, or available via a plugin |
| ❌ | Not supported, or explicitly on the roadmap as not done |
| ? | **Unverified.** Could not confirm from a primary source. |

> **Caution on sources.** Much of the "best notch apps 2026" content online comes from vendor SEO blogs: notchy.dev, getseam.app, getdroppy.app, brow-app.com, notchbay.com, dynamicnotch.tech, crestnotch.app, tryonenotch.com, notchable.com and vibeisland.app. These pages contain factual errors. For example, brow-app.com lists Boring Notch as MIT (it is GPL-3.0) and Alcove at $5 (it is $14.99). They were used only to *discover* apps; facts were re-checked against primary sources wherever possible.

---

## 0. Key findings (TL;DR)

1. **The category leader collapsed.**
   - NotchNook (lo.cafe; $25 lifetime or $3/mo), the best-known paid notch app, has been **offline since mid-2026**. The cause is a corporate dispute between lo.cafe's founders over control of the domain, Stripe, licensing servers and social accounts.
   - `lo.cafe` no longer resolves. Setapp removed NotchNook, with discontinuation set for 2026-09-22.
   - Homebrew **disabled the `notchnook` cask on 2026-09-19** because the download was "unreachable".
   - Refunds were only partially issued. lo.cafe reportedly teased a rebuilt successor, "NOOTCH", with 90% off for lifetime holders, and a *possible* open-sourcing of NotchNook (unverified).
   - This leaves a large pool of orphaned paying users looking for alternatives right now.
2. **Open source is the volume leader.**
   - **Boring Notch** (10.9k★, GPL-3.0) is the most popular notch app on GitHub by a wide margin. Its fork **Atoll** (4.8k★, GPL-3.0) is second.
   - Both are **unsigned or not notarized** (Gatekeeper workarounds needed) and have large issue backlogs (394 and 197 open).
   - Boring Notch's last *stable* release is v2.7.3 (2025-11-24). v2.8 is at RC stage (2026-09-25) and adds notification mirroring, YouTube Music, weekly calendar, meeting-join links and update channels.
3. **The fastest-growing sub-segment is AI coding-agent notch apps.**
   - These show live status, permission approvals and usage limits for Claude Code, Codex, Gemini CLI, Cursor and similar tools.
   - In roughly six months (Dec 2025 – Sep 2026) this produced several ~1–2.5k★ OSS projects: Vibe Notch 2.5k★, CodeIsland 2.4k★, Open Island 2.0k★, Ping Island 1.1k★ and Notchi 1.0k★.
   - It also produced a paid leader, **Vibe Island** ($19.99, 25–30 agents).
   - General-purpose hubs now bolt this feature on: Notchy, Crest, OneNotch, NotchBay, Droppy (as a Droplet), and Atoll (LLM usage).
4. **Extensibility is becoming table stakes for "platform" players**:
   - SuperIsland: a JavaScript extension SDK running in JavaScriptCore.
   - Droppy: "Droplets", built with DroppyKit, with a visible third-party ecosystem on GitHub.
   - Atoll: AtollExtensionKit (XPC, LGPL-3.0).
   - DynamicLake Pro: Plugins and a Market, since 1.9.7 (Sep 2026).
   - Boring Notch still lists "Extension system" as a to-do.
5. **Pricing has compressed.**
   - Paid one-time prices range from **$5.99** (Dynamic Notch) through $9–$9.99 (NotchBay, Droppy, OneNotch Pro), $13.99–$14.99 (DynamicLake Pro, Alcove), to $19.90–$19.99 (Seam, Crest, Vibe Island, NotchSpace).
   - Freemium and subscription models also exist: Brow Pro $49/yr, Perch, NotchNest, Sapphire, and MacNotch via Setapp.
   - A closed but **free** app, Notchy (notchy.dev), claims 74 features and aggressively targets every competitor with SEO pages.
6. **Platform risk is real and shared by everyone.**
   - **macOS 15.4 blocked the private MediaRemote "Now Playing" API** for non-Apple processes. Nearly every app now relies on the community `mediaremote-adapter` workaround (it runs through the entitled `/usr/bin/perl`), or on per-player AppleScript and distributed notifications.
   - Alcove's own FAQ warns it "relies on private APIs" and is sold "as is".
   - Apple is rumored (Bloomberg, Feb 2026) to ship an **OLED touchscreen MacBook Pro with a real, interactive Dynamic Island** in late 2026 or early 2027. That would both validate the category and threaten it.
7. **License hygiene matters.** In **Feb 2026 Atoll's author filed a GitHub DMCA takedown against Droppy** (iordv/Droppy), alleging GPL-3.0-derived code: parallax hover, lock-screen manager, media-key interceptor, volume and brightness managers. The Droppy repo is now blocked (HTTP 451) and Droppy ships as a closed $9.99 app. Any new OSS entrant reusing Boring Notch or Atoll code must comply with GPL-3.0.
8. **White space for a new OSS entrant.** No app is all of the following at once:
   - open source under a permissive or clear license,
   - signed and notarized,
   - lightweight,
   - working on non-notch and multi-display setups,
   - offering a documented plugin API,
   - covering both "classic" features (media, shelf, HUD, calendar) and AI-agent monitoring.

   Boring Notch comes closest but is unsigned, has no plugin API, and lacks weather, lock-screen widgets and clipboard.

---

## 1. Overview tables

### 1a. General-purpose notch hubs: paid or closed-source

| App | Developer | Price / licensing | OSS? | GitHub ★ | Last active (version) | macOS min | Headline features |
|---|---|---|---|---|---|---|---|
| **NotchNook** | lo.cafe | $25 one-time (5 Macs) or $3/mo (2 Macs); 48 h trial | No | — | v1.6.2 (MacUpdate lists 2026-06-26). **Offline Jul–Sep 2026**; Homebrew cask disabled 2026-09-19 | 14.6 (MacUpdate) / 14 (Homebrew) | Media, file tray + AirDrop, calendar, Shortcuts widget, mirror, notes/to-do, timers, custom GIFs, non-notch support |
| **Alcove** | tryalcove.com | $14.99 one-time, 3 devices, 72 h trial, 14-day refund | No | — | v1.7.7 (Homebrew); FAQ updated Jun 2026 | 15 (Homebrew cask) | Apple-faithful Dynamic Island: live activities, notifications, customizable HUDs, lock-screen widgets, swipe gestures, pill on non-notch Macs |
| **DynamicLake Pro** | Aviorrok (dynamiclake.com) | $13.99 one-time (Gumroad); 30-day refund | No | — | 1.9.7.5 (Sep 2026) | ? (macOS 27 support added in 1.9.5.5) | Notifications (iMessage, WhatsApp, Telegram, Slack), calls, DynaDrop file conversion and share links, AirDrop, Bluetooth alerts, weather, timers, **Plugins + Market**, Liquid Glass, miniLake |
| **MediaMate** | Wouter01 | Free demo; license €6.99 (≈$7.93) on Gumroad | No (release-only repo) | — | 3.8.4 (2026-08-13, macOS 27 support) | 13 | Replaces volume, brightness and keyboard-backlight HUDs; Now Playing; notch HUD; AirPods icons |
| **Droppy** | getdroppy.app (orig. `iordv/Droppy`) | $9.99 one-time, 2 devices, 3-day trial, 14-day refund | **No longer.** Repo blocked by DMCA, Feb 2026 | — | 16.0.1 (Homebrew); site updated 2026-07-06 | 14 (AS + Intel) | Shelf, clipboard, media and lyrics, notifications, HUDs, **38 "Droplets" + third-party DroppyKit ecosystem**, iPhone companion app |
| **Notchy** | Vishva Variya (notchy.dev) | **Free**, donation-funded | No | — | v1.0.178 (2026-09-25) | 13 | Claims 74 features: Face Unlock, AI rate-limit tracking (60+ providers), terminal, stocks, window snapping, local dev API, lock-screen widgets |
| **Seam** | Ramzi (getseam.app) | $19.90 one-time, 2 Macs, 48 h trial, 14-day refund, ≥1 yr updates | No | — | 1.16.2 | 14 (Homebrew) | Music, focus timer, calendar, weather, **100% local voice transcription and translation**, "Island mode" for non-notch displays, ~0.1% CPU |
| **Dynamic Notch** | Aryaan (dynamicnotch.tech) | $5.99 one-time (pay-what-you-want above) | No | — | 4.0 (build 33) | 14.6, **Apple Silicon only** | 16 modules: media, file tray, clipboard, notes, current task, colour picker (WCAG), calendar with Join, timer, HUD, weather, mirror, download watcher, hide-notch mode |
| **Sapphire** | Shariq Charolia | Free core + Pro/Ultra subscriptions (notchy.dev claims $15.99–$30.99/mo; **unverified**) | Source on GitHub, **AGPL-3.0** | 240 | v3.0 (2026-09-15) | 14.6 (3rd-party claim) | Android Nearby Share, per-app EQ, snap zones, eye-break reminders, Gemini Live; paid tier adds "Blip" AI agent, Face ID, sports and finance widgets |
| **Brow** | brow-app.com | Free (40+ tools); Pro $4.99/mo or $49/yr | No | — | ? | 14 | All-in-one utility: launcher, clipboard, OCR, window management, fan control, PDF editor. The notch is one surface. Pro adds AI dictation, translation and an agent. |
| **NotchBay** | Ossian design lab | $9 one-time | No | — | ? | ? | Zoom and Meet call controls, 60-item clipboard tray with OCR, on-device dictation, Claude Code/Codex state, floating island on non-notch displays |
| **Crest** | crestnotch.app | Free (5 of 18 widgets) + Pro $19.99 one-time | No | — | ? | 14 | Widgets for SSH hosts, pull-request checks, agent approvals (Claude Code, Codex, Copilot CLI), Claude chat, notification mirror, 12 window layouts |
| **OneNotch** | tryonenotch.com | Free + Pro $9.99 lifetime (clipboard limits only) | No | — | ? | 15, Apple Silicon | AI-agent status, clipboard boards, lyrics, screenshot markup, translate, window layouts, pill mode |
| **NotchSpace** | notchspace.com | $19.99 (sale $16) one-time | No | — | ? | 14; AS + Intel | Multi-display notch, clipboard, temp shelf, AI file organizer, expense tracker, workspaces, "Pings". *(notchy.dev lists a free "NotchSpace", macOS 15; possibly a different product, **unverified**.)* |
| **MacNotch** | MacPaw (Setapp) | Setapp subscription (from $14.99/mo) or standalone from $4.99/mo | No | — | 1.9.9.6 | 14 | Media (incl. YouTube and browsers), calendar, Pomodoro, Reminders, toggles, Bluetooth batteries, AirDrop/zip/convert, HUD |
| **Perch** ("Dynamic Notch Island") | Serkan Adiguzel (Mac App Store) | Free + Pro $3.99/mo, $14.99/yr, $24.99 / $49.99 lifetime | No | — | 1.5.2 | 13 | Media, weather, calendar, timer, snippets, file tray, AI chat, fullscreen-app compatibility |
| **NotchNest** | notchnest.app (Mac App Store) | Free + Premium $2.99/mo or $14.99 lifetime | No | — | ? | 14, Apple Silicon | Apple Intelligence clipboard and meeting briefings, Pomodoro, AirDrop, music, mirror, bookmarks |
| **NotchBox** | Mac App Store | Free + Pro IAP $4.99 | No | — | ? | 13 (3rd-party claim) | Music, file drop, Pomodoro, camera mirror, timers |
| **Nook X** | Mac App Store (CN-focused) | ? | No | — | updates in 2026 | 13 | Lyrics, weather, tasks, mirror, AI assistant |
| **Pulse Island** | pulseisland.club | 7-day trial, then one-time price (amount **unverified**) | No | — | 1.0 | ? | Music incl. browser tabs, meetings, smart clipboard, weather, devices, CPU/RAM/network |
| **Canopy** | getcanopy.pro | €15 (per getdroppy.app compare; **unverified**) | No | — | v3.3.7 (3rd-party) | ? | Media, LRCLIB synced lyrics, Liquid Glass lock-screen widget, notification mirroring |
| **OmniNotch** | Nikhil Verma | $9 launch / $19.99 regular, one-time | Claims NotchDrop-based source on GitHub (repo **not found** via API) | ? | 2.0 | 14 | 20 tools incl. "Ask Omni" AI, AI usage, stocks, teleprompter |

### 1b. General-purpose notch hubs: free / open source

| App | Repo | License | ★ / forks | Last push · latest release | macOS min | Headline features |
|---|---|---|---|---|---|---|
| **Boring Notch** | TheBoredTeam/boring.notch | GPL-3.0 | **10,919 / 1,069** | 2026-09-30 · stable v2.7.3 (2025-11-24); **v2.8-rc.1 (2026-09-25)** | 14 (AS + Intel) | Music and visualizer, lyrics, Apple Music, Spotify, YouTube Music, system Now Playing, calendar, reminders, shelf + AirDrop, HUD (OSD), mirror, battery. v2.8-rc adds notification mirroring, meeting-join links, audio-route switcher and update channels. **Unsigned.** |
| **Atoll** | Ebullioscopic/Atoll | GPL-3.0 | **4,815 / 331** | 2026-09-30 · v2.3.3 (2026-07-24); betas to 2026-09-07 | 14 (notched MBP only) | Boring Notch fork with system stats, clipboard, colour picker, timers, terminal, lock-screen widgets, Focus/DND, screen-recording and privacy indicators, downloads, LLM usage tracking, **AtollExtensionKit (XPC)** |
| **NotchDrop** | Lakr233/NotchDrop | MIT | 2,116 / 162 | 2026-05-18 · no GitHub release; Mac App Store v2.16 (2024-11-25), free | 13 | Minimal file shelf + AirDrop; inspired NotchNook; origin of Boring Notch's shelf |
| **SuperIsland** | shobhit99/SuperIsland | **No license file** (source-available; "free and open source" per site) | 670 / 56 | 2026-09-13 · 1.0.10 (2026-06-12) | 14 | Now Playing (incl. Chromium browsers), battery, weather, calendar with meeting links, notifications (WhatsApp), shelf, HUD, **JS extension SDK**, energy modes, any Mac |
| **DynamicNotch** | jackson-storm/DynamicNotch | GPL-3.0 | 581 / 43 | 2026-09-29 · v1.6.2 (2026-09-06) | 14.6 | Own engine with iOS-faithful physics; live activities (media, downloads, AirDrop, timer, screen recording, Focus, hotspot); alerts (battery, Bluetooth, Wi-Fi, VPN); lock screen; floating capsule on non-notch displays; 38+ languages |
| **MewNotch** | monuk7735/mew-notch | GPL-3.0 | 554 / 37 | 2026-09-17 · 2.2.2 (2026-06-30) | 14–15.2 (project targets; **unverified**) | HUD-first design: brightness, volume, input volume, power. Plus Now Playing, persistent shelf, mirror, bash-script view, lock-screen HUD, per-display, Touch Bar support. **Unsigned.** |
| **Cyclop** | akalikbergenov/cyclop | MIT | 345 / 70 | 2026-09-20 · v0.8.2 (2026-09-17) | 15 | Music (any source, zero permissions), shelf, clipboard (40), snippets, calendar with Join, offline translate, currency, **teleprompter**, notes. **Signed and notarized** since 0.8.0. |
| **Peninsula** | Celve/Peninsula | GPL-3.0 | 457 | 2025-10-10 · 0.1.0 | 14 | Window switching, notifications, file storage |
| **Tuneful** | martinfekete10/Tuneful | No license (release-only repo) | 537 | 2026-05-23 · v2.5.2 (2025-03-12) | ? | Spotify and Apple Music player in notch, menu bar or mini player; non-notch auto-hide; iCloud sync |
| **OpenYoink** | MuQY1818/OpenYoink | MIT | 216 | 2026-09-21 · v1.6.8 | 15 | Drag-and-drop shelf / Dynamic Island for files, images and text |
| **ghnotch** | aymandakirgh/ghnotch | MIT | 174 | 2026-09-14 · v0.4.0 | 14 | Media, calendar, file shelf, AI command bar |
| **ComfyNotch** | AryanRogye/ComfyNotch | MIT | 149 | 2026-01-24 · 0.1.40 (2025-08-05) | ? | Widgets, AI chat, music, brightness |
| **NotchBar** | navtoj/NotchBar | AGPL-3.0 | 128 | 2025-12-12 · none | 14.5 | Widgets around the notch: system monitor, media, active app |
| **QuartzNotch** | Clayton630/QuartzNotch | GPL-3.0 | 91 | 2026-07-17 · v0.4.3 | ? | "Ambitious" Boring Notch fork |
| **MacIsland** | BadRat-in/MacIsland | MPL-2.0 | 48 | 2026-07-31 · v1.1.0 | 15 | Notification-panel Dynamic Island |
| **Dynamic-Island-Sketchybar** | crissNb | MIT | 528 | 2025-09-02 | — | SketchyBar config (power users) |
| **Ripple** | TopMyster/Ripple | MIT | 172 | 2026-08-13 · v3.3.0 | — | Cross-platform (Windows, macOS, Linux) JS Dynamic Island |

*Long tail:* dozens of 0–50★ repos named OpenNotch, notch-island, islet, top-notch, NotchPop, nooky, active-notch and similar, created in 2026. None is material.

### 1c. AI coding-agent notch apps (new 2025–26 sub-segment)

| App | License / price | ★ | Last release | macOS min | Agents | Notes |
|---|---|---|---|---|---|---|
| **Vibe Island** (vibeisland.app, Edward Luo) | **Paid**: $19.99 one-time (1 Mac; 2- and 3-Mac tiers); trial | 151 (community / issues repo) | 1.0.51 (Homebrew) | 14 | 25–30 (Claude Code, Codex, Gemini CLI, Cursor, Copilot, Kiro, Amp…) | Approvals, question answering, plan review, jump to 20+ terminals, usage limits, SSH remote |
| **Vibe Notch** (ex-"Claude Island") | Apache-2.0, free | **2,511** | v1.3.2 (2026-04-20) | 15.6 | Claude Code | Pioneer (Dec 2025). Approvals, chat history. Mixpanel analytics. |
| **CodeIsland** (wxtsky) | MIT, free | **2,440** | v1.0.35 (2026-09-24) | 14 | 30+ | Approvals, iPhone/Watch buddy, ESP32 desk buddy, SSH, webhooks; hides in fullscreen; signed and notarized |
| **Open Island** (Octane0411/open-vibe-island) | GPL-3.0, free | **2,036** | v1.2.1 (2026-09-15) | 14 | 13 agents, 15+ terminals and IDEs | "Open-source Vibe Island"; local-first, no telemetry; 216 open issues |
| **Ping Island** (erha19) | Apache-2.0, free | 1,120 | v0.32.1 (2026-09-26) | 14 | 17 clients | Detachable pet, SSH, event filtering |
| **Notchi** (sk-ruban) | GPL-3.0, free | 1,034 | v1.2.7 (2026-09-19) | 15 | Claude Code, Codex | Pixel sprites, sentiment via API key, cost/token tracking; signed |
| **Notchy** (adamlyttleapps) *(different from notchy.dev)* | MIT | 721 | none (push 2026-03-29) | 26 | Claude Code | Terminal panel in the notch with Xcode project detection |
| **HermesPet** | none | 600 | — | 14 | multi-engine | Chinese-language AI companion in the notch |
| **MioIsland** | NOASSERTION | 540 | v3.1.3 (2026-08-13) | 15 | Claude Code + others | Approve and jump |
| **codex-island** | MIT | 346 | — | ? | Codex | Usage limits |
| **agent-notch** | MIT | 308 | — | 12 | multiple | "Open-source alternative to vibe-island" |
| **Notch Pilot** | MIT | 68 | v0.4.12 (2026-04-30) | 14 | Claude Code | Real 5-hour/weekly usage via OAuth usage endpoint; diff view on approvals; dangerous-command detection |

### 1d. Niche, notch-hiding and decorative apps

| App | Price | OSS | Last active | macOS min | What it does |
|---|---|---|---|---|---|
| **TopNotch** (MTW, makers of CleanShot) | Free | No | 1.3.2 (Homebrew) | 11 | Hides the notch by blacking the wallpaper strip; multi-display, Spaces |
| **Notchmeister** (Iconfactory) | Free (Mac App Store) | BSD-3-Clause, 173★ | push 2026-06-29 | 12 (Monterey) | Decorative effects around the notch (glow, lights, "radar"); fake notch for older Macs |
| **NotchCam** | ~$1 Mac App Store (2021 price; current **unverified**) | No | ? | ? | Click the notch to preview the webcam; can simulate a notch; wallpaper blackout |
| **Hot** (macmade) | Free | MIT, 3,046★ | 1.9.4 (2024-07-10) | ? | **Not a notch app.** Menu bar CPU thermal-throttle indicator. Included because it was named in the brief. |
| **OnlySwitch** | Free | MIT, 5,953★ | 2026-09-28 | ? | Menu-bar toggle suite that includes "hide notch" |
| **QuakeNotch** | Free + Pro $14 | No | 3.3.2 (2026-08-11) | 14 | Quake-style terminal drops from the notch; QPilot AI; Apple Music |
| **TickerNotch** (BitVibe Labs) | Free + Pro $40 lifetime or $5/mo | No | 1.10.0 | 14 | Stocks, crypto, weather, social counters, RSS beside the notch |
| **Notchable** | Lite $9.99 / Standard $19.99 one-time; 3-day trial | No | 2.1 | 15 | Task manager in the notch with voice capture and AI sorting (on-device Qwen3 1.7B or cloud) |
| **Cronus** | $6/mo, 21-day trial | No | ? | ? | Time tracking in a notch strip |
| **Notch teleprompters** | textream 3,781★; notchprompt 1,380★; NotchPrompter 639★ (all free) | mostly MIT | active | — | Teleprompter under the camera. Shows the notch-as-camera-adjacent use case. |

### 1e. Developer frameworks and key dependencies

| Library | License | ★ | Last active | Purpose |
|---|---|---|---|---|
| **DynamicNotchKit** (MrKai77) | MIT | 462 | 1.1.0 (2026-04-05) | SwiftUI notch window + `DynamicNotchInfo`; auto `.floating` style on non-notch Macs; macOS 13+ |
| **NotchNotification** (Lakr233) | MIT | 120 | 1.1.0 (2024-09-20) | Notification inside the notch (from NotchDrop) |
| **OpenNook** (twinkling-reality) | Apache-2.0 (+ MIT NookSurface) | 44 | v0.4.0 (2026-06-29) | Framework for notch apps: window, hover, settings shell, hotkey, shelf, live-activity queue; macOS 15+ |
| **AtollExtensionKit** | LGPL-3.0 | 33 | 2026-09-15 | Atoll's third-party extension API |
| **mediaremote-adapter** (ungive) | BSD-3-Clause | 278 | 2026-09-30 | Restores Now Playing on macOS 15.4+ via `/usr/bin/perl`. Used by Boring Notch, MewNotch, DynamicNotch and others. |
| **SkyLightWindow** (Lakr233) | MIT | 214 | 2026-07-12 | Draw UI on the lock screen (Atoll, MewNotch) |
| **MacroVisionKit** (TheBoredTeam) | MIT | 14 | 2025-11-22 | Fullscreen / window-state detection |
| **Stats** (exelban) | MIT | 42,214 | 2026-09-29 | SMC and IOReport readers reused by Atoll for system stats |

---

## 2. Per-app detailed profiles

### 2.1 NotchNook (lo.cafe): paid, closed. **Status: offline / in dispute.**

- **Price.** $25 lifetime (up to 5 Macs) or $3/month (2 Macs). 48 h trial, or 15-day trial with a subscription. It was also on Setapp. (Macworld, Jul/Aug 2024; confirmed by search snippets in 2026. brow-app.com's "$30" is **unverified**.)
- **Version / requirements.** 1.6.2 (MacUpdate lists 2026-06-26). macOS 14.6+. Intel and Apple Silicon. Homebrew cask `notchnook` 1.6.2 requires ≥14 and was **disabled 2026-09-19** ("unreachable").
- **Features.**
  - "Nook" widgets: universal media controls with two-finger swipe to skip, calendar, Shortcuts widget, notes and to-do, webcam mirror, timers.
  - File tray and AirDrop drop zone; custom GIFs and animations.
  - Live activities for now playing, battery changes, Bluetooth connections and calendar transitions.
  - Optional HUD replacement.
  - Works on non-notch displays as a half-size notch.
  - Heavy customization; trackpad haptics.
- **Music apps.** Apple Music and Spotify confirmed (Macworld 2024 could not get Podcasts or QuickTime to work). Later "universal" media claims are **unverified**.
- **Complaints.** Competitors cite 10–15% background CPU (notchy.dev; **unverified** vendor claim).
- **2026 crisis.**
  - MacMagazine (2026-09-16) reports a lo.cafe corporate dispute between co-founder Jorge Henrique and technical admin/founder Igor Marcossi over domain, Stripe, licensing and social accounts.
  - The app and site are offline. More than 3,000 refunds were issued before Stripe access was cut again. Setapp is discontinuing it (2026-09-22). lo.cafe advises users **not** to buy, renew or use NotchNook.
  - Snippets attributed to lo.cafe mention **NOOTCH**, a rebuilt successor with an HDR/EDR "liquid glass" shader down to macOS 15 and 90% off for lifetime holders, and say NotchNook "will probably go open-source". **Unverified**: the X post was not retrievable (HTTP 402).
- **Takeaway.** The most-copied UX in the category no longer has a functioning vendor, and its user base is actively searching for replacements.

### 2.2 Alcove (tryalcove.com): paid, closed

- **Price.** $14.99 one-time, all future updates included. Up to 3 devices, with device deactivation. 72 h trial, 14-day no-questions refund, no discounts. Earlier price was $16.99 (TodayOnMac, Feb 2025).
- **Version / requirements.** Site shows v1.7. Homebrew cask 1.7.7 requires **macOS 15+**. The FAQ notes the menu-bar icon can be hidden natively since macOS Tahoe.
- **Features.**
  - "Sticks to what Apple built into the Dynamic Island, and nothing more."
  - Fluid transitions, instant notifications (battery, connected devices, Focus), live activities, swipe gestures, customizable brightness and volume HUDs.
  - **Lock-screen widgets.** Calendar widget.
  - Same pill shape on non-notch Macs.
  - Swift-native.
- **Music apps.** Full metadata (art, duration, title) only for **Spotify and Apple Music**. Other sources show limited info (Lemon8 user report; **partially verified**).
- **Not included.** File shelf and AirDrop, clipboard, mirror (per competitor matrices; **unverified**).
- **Risk disclosure.** The FAQ says Alcove "relies on private APIs" and is sold "as is".
- **Privacy.** No data collection.
- **Note.** A GitHub org `Alcove-Dynamic` (created 2026-05-14) hosts an SEO-style README that links to a third-party `github.io` download, not tryalcove.com. It looks unofficial and should be treated as untrusted.

### 2.3 DynamicLake / DynamicLake Pro (dynamiclake.com, "Aviorrok"): paid, closed

- **Price.** $13.99 one-time via Gumroad (store listing shows 1399 cents). 30-day refund. PayPal accepted; multi-device activation. A figure of "$16.90 for 3 devices" appears in a search snippet (**unverified**).
- **Version.** Changelog latest is **1.9.7.5** (Sep 2026):
  - 1.9.7 added **Plugins, Market, Pill**.
  - 1.9.5.5 (2026-08-15) added **macOS 27** support.
  - 1.9.5 redesigned animations and added hover "Sneak Peek".
  - 1.9.4 overhauled DynaDrop and integrated macOS Clock timers.
  - 1.9.3 added a Music Queue for Apple Music and Spotify.
- **Minimum macOS.** Unverified.
- **Features** (branded modules):
  - DynaMusix (music).
  - DynaGlance (calendar and weather).
  - **Calls** (FaceTime and phone).
  - **Notifications** from iMessage, WhatsApp, Telegram, Slack and others.
  - DynaDrop (drag-and-drop actions: share link, convert audio and video via FFmpeg/LGPL).
  - DynaClip (file clipboard: move, share, AirDrop).
  - Timer; DynaConnect (Bluetooth and AirPods connect alerts); DynaKeys (media-key HUDs); battery and meeting alerts.
  - Volume, brightness and keyboard-backlight control; lock-screen widgets (TheSweetBits).
  - **Liquid Glass** island (external-display option); **miniLake** compact mode; BetterDisplay support; external displays.
  - Its FAQ asks "non-notch MacBooks?" but the answer was not retrievable (**unverified**).
  - A sister product, **Liqoria Notch Player**, is referenced.
- **Positioning.** Broadest paid feature set, with frequent releases and now a plugin marketplace. Competitors describe it as "shallow in spots".

### 2.4 MediaMate (Wouter01): paid, closed

- **Price.** Free demo; license **€6.99** (≈$7.93) on Gumroad.
- **Version / requirements.** 3.8.4 (2026-08-13, "support for macOS 27 Golden Gate"). macOS 13+. "All Macs supported" (Touch Bar Macs get a less reliable mode).
- **Features.**
  - Replacement HUDs for volume, brightness and keyboard backlight in several styles (iOS, classic, notch), including Liquid Glass variants.
  - Now Playing HUD, shown on notch hover.
  - AirPods and Beats device icons.
  - Works in fullscreen apps (fixed for macOS 26 in 3.8.2).
- **Positioning.** A single-purpose "HUD + Now Playing" app with no shelf or widgets. Long-lived and stable.

### 2.5 Droppy (getdroppy.app): paid, closed (formerly OSS)

- **Price.** $9.99 one-time (regional pricing in 126 countries). One key covers 2 devices. 3-day full trial, 14-day refund. **Droppy for iPhone** is included with the Mac license (E2E-encrypted clipboard, files and notes sync; 15 Droplets; Live Activity widgets).
- **Version / requirements.** Homebrew 16.0.1. macOS 14+, Apple Silicon and Intel, notch and non-notch (floating shelf). Multi-display.
- **Features.**
  - File shelf and tray with sharing and cloud links; clipboard history.
  - Media with album-art "motion art" and lyrics.
  - Live Activities (music, meetings, uploads, volume); notifications; brightness, volume and battery HUDs; per-app volume.
  - Meeting controls (Zoom, Teams, Meet); Pomodoro; screen-recording controls.
- **Extensions.** **38 free built-in "Droplets"**, including screenshot editor, window snapping, OCR, voice transcription, background removal, Obsidian, and **AI coding-agent monitoring** (Claude, Codex, Cursor). There is a **third-party Droplet ecosystem built with DroppyKit**: GitHub shows MIT-licensed droplets for NFL scores, dev-server ports, Homebrew, weather, markets and iPhone Live Activities, created Sep 2026.
- **History.** The original repo `github.com/iordv/Droppy` was **disabled by a GitHub DMCA notice (filed 2026-02-10 by Atoll's copyright holder)**. The notice alleges six files were GPL-3.0-derived from Atoll without compliance: Parallax3D, LockScreenManager, TemporaryFileStorageService, Brightness/VolumeManager, MediaKeyInterceptor. Droppy is now closed-source commercial.

### 2.6 Notchy (notchy.dev): free, closed

- **Business model.** Free, funded by donations (Ko-fi, Buy Me a Coffee). Solo developer (Vishva Variya).
- **Version / requirements.** v1.0.178 (2026-09-25). macOS **13** Ventura+ (lowest in the category). Floats as a pill on iMac, Mac mini, Studio and external displays. Localized into 134 languages.
- **Claimed features (74; vendor claims, not independently verified).**
  - Now Playing (Spotify and Apple Music, lyrics, playback speed, audio output switcher).
  - Shelf + AirDrop, image converter, zip; clipboard history with OCR; snippets; notes.
  - HUDs; battery and "full charge" alerts.
  - Reminders; download alerts; Messages and Call islands; Pomodoro and stopwatch; calendar; Focus detection.
  - AirPods per-bud battery; peripheral batteries; system mic mute.
  - **AI rate-limit tracking** (Claude Code, Codex, Cursor, Copilot; "60+ providers"); agent activity; shell activity; **notch terminal**.
  - **Face Unlock** (Apple Vision with liveness check); window snapping; DDC external-display brightness.
  - Stocks; Shortcuts runner; weather; camera mirror; privacy indicator; lock-screen widgets; WidgetKit desktop widgets.
  - **Local developer API on 127.0.0.1:9999**.
- **Note.** Very aggressive SEO (dozens of "alternative to X" pages). Maintains a fork of mediaremote-adapter (`vishvavariya/mediaremote-adapter`).

### 2.7 Seam (getseam.app): paid, closed

- **Price.** **$19.90** one-time. Up to 2 Macs. 48 h trial. At least one year of free updates, with a discount on major upgrades. 14-day refund.
- **Version / requirements.** v1.16.2. macOS 14+ (Homebrew `seam-app`). The "Apple Silicon only" claim comes from notchy.dev and is **unverified**. Localized EN, FR, DE, JA.
- **Features** (10 toggles): Lock Screen, Notifications, Sound & Display (HUD), Audio Devices, Battery, Focus, Live Activities, Now Playing (jump to browser tab, output-device picker, last track when paused), Calendar, Weather.
  - Focus timer.
  - **Ultra-fast 100% local voice transcription and translation.**
  - "Island mode" for iMac, Mac mini and external displays.
  - Claims 0.1% CPU and 33 MB RAM; only wakes on changes.
- **Not included.** File shelf and clipboard (per competitor claims).

### 2.8 Dynamic Notch (dynamicnotch.tech): paid, closed

- *Not to be confused with the OSS jackson-storm/DynamicNotch (§2.13).*
- **Price.** **$5.99** once, pay-what-you-want above that. LemonSqueezy is the merchant of record. Sparkle updates.
- **Version / requirements.** 4.0 (build 33). macOS 14.6+, **Apple Silicon (M1+) only**. 3.9 MB download, ~45 MB RAM, 0% CPU idle (2–5% when open). Signed and notarized. One anonymous install ping.
- **Modules (16).**
  - Media player, file tray (multi-file batches), clipboard history (skips password-manager fills), quick notes, "current task".
  - Colour picker with HEX, RGB, HSL, Swift output and WCAG AA/AAA contrast.
  - Calendar with Join (Zoom, Meet, Teams, Webex, FaceTime); timer.
  - System HUD (volume and brightness, plus Mac, AirPods, mouse and keyboard batteries); weather.
  - 7 panel themes and 9 bar themes (album-art tint).
  - AirDrop, camera mirror, download watcher, Finder shortcut, global hotkey ⌃⌥⌘N, display selection, **hide-notch mode**.
- Draws its own panel on non-notch displays.

### 2.9 Boring Notch (TheBoredTeam/boring.notch): free, GPL-3.0

- **Repo stats.** 10,919★, 1,069 forks, 394 open issues. Pushed 2026-09-30. Homepage theboring.name. Ko-fi and Discord.
- **Releases.** Stable **v2.7.3 "Flying Rabbit" (2025-11-24)**. **v2.8-rc.0/rc.1 "Dapper Crab" (2026-09-23/25)**. Nightly channel.
- **Requirements.** macOS 14+ (building needs macOS 15.6 and Xcode 26). Apple Silicon and Intel.
- **Distribution.** **Not signed or notarized** ("We don't have an Apple Developer account (yet)"); the user must run `xattr -dr com.apple.quarantine`. Homebrew tap `TheBoredTeam/boring-notch`.
- **Features (stable).**
  - Playback live activity with visualizer; album art.
  - Calendar and **Reminders**; mirror; charging indicator and percentage.
  - Customizable gestures; shelf with AirDrop (derived from NotchDrop).
  - Notch sizing per display; HUD replacement (volume, brightness, keyboard backlight).
- **Media sources** (code: `MediaControllers/`): **system Now Playing** via bundled `mediaremote-adapter` (so browsers and any app macOS sees), plus dedicated **Apple Music, Spotify and YouTube Music** (Pear desktop, WebSocket) controllers. Synced lyrics.
- **New in 2.8-rc.**
  - Compact player; remaining time; real-time waveform visualizer (macOS 14.2+ audio capture).
  - **Audio output routing** (AirPods, Bluetooth, external).
  - Weekly calendar; **join meetings from events** (Meet, Zoom, Teams, Webex, Whereby, Jitsi).
  - HUD renamed OSD; BetterDisplay and Lunar external brightness.
  - **Notification mirroring** (per-app filter, queue, closed-notch indicator; via Accessibility).
  - Battery wattage and time-to-empty; reverse shelf order; Quick Share; camera selection for mirror.
  - Reorganized settings; language picker; **Stable/Beta/Nightly update channels**; macOS 27 permission terminology.
- **Roadmap (unchecked).** Bluetooth live activity, weather, customizable layouts, **lock-screen widgets, extension system**. Notifications is "under consideration" (now RC).
- **Also.** An XPC helper (`BoringNotchXPCHelper`) and fullscreen media detection.
- **Weaknesses** (per competitors, **partially verified**): unsigned build, reported crashes after sleep and wake, no clipboard or weather yet.

### 2.10 Atoll (Ebullioscopic/Atoll): free, GPL-3.0

- **Repo stats.** 4,815★, 331 forks, 197 open issues. Pushed 2026-09-30. Homepage getatoll.app ("Atoll Labs", with a "Sign In" link: possible future account or commercial layer, **unverified**). Mirror org `Atoll-Labs/Atoll`. Backed by the iOS Development Centre at SRM Institute (Apple/Infosys).
- **Releases.** v2.3.3 (2026-07-24). 2.3.3 alpha and beta builds through 2026-09-07. Homebrew `atoll` 2.3.3.
- **Requirements.** macOS 14+ (optimized for 15+). **Only MacBooks with a notch** (14/16-inch MBP, Apple Silicon). Not for iMac, Mac mini or external displays.
- **Features.**
  - Media for Apple Music, Spotify, **YouTube Music, Amazon Music**, Cider and others (code: controllers for each plus Now Playing); animated artwork; AirPlay.
  - Live activities: media, Focus, **screen recording, privacy indicators, downloads (beta)**, battery and charging, reminders.
  - **Lock-screen widgets** for media, timers, charging, Bluetooth devices, weather (Open-Meteo) and reminders.
  - **System stats** (CPU, GPU, memory, network, disk; from Stats).
  - Timers, **clipboard history, colour picker**, calendar, **terminal tab** (SwiftTerm), LocalSend device picker.
  - **LLM usage tracking** (OpenUsage and OpenRouter pricing).
  - Caps Lock HUD; circular and vertical custom OSDs; BetterDisplay and Lunar.
  - Gestures with haptics; parallax hover; shortcut remapping.
  - **Extensions via AtollExtensionKit** (XPC service; extension live activities, lock-screen widgets and "notch experiences").
- **Lineage.** Built on Boring Notch (media, AirDrop, shelf, calendar). Inspired by Alcove's minimal mode. Battery HUDs from DynamicNotch.
- **Weakness.** Notched-MacBook-only; described as beta or unsigned by competitors.

### 2.11 NotchDrop (Lakr233/NotchDrop): free, MIT

- 2,116★. Last push 2026-05-18. No GitHub releases. **Mac App Store free**, v2.16 (2024-11-25), macOS 13+.
- **Features.** Drag files to the notch, AirDrop from the notch, auto-keep files for one day (configurable), menu-bar-manager compatible. Privacy-focused.
- **Significance.** A reference implementation. Its code seeded Boring Notch's shelf and the `NotchNotification` library.

### 2.12 MewNotch (monuk7735/mew-notch): free, GPL-3.0

- 554★. Release 2.2.2 (2026-06-30). Pushed 2026-09-17. Homebrew tap `monuk7735/tap/mew-notch`. **Unsigned.** Sparkle auto-update.
- **Features.**
  - HUDs for brightness (incl. auto-brightness, custom steps), output and **input** volume, power source with time remaining; option to suppress system HUDs.
  - Now Playing with controls; persistent file shelf; mirror.
  - **Bash script view**; notch shown **on lock screen**; custom layout.
  - **Choose which displays show the notch**; Touch Bar support.
- **Roadmap.** Keyboard-backlight HUD; shelf with lock-screen mode.
- **Minimum macOS.** Not stated (Xcode targets 14.0 and 15.2; **unverified**).

### 2.13 DynamicNotch (jackson-storm/DynamicNotch): free, GPL-3.0

- 581★. v1.6.2 (2026-09-06). Pushed 2026-09-29. macOS 14.6+. Funded by donations (Boosty, crypto).
- **Positioning.** Its "own engine" with iOS-faithful spring physics and morphing (not forked from Boring Notch).
- **Live activities.** Now Playing (visualizer, LRCLIB lyrics), downloads, AirDrop, timer, **screen recording**, Focus, personal hotspot, lock-screen media.
- **Temporary alerts.** Battery (charging, low, full), **Bluetooth, Wi-Fi, VPN**.
- **Other.** Gesture dismissal; **floating capsule on non-notch displays** (iMac, mini, external); display selection; fullscreen Spaces handling; 38+ languages.

### 2.14 SuperIsland (shobhit99/SuperIsland; dynamicisland.app): free, source-available

- 670★. 1.0.10 (2026-06-12). Pushed 2026-09-13. macOS 14+.
- **Licensing.** The website says "free and open source", but **the repo has no LICENSE file**, so there are no OSI rights. Notarized-release scripts exist.
- **Modules.**
  - Now Playing (system media, Apple Music, Spotify, **opt-in Chromium browser detection**).
  - Battery and power; weather (hourly).
  - Calendar (account filters, meeting links).
  - **Notifications** (extension sources, bundled WhatsApp Web integration, public app broadcasts).
  - File shelf (files, folders, URLs, text, images); volume, brightness and keyboard-backlight HUDs.
  - Energy profiles (Normal, Smart, Low Power).
- **Extensions.** **JavaScript extensions in a sandboxed JavaScriptCore host with a declarative view system rendered natively in SwiftUI.** Bundled examples include Pomodoro and WhatsApp Web. Docs at dynamicisland.app/docs.

### 2.15 Cyclop (akalikbergenov/cyclop): free, MIT

- 345★, 70 forks. v0.8.2 (2026-09-17). macOS 15+. **Developer-ID signed and notarized.**
- **Footprint.** 0.0% CPU at rest, ≈40 MB + 14 MB helper, 3.7 MB bundle.
- **Permissions.** Only calendar, requested on an explicit button. Now Playing uses a helper hosted in `/usr/bin/perl`, so no Automation or Accessibility permission is needed.
- **Tabs.** Music (any source, incl. browser tabs), Shelf (screenshots auto-land), Clipboard (40), Snippets (JSON file), Calendar with Join, **offline Translate** (Translation.framework), Currency, **Teleprompter**, Notes.
- **Other.** Every tab can be disabled, which also stops its background work. Treats a 180×24 pt top-centre area as the notch on non-notch Macs.
- **Takeaway.** A good model for privacy-minimal, low-overhead design.

### 2.16 Sapphire (cshariq/Sapphire): freemium, AGPL-3.0 source

- 240★. v3.0 (2026-09-15).
- **Free.**
  - **Android Nearby Share** to Mac; Now Playing (works on 15.5); per-app volume and **10-band EQ**, multi-device routing.
  - Eye-break reminders; weather; Gemini Live screen sharing; calendar; lock screen.
  - File shelf + AirDrop; **Snap Zones** window tiling; Bluetooth fast-connect; Caffeinate; clipboard.
  - Battery charge limits; XDR brightness boost; notes; banner notifications; Shortcuts.
- **Paid (Pro/Ultra).** "Blip" AI agent across native apps, Blip Live, Circle to Search, sports and finance live activities, camera Face ID unlock.
- **Pricing.** Amounts **unverified**. notchy.dev claims $15.99–$30.99/mo plus per-Mac surcharges.

### 2.17 Vibe Island (vibeisland.app): paid, closed; AI agents

- **Price.** $19.99 one-time for 1 Mac; 2- and 3-Mac tiers; free trial.
- **Version.** Homebrew 1.0.51; macOS 14+.
- **Agents.** 25–30 supported: Claude Code, Codex, Gemini CLI, Cursor, Copilot, Kiro, Amp, Devin, Qwen, Kimi and others.
- **Terminals.** Jump to 20+ terminals and IDEs, including tmux and split panes.
- **Features.**
  - GUI approvals and question answering.
  - **Plan review** (Markdown).
  - Usage and quota windows.
  - **SSH remote** agents.
  - 8-bit sounds; zero-config hook install.
  - <50–100 MB RAM; local-only.
- **Competition.** Spawned OSS clones: Open Island, agent-notch, and others.

### 2.18 Open-source AI-agent notch apps (group)

**Shared mechanism.** Most install **agent hooks** (e.g. `~/.claude/hooks/`, Codex hooks) that send JSON over a **Unix socket** to the notch app.

- **Vibe Notch** (Apache-2.0, 2.5k★). The original "Claude Island".
  - Features: permission approvals, chat history.
  - macOS 15.6+.
  - Reactivated in Apr 2026 after a 4-month break.
- **CodeIsland** (MIT, 2.4k★). 30+ tools.
  - Session cards: task-checklist progress, git branch and worktree, Claude plan limits.
  - Controls: approve, deny or always-allow; global shortcuts.
  - Behaviour: smart suppress; quiet hours; hides in fullscreen.
  - Extras: SSH hosts, **iPhone/Watch and ESP32 buddies**, push to Slack, Telegram, ntfy and others; webhooks.
- **Open Island** (GPL-3.0, 2.0k★). 13 agents, including Codex Desktop via JSON-RPC and Claude Desktop, and 15+ terminals and IDEs. Local-first, no telemetry.
- **Ping Island** (Apache-2.0, 1.1k★). 17 clients; detachable pet; Homebrew cask.
- **Notchi** (GPL-3.0, 1.0k★). Pixel-sprite mascots; optional sentiment analysis via an Anthropic or OpenAI key; 30-day cost and token tracking; signed via GitHub Sponsors funding; community Windows port.
- **Notch Pilot** (MIT). Reads the Claude Code OAuth token to show *real* 5-hour and weekly utilization; diff previews in approvals; dangerous-command detection; activity heatmap.

### 2.19 Other paid or freemium hubs (brief)

- **Brow.**
  - Model: freemium utility suite; Pro $4.99/mo or $49/yr.
  - Notch widgets and a file drop zone are a small part of 40+ tools.
  - Notch features are optional and work on non-notch Macs.
- **NotchBay** ($9 one-time, Ossian design lab).
  - Call controls: Zoom and Meet mute, camera and leave, with a call timer; Teams "coming soon".
  - Clipboard tray: 60 items with OCR.
  - Other: on-device dictation (⌥⌘M), Claude Code and Codex session tracking, next meeting, Focus, Caps Lock, storage indicators.
  - Floating island on notchless or external displays; fully local.
- **Crest** (free with 5 widgets; Pro $19.99).
  - 18 resizable widgets: Shelf (AirDrop, compress, convert), clipboard, system, notes, **pull requests**, **agents**, weather, focus timer, batteries, Now Playing (lyrics, queue), calendar with Join, reminders, controls, **Claude chat**, notification mirror, **SSH hosts**.
  - Home, Work and Code "modes" with auto-switching; 12 window layouts.
  - Sister apps **Take** (recording) and **Minutes** (meeting recording).
  - macOS 14+; signed; no analytics.
- **OneNotch** (free; Pro $9.99 lifetime).
  - Clipboard boards and stacks; AI-agent status with approvals and quota; lyrics; screenshots and markup; smart-selection translation and currency; window layouts; file drop; calendar and timers.
  - Pill mode on non-notch displays; macOS 15+, Apple Silicon.
- **NotchSpace** ($19.99, sale $16).
  - Multi-display notch; clipboard with image OCR; temp shelf; desktop widgets; **AI file organizer**; **expense tracker**; workspace launcher; Pomodoro; natural-language reminders.
  - Spotify, Apple Music and YouTube (browser playback) with lyrics; HUD for volume, brightness, downloads and charging; system stats.
  - "Pings" (invite-only nudges between people).
  - macOS 14; Apple Silicon and Intel.
- **MacNotch** (MacPaw/Setapp; v1.9.9.6, macOS 14).
  - Media: Spotify, Apple Music, YouTube and browsers.
  - Calendar countdowns; Pomodoro; Reminders tasks; notes; widget grid with weather, launchers and toggles (Dark Mode, True Tone, Night Shift).
  - Bluetooth batteries; AirDrop, zip and image conversion; HUDs.
  - A Setapp-native competitor that inherits NotchNook's Setapp slot.
- **Perch** (App Store; free + subscription or lifetime; macOS 13).
  - Media, weather, camera, calendar, timer and stopwatch, snippets, file tray, AI chat, fullscreen compatibility.
  - Reviews complain about upsell prompts.
- **NotchNest** (Mac App Store; free + $2.99/mo or $14.99 lifetime; macOS 14, Apple Silicon).
  - Apple Intelligence-powered clipboard and meeting briefings; Pomodoro; AirDrop; Spotify and Apple Music; mirror; bookmarks; battery.
- **NotchBox** (free + $4.99 Pro).
- **Nook X** (App Store; lyrics, AI).
- **Pulse Island** (7-day trial; browser-tab media, window switcher, clipboard).
- **Canopy** (lyrics, Liquid Glass lock-screen widget, notification mirroring; €15 **unverified**).
- **OmniNotch** ($9 → $19.99; 20 tools).
- **Notchable** (task manager; $9.99 on-device AI or $19.99 cloud AI).
- **QuakeNotch** (terminal; free + $14).
- **TickerNotch** (markets; free + $40 lifetime).

### 2.20 Notch hiders and decorators (brief)

- **TopNotch** (MTW, free, macOS 11+). Blacks out the menu-bar strip in the wallpaper so the notch disappears. Handles dynamic wallpapers, multi-display and Spaces; optional rounded corners.
- **Notchmeister** (Iconfactory, free, BSD-3 source). Novelty effects that react to the cursor near the notch; <1 MB.
- **NotchCam** (Mac App Store, ~$1 originally).
  - Webcam preview on notch click; simulated notch on other Macs; wallpaper blackout; multi-display.
  - Current status and price are **unverified**.
- **Hot** (macmade, MIT, 3.0k★). **Not a notch app.** A menu-bar CPU thermal-limit monitor, last released 2024-07.

---

## 3. Master feature matrix

**Columns (12 most relevant competitors):**

| Code | App |
|---|---|
| **BN** | Boring Notch (stable 2.7.3; "rc" = in v2.8-rc) |
| **AT** | Atoll |
| **MN** | MewNotch |
| **DN** | DynamicNotch (OSS, jackson-storm) |
| **SI** | SuperIsland |
| **NN** | NotchNook (offline) |
| **AL** | Alcove |
| **DL** | DynamicLake Pro |
| **DR** | Droppy |
| **NY** | Notchy (notchy.dev, vendor claims) |
| **SE** | Seam |
| **DNt** | Dynamic Notch ($5.99) |

**Cell values:** ✅ yes · ◐ partial / beta / plugin · ❌ no · ? unverified.

| Feature | BN | AT | MN | DN | SI | NN | AL | DL | DR | NY | SE | DNt |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| **Price** | Free | Free | Free | Free | Free | $25 / $3/mo | $14.99 | $13.99 | $9.99 | Free | $19.90 | $5.99 |
| **Open source** | ✅ GPL-3 | ✅ GPL-3 | ✅ GPL-3 | ✅ GPL-3 | ◐ no license | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| **Signed / notarized build** | ❌ | ? (3rd-party: no) | ❌ | ? | ◐ (notarize scripts; releases unverified) | ✅ (Setapp-distributed) | ? | ? | ✅ | ? | ? | ✅ |
| **Media controls** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Apple Music / Spotify | ✅/✅ | ✅/✅ | ✅ via Now Playing | ✅ via Now Playing | ✅/✅ | ✅/✅ | ✅/✅ | ✅/✅ (queue) | ? | ✅/✅ | ? | ✅ (system audio) |
| Browser media (YouTube etc.) | ✅ (Now Playing) | ✅ | ✅ | ✅ | ◐ opt-in Chromium | ? | ◐ limited metadata | ? | ? | ? | ✅ (jump to tab) | ✅ |
| YouTube Music app / other players | ✅ YT Music (Pear) | ✅ YT Music, Amazon, Cider | ? | ? | ? | ❌ Podcasts / QuickTime (2024) | ? | ? | ? | ? | ? | ? |
| Synced lyrics | ✅ | ? | ❌ | ✅ | ? | ? | ? | ? | ✅ | ✅ | ? | ? |
| Audio output switcher | ◐ rc | ✅ | ❌ | ? | ? | ? | ? | ? | ◐ per-app volume | ✅ | ✅ | ? |
| **File shelf** | ✅ | ✅ | ✅ | ? | ✅ | ✅ | ❌ | ✅ | ✅ | ✅ | ❌ | ✅ |
| AirDrop from notch | ✅ | ✅ | ? | ◐ AirDrop activity | ? | ✅ | ❌ | ✅ | ✅ | ✅ | ❌ | ✅ |
| **Calendar** | ✅ (+join links rc) | ✅ | ❌ | ? | ✅ (+join) | ✅ | ✅ | ✅ | ? | ✅ | ✅ | ✅ (+join) |
| **Reminders / to-do** | ✅ | ✅ | ❌ | ❌ | ? | ✅ to-do widget | ? | ? | ? | ✅ | ? | ◐ current task |
| **Battery / charging HUD** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **Volume / brightness HUD replacement** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ (optional) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Keyboard backlight HUD | ✅ | ✅ | ❌ (roadmap) | ? | ✅ | ? | ? | ✅ | ? | ✅ | ? | ? |
| **Notifications (app banners)** | ◐ rc (mirroring) | ? | ❌ | ◐ system alerts only | ✅ | ? | ◐ system events (battery, devices, Focus) | ✅ iMessage / WhatsApp / Telegram / Slack | ✅ | ✅ Messages / calls | ✅ | ? |
| Calls (FaceTime / phone / meetings) | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ? | ✅ | ✅ meeting controls | ✅ | ? | ❌ |
| **Timers / Pomodoro** | ❌ | ✅ | ❌ | ✅ | ◐ ext | ✅ | ? | ✅ | ✅ | ✅ | ✅ focus timer | ✅ |
| **Clipboard history** | ❌ | ✅ | ❌ | ? | ◐ text in shelf | ? | ❌ | ◐ file clipboard | ✅ | ✅ | ❌ | ✅ |
| **Webcam mirror** | ✅ | ✅ | ✅ | ? | ? | ✅ | ❌ | ? | ? | ✅ | ? | ✅ |
| **Weather** | ❌ (roadmap) | ✅ (lock screen) | ❌ | ? | ✅ | ? | ? | ✅ | ◐ 3rd-party Droplet | ✅ | ✅ | ✅ |
| **System stats (CPU / RAM / net)** | ❌ | ✅ | ❌ | ❌ | ? | ❌ | ❌ | ? | ? | ✅ | ❌ | ❌ |
| **Lock-screen widgets** | ❌ (roadmap) | ✅ | ◐ HUD on lock screen | ✅ | ? | ? | ✅ | ✅ | ? | ✅ | ✅ | ? |
| **Focus / DND indicator** | ? | ✅ | ❌ | ✅ | ? | ? | ✅ | ? | ? | ✅ | ✅ | ? |
| **Bluetooth / AirPods connect** | ◐ output routing rc | ✅ | ❌ | ✅ | ? | ✅ | ✅ | ✅ | ? | ✅ | ✅ audio devices | ✅ battery levels |
| **Downloads progress** | ◐ (code present) | ✅ beta | ❌ | ✅ | ? | ? | ? | ? | ◐ uploads | ✅ | ? | ✅ watcher |
| **Screen-recording indicator** | ? | ✅ | ❌ | ✅ | ? | ? | ? | ? | ✅ controls | ✅ privacy indicator | ? | ❌ |
| **AI / agent integration** | ❌ | ◐ LLM usage | ❌ | ❌ | ◐ via ext | ❌ | ❌ | ❌ | ✅ agent Droplet | ✅ rate limits + agents | ◐ local transcription | ❌ |
| **Shortcuts / hotkeys** | ✅ hotkeys | ✅ remap | ❌ | ? | ? | ✅ Apple Shortcuts | ? | ✅ DynaKeys | ? | ✅ Shortcuts runner | ? | ✅ hotkey |
| **Plugins / extensions API** | ❌ (roadmap) | ✅ AtollExtensionKit | ◐ bash script view | ❌ | ✅ JS SDK | ❌ | ❌ | ✅ Plugins + Market | ✅ Droplets / DroppyKit | ◐ local HTTP API | ❌ | ❌ |
| **Multi-display** | ✅ | ❌ | ✅ | ✅ | ? | ? | ? | ✅ | ✅ | ✅ | ✅ | ✅ |
| **Non-notch Mac support** | ✅ | ❌ | ✅ | ✅ floating capsule | ✅ | ✅ | ✅ pill | ◐ (FAQ, answer unverified) | ✅ | ✅ | ✅ Island mode | ✅ |
| **Fullscreen handling** | ✅ fullscreen-media detection | ? | ? | ✅ Spaces handling | ? | ? | ? | ? | ? | ? | ? | ? |
| **Intel support** | ✅ | ❌ | ? | ? | ✅ universal | ✅ | ? | ? | ✅ | ? | ? (3rd-party: no) | ❌ |
| **Min macOS** | 14 | 14 | ~14 | 14.6 | 14 | 14.6 | 15 | ? | 14 | 13 | 14 | 14.6 |

**Matrix notes.**
- NotchNook cells describe the product as last sold. It is currently unobtainable.
- Notchy cells are vendor claims.
- "?" usually means the vendor does not document it. Treat it as "probably not" for marketing comparisons, but do not publish it as a fact.

---

## 4. Market dynamics, risks and opportunities (for a new OSS entrant)

1. **Demand is proven and growing.**
   - Boring Notch went from 0 to 10.9k★ in about two years.
   - The agent-notch niche produced five 1k+★ repos in under a year.
   - There are 400+ repos tagged `notch`+`macos` and 200+ tagged `dynamic-island`+`macos`.
   - At least 20 paid apps compete at $5–$25.
2. **The NotchNook vacuum.** The most-reviewed paid app is gone, and Setapp and Homebrew have delisted it. Users searching "NotchNook alternative" in late 2026 are a ready audience. Signed builds and a migration or import story could capture them.
3. **Private-API fragility.**
   - macOS 15.4 broke third-party Now Playing (`MRMediaRemoteGetNowPlayingInfo` returns "Operation not permitted"). FB17228659, which asks for a public API, is still open.
   - The ecosystem converged on `mediaremote-adapter` (Perl-hosted helper). Alternatives are per-player distributed notifications and AppleScript (Perch, Cyclop fallback) or SIP-disabling injection (MediaRemoteWizard; not viable).
   - HUD replacement relies on media-key interception (Accessibility / Carbon events). Lock-screen UI relies on SkyLight private windows.
   - Every macOS release (26 Tahoe, 27 "Golden Gate") triggers compatibility releases: MediaMate 3.8.2 and 3.8.4, DynamicLake 1.9.5.5, Boring Notch 2.8.
4. **Apple as competitor.**
   - Bloomberg and MacRumors (Feb 2026) report an OLED touchscreen MacBook Pro with a real, interactive Dynamic Island replacing the notch. AppleInsider (Jun 2026) puts it at late 2026 to early 2027.
   - If Apple ships a first-party island API, third-party notch hubs lose novelty. Apps that support non-notch displays and offer deeper extensibility would be least affected.
5. **Licensing and trust.**
   - The Atoll → Droppy DMCA (GPL-3.0) shows that forking from Boring Notch or Atoll locks a project into GPL.
   - A permissive (MIT/Apache) clean-room codebase, or a clear GPL strategy, is a real differentiator for contributors and downstream embedders.
   - Unsigned builds (Boring Notch, MewNotch, Atoll) are the #1 onboarding friction. Cyclop and Notchi show that an OSS project can fund an Apple Developer ID through sponsors.
6. **Differentiation vectors seen in 2026.**
   - Extension ecosystems: JS in SuperIsland, XPC in Atoll, Droplets in Droppy, marketplace in DynamicLake.
   - AI-agent monitoring and approvals.
   - On-device AI (transcription in Seam, NotchBay, Droppy; Apple Intelligence in NotchNest; local LLM in Notchable).
   - Face Unlock (Notchy, Sapphire).
   - iPhone companion apps (Droppy, CodeIsland).
   - Meeting-join and call controls.
   - Low resource use as a marketing claim (Seam 33 MB, Dynamic Notch 45 MB, Cyclop 40 MB).
   - Privacy-minimal permissions (Cyclop).
7. **Unmet combination (white space).**
   - A **signed, permissively licensed, plugin-first** notch platform.
   - It would pair a small, stable core (media via `mediaremote-adapter`, shelf + AirDrop, HUD, calendar/reminders, battery/Bluetooth) with a documented extension API.
   - Agent monitoring (hooks over a Unix socket) would ship as a first-party plugin.
   - Non-notch, multi-display and fullscreen handling would be first-class.
   - No current product checks all of these boxes.

---

## 5. Sources

### Official sites, stores and package managers
- NotchNook: https://lo.cafe/notchnook (DNS unresolvable 2026-09-30) · MacUpdate https://notchnook.macupdate.com/ · Homebrew cask API https://formulae.brew.sh/api/cask/notchnook.json · https://formulae.brew.sh/cask/notchnook
- Alcove: https://tryalcove.com · https://tryalcove.com/faqs · https://formulae.brew.sh/api/cask/alcove.json
- DynamicLake: https://www.dynamiclake.com/ · https://www.dynamiclake.com/changelog · https://avirok1.gumroad.com/
- MediaMate: https://wouter01.github.io/MediaMate/ · https://wouter01.gumroad.com/l/mediamate · https://github.com/Wouter01/MediaMate-Releases/releases · https://formulae.brew.sh/cask/mediamate
- Droppy: https://getdroppy.app/ · https://getdroppy.app/compare · https://getdroppy.app/blog/best-mac-notch-apps-2026 · https://formulae.brew.sh/api/cask/droppy.json
- Notchy: https://notchy.dev/ · https://notchy.dev/best-mac-notch-apps/ · https://notchy.dev/uninstall-notchnook/
- Seam: https://getseam.app/ · https://formulae.brew.sh/api/cask/seam-app.json
- Dynamic Notch: https://www.dynamicnotch.tech/ · https://www.dynamicnotch.tech/best-mac-notch-apps
- SuperIsland: https://dynamicisland.app/
- Sapphire: https://sapphire-app.tech/
- Brow: https://brow-app.com/ · https://brow-app.com/blog/best-macbook-notch-apps-2026
- NotchBay: https://notchbay.com/
- Crest: https://crestnotch.app/crest
- OneNotch: https://www.tryonenotch.com/
- NotchSpace: https://www.notchspace.com/ · https://www.producthunt.com/products/notchspace-2
- MacNotch: https://setapp.com/apps/macnotch
- Perch: https://apps.apple.com/us/app/dynamic-notch-island-perch/id6742724228?mt=12
- NotchNest: https://notchnest.app/
- NotchBox: https://apps.apple.com/us/app/notchbox-easier-drag-drop/id6737410946?mt=12
- Nook X: https://apps.apple.com/mt/app/nook-x-notch-screen-tool/id6733240772
- Pulse Island: https://www.pulseisland.club/ · https://www.producthunt.com/products/pulse-island
- Canopy: https://getcanopy.pro/
- OmniNotch: https://omninotch.app/
- Notchable: https://notchable.com/
- QuakeNotch: https://quakenotch.com/
- TickerNotch: https://bitvibelabs.com/tickernotch/
- Tuneful: https://tuneful.app/
- Vibe Island: https://vibeisland.app/ · https://vibeisland.app/best-ai-agent-notch-apps/
- Vibe Notch: https://vibenotch.app/
- Notchi: https://notchi.app/
- Atoll: https://getatoll.app/ · https://formulae.brew.sh/api/cask/atoll.json
- TopNotch: https://topnotch.app/
- Notchmeister: https://apps.apple.com/us/app/notchmeister/id1599169747
- NotchCam: https://apps.apple.com/us/app/notchcam-quick-camera-access/id1593584739?mt=12
- NotchDrop (Mac App Store): https://apps.apple.com/us/app/notchdrop/id6529528324?mt=12
- Cronus: https://cronushq.com/blog/mac-notch-apps

### GitHub repositories (stats via GitHub API, 2026-09-30)
- https://github.com/TheBoredTeam/boring.notch (releases v2.7.3, v2.8-rc.0, v2.8-rc.1)
- https://github.com/Ebullioscopic/Atoll · https://github.com/Ebullioscopic/AtollExtensionKit · https://github.com/Atoll-Labs/Atoll
- https://github.com/Lakr233/NotchDrop · https://github.com/Lakr233/NotchNotification · https://github.com/Lakr233/SkyLightWindow
- https://github.com/monuk7735/mew-notch
- https://github.com/MrKai77/DynamicNotchKit
- https://github.com/jackson-storm/DynamicNotch
- https://github.com/shobhit99/SuperIsland
- https://github.com/akalikbergenov/cyclop
- https://github.com/cshariq/Sapphire
- https://github.com/navtoj/NotchBar
- https://github.com/chockenberry/Notchmeister
- https://github.com/Celve/Peninsula
- https://github.com/martinfekete10/Tuneful
- https://github.com/AryanRogye/ComfyNotch
- https://github.com/Clayton630/QuartzNotch
- https://github.com/MuQY1818/OpenYoink
- https://github.com/aymandakirgh/ghnotch
- https://github.com/BadRat-in/MacIsland
- https://github.com/crissNb/Dynamic-Island-Sketchybar
- https://github.com/TopMyster/Ripple
- https://github.com/twinkling-reality/opennook
- https://github.com/farouqaldori/vibe-notch
- https://github.com/wxtsky/CodeIsland
- https://github.com/Octane0411/open-vibe-island
- https://github.com/erha19/ping-island
- https://github.com/sk-ruban/notchi
- https://github.com/adamlyttleapps/notchy
- https://github.com/MioMioOS/MioIsland
- https://github.com/realfishsam/agent-notch
- https://github.com/trustunsafe/Notch-Pilot
- https://github.com/vibeislandapp/vibe-island
- https://github.com/basionwang-bot/HermesPet
- https://github.com/ericjypark/codex-island
- https://github.com/macmade/Hot
- https://github.com/jacklandrin/OnlySwitch
- https://github.com/ungive/mediaremote-adapter
- https://github.com/TheBoredTeam/MacroVisionKit
- https://github.com/exelban/stats
- https://github.com/rohanrhu/QuakeNotch
- Droppy DMCA notice: https://github.com/github/dmca/blob/master/2026/02/2026-02-10-atoll.md (iordv/Droppy returns HTTP 451)
- Unofficial Alcove org (untrusted): https://github.com/Alcove-Dynamic/.github

### News, reviews and comparisons
- MacMagazine, "Crise na lo.cafe deixa NotchNook fora do ar…" (2026-09-16): https://macmagazine.com.br/post/2026/09/16/crise-na-lo-cafe-deixa-notchnook-fora-do-ar-e-usuarios-sem-reembolso/
- Igor Marcossi on X (not retrievable, HTTP 402): https://x.com/IMarcossi/status/2102731577423782104
- Macworld NotchNook review (Jul/Aug 2024): https://www.macworld.com/article/2406934/notfhnook-macbook-dynamic-island-widgets-files-tray.html
- How-To Geek, "These Apps Turn Your MacBook Notch Into a Dynamic Island" (2024-10-01): https://www.howtogeek.com/these-apps-turn-your-macbook-notch-into-a-dynamic-island/
- TodayOnMac, Alcove (2025-02-06): https://www.todayonmac.com/alcove-dynamic-island-getaway/
- TheSweetBits, DynamicLake Pro review (updated 2026-07-05): https://thesweetbits.com/tools/dynamiclake-review/
- Cronus, "Best MacBook Notch Apps 2026" (2026-08-10): https://cronushq.com/blog/mac-notch-apps
- Product Hunt NotchNook alternatives: https://www.producthunt.com/products/notchnook/alternatives
- Lemon8 user note on Alcove media metadata: https://www.lemon8-app.com/@life.of.aye/7479483773328687662?region=us
- MediaRemote restriction (FB17228659): https://github.com/feedback-assistant/reports/issues/637
- MacRumors, OLED touchscreen MacBook Pro with Dynamic Island (2026-02-24): https://www.macrumors.com/2026/02/24/touchscreen-macbook-pro-dynamic-island/
- AppleInsider, 2027 MacBook Pro rumors (2026-06-26): https://appleinsider.com/articles/26/06/26/oled-touchscreen-and-more-what-to-expect-from-the-2027-macbook-pro
- Fast Company, notch workaround apps (NotchCam, 2021): https://www.fastcompany.com/90690822/macbook-pro-notch-workaround-apps
- Vendor comparison pages used for discovery only (biased):
  - https://getseam.app/blog/notchnook-alternatives
  - https://notchbay.com/blog/notchnook-alternatives/
  - https://notchable.com/blog/best-mac-notch-apps-2026
  - https://www.tryonenotch.com/blog/best-mac-notch-apps-2026
  - https://crestnotch.app/best-mac-notch-apps
