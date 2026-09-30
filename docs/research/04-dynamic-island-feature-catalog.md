# 04 — Dynamic Island Feature Catalogue: iPhone, Mac Menu-Bar Live Activities, Android, and What Islet Should Build

**Snapshot date:** 2026-09-30
**Scope:**
- The iPhone Dynamic Island through **iOS 27** and the **iPhone 18 Pro**.
- Live Activities on Apple Watch, CarPlay, iPad and the **Mac menu bar**: macOS 26 Tahoe, then macOS 27 Golden Gate.
- Android equivalents.
- A prioritized feature list for Islet.

**Read with:**
- `01-market-analysis.md`: the competitors.
- `02-pain-points.md`: user complaints and requests.
- `03-integrations-feasibility.md`: which macOS APIs work. Its A–D feasibility grades are reused here.

**Verification legend**

| Tag | Meaning |
|---|---|
| **[V]** | Checked on 30 September 2026 against the cited page (Apple HIG and DocC, WWDC session pages, Apple Support, press articles). |
| **[S]** | Seen only in a search-engine result summary; the page itself was not opened. |
| **[U]** | **Unverified.** From prior knowledge (to mid-2026) or one weak secondary source. Re-check before publishing. |

> **Method and limits.** Several sources could not be fetched during the research; entries that rest on them are marked unverified.
>
> These planned checks could not be finished, so they are tagged [U]:
> - per-app confirmation of third-party iPhone Live Activities;
> - the Android skins other than Samsung and Google;
> - the exact look of each iPhone system alert.
>
> Nothing here is invented. Details from memory are tagged. Quotes are under 15 words.

---

## 0. Key findings

1. **Apple's model is four presentations.** It is the same on every surface.
   - **Compact:** a leading and a trailing view hugging the camera.
   - **Minimal:** used when several activities run. One view is attached to the island, one is a detached circle or oval.
   - **Expanded:** shown on touch-and-hold, or briefly for an alert.
   - **Lock Screen card.**

   Apple reused these unchanged for the **Mac menu bar**, **CarPlay** and the **Apple Watch Smart Stack** [V]. Islet should adopt the same contract. It will feel familiar, and it would map directly onto a Mac-native ActivityKit if Apple ships one.
2. **2026 changes.**
   - **iPhone 18 Pro** (Apple event 2026-09-09) has a *smaller* island that can show **up to three** Live Activities at once [V]. The arrangement is not documented in the sources reached.
   - **iOS 27** (released 2026-09-14):
     - Live Activities now show in **landscape**. There the compact width cannot grow, and apps read the new `isDynamicIslandLimitedInWidth` value [V].
     - **Siri moves into the island**, as an orb with compact answers around it [V].
     - A **swipe down from the island** opens "Search or Ask" [V].
3. **iOS 26 (2025) additions:**
   - scheduled Live Activities [V];
   - a Fitness workout Live Activity with a pause control [V];
   - shareable Wallet boarding-pass Live Activities [V];
   - CarPlay and Mac menu-bar surfaces [V];
   - a low-battery alert in the island with a Low Power Mode prompt [S].
4. **Mac today (macOS 26+).**
   - iPhone Live Activities appear in the menu bar as a pill showing the **compact leading and trailing views**, or a small icon when space is short.
   - A click shows the Lock Screen / expanded view. A further click (or a double-click on the menu-bar item) opens the app in **iPhone Mirroring**. Buttons work.
   - The iPhone needs **iOS 18+**, and developers change nothing [V].
   - **macOS 27 added nothing Apple-announced** for Mac Live Activities. There is still no Mac-native ActivityKit and no public API for reading these activities [V absence].
   - → Islet should not try to mirror iPhone activities. It should own **Mac-native** activities.
5. **Android ideas neither iPhone nor Mac notch apps have:**
   - drag an activity **out** of the island to share it (Xiaomi) [S];
   - pull down to open a **floating mini-window** (Xiaomi) [V];
   - **segmented progress with milestone points and a moving tracker icon** (Android 16 ProgressStyle) [V];
   - **three-metric live dashboards** (Android 17 MetricStyle) [V];
   - AI **time-of-day briefs** in the same pill (Samsung Now Brief) [V];
   - a **vertical swipe through stacked activities, plus long-press to item settings** (Samsung) [V];
   - strict **"ongoing, user-started only; no ads or chat"** eligibility rules (Android) [V].
6. **Islet's biggest parity gaps** (from its current source):
   - `Presenter` shows **one** compact item plus an "others" count. There is no minimal view and no detached bubble.
   - No stale-date, relevance, alert or dismissal semantics.
   - No segmented or metric templates.
   - No iPhone-style device-event "splash" set (AirPods, charging, mute, Focus, unlock).
   - The gesture set is hover and click only.

---

## 1. iPhone Dynamic Island

### 1.1 Timeline

| When | Change | Tag |
|---|---|---|
| Sep 2022 · iPhone 14 Pro, iOS 16 | Dynamic Island introduced: system alerts and background activities | [U] (widely known) |
| iOS 16.1 | Third-party Live Activities (ActivityKit). Swipe gestures to minimize or restore. | gestures [V Six Colors]; date [U] |
| iOS 16.2 | `relevanceScore`; frequent-updates Info.plist key | [V DocC] |
| iOS 17 (2023) | Interactive Live Activities (Button and Toggle via App Intents); StandBy; automatic content animations | [V] |
| iOS 17.2 | Push-to-start tokens | [V] |
| iOS 18 (2024) | Watch Smart Stack; broadcast channels; `.transient` style (e.g., Music's AirPlay-to-HomePod prompt); new flashlight UI inside the island | [V]/[S] |
| iOS 26 (2025) | Scheduled start; CarPlay Dashboard; Mac menu bar; Fitness workout Live Activity; shareable boarding-pass Live Activity; iPadOS Background Tasks Live Activity; low-battery island alert with Low Power Mode | [V]/[S] |
| **iOS 27 (2026-09-14)** | Live Activities in **landscape** (`isDynamicIslandLimitedInWidth`); **Siri orb inside the island**; **swipe-down Search or Ask** | [V] |
| **iPhone 18 Pro (announced 2026-09-09)** | Smaller island; **up to three simultaneous Live Activities** | [V] |

### 1.2 Interaction model

**Presentations** (HIG and DocC) [V]:

- **Compact**
  - Used when one Live Activity is running.
  - A leading view and a trailing view sit either side of the TrueDepth camera and should read as one unit.
  - HIG: keep it "snug against the TrueDepth camera"; no padding next to the camera.
  - Keep the two widths balanced. Both sides link to the same screen.
- **Minimal**
  - Used when two or more activities run.
  - The system shows two: one **attached** to the island (leading) and one **detached**, a circle or an oval depending on content.
  - It should show *live data*, not a static logo. The HIG's example is the Timer showing remaining time.
- **Expanded**
  - Shown on touch-and-hold, and briefly for an update that carries an alert.
  - Regions: `.leading`, `.trailing`, `.center`, `.bottom`.
  - Content taller than 160 pt may be truncated.
- **Lock Screen**
  - A card 84–160 pt tall.
  - On devices without an island, an alert appears as a banner.
- **StandBy**
  - The minimal view shows at the top. Tapping it shows the Lock Screen view scaled up **2×**.
- **Transient style (iOS 18)**
  - A temporary extended presentation.
  - It ends when the device locks, the user collapses it, or the user taps outside.

**Gestures:**

| Gesture | Effect | Tag |
|---|---|---|
| Tap compact or minimal | Opens the app (via `widgetURL` or a deep link) | [V MacRumors, DocC] |
| Touch and hold | Expanded view (e.g., playback controls for music) | [V MacRumors] |
| Swipe toward the center | Minimizes or hides the activity; it keeps running | [V Six Colors; MacRumors] |
| Swipe outward from the center | Restores it | [V Six Colors] |
| Two activities: swipe over the secondary | Hides it | [V Six Colors] |
| Two activities: swipe in from the far edge | Brings the smaller item forward, replacing the main one | [V Six Colors] |
| Swipe beyond the limit | The island rubber-bands | [V Six Colors] |
| iPhone 18 Pro | Users can "toggle between three live tasks". Arrangement undocumented. | [V MacRumors] |
| iOS 27: swipe down from top center | **Search or Ask** (Spotlight with Siri), from inside any app. Apple Intelligence iPhones with an island only. | [V Beebom, MacRumors] |
| iOS 18 flashlight: tap the torch in the island | Opens a panel (see below) | [S AppleInsider, 9to5Mac] |
| iOS 27 landscape | Compact and minimal cannot grow wider. Apps switch to an icon or abbreviated UI. | [V WWDC26-223] |

The iOS 18 flashlight panel:
- drag **horizontally** to change beam width;
- drag **vertically** to change intensity;
- both at once is possible;
- tap outside and the panel is pulled back into the island;
- tap the island again to return, with the settings kept.

**Ordering between activities** [V DocC]:
- `relevanceScore` only orders activities *from the same app*. With equal scores, the first-started activity wins.
- How the system chooses *across apps* is undocumented.
- The HIG prefers **one rotating activity** over several separate ones.

**Geometry** [V HIG]:

| Item | Size (pt) |
|---|---|
| Corner radius | **44** |
| Compact leading/trailing views | 52.33–62.33 × **36.67** each |
| Minimal | 36.67–45 × 36.67 |
| Expanded | 371–408 wide × 84–160 tall |
| Island width, compact or minimal: standard and Pro models | 230 |
| Island width, compact or minimal: Plus, Pro Max and Air | 250 |
| Lock Screen margin | 14 |

- The **iPhone 18 Pro island** is reportedly "below 100 layout points" [S, GadgetReview/Yahoo snippet], possibly thanks to Face ID parts moving under the display [S]. Treat both as unconfirmed.
- For comparison, report 03 measured a MacBook Pro 14" (M3 Pro) notch at **185 × 32 pt** with a 33 pt menu bar. A Mac "compact" is therefore about 13% shorter than an iPhone compact.

### 1.3 Animation language and haptics

**Apple's own framing** (WWDC23 "Design dynamic Live Activities") [V]:
- The island is a blend of hardware and software that "organically shape shifts".
- It is designed "to feel like a living organism", with deliberate elasticity.
- Layout is concentric: rounded shapes nest with even margins, and content hugs the sensor.
- Use "rounded, thicker shapes and liberal use of color", so each activity feels like a tiny version of the app.
- **When possible, expand the island to present an alert instead of sending a push notification.**

**Content-animation rules** [V DocC and HIG]:
- The system ignores `withAnimation` and `.animation`.
- Text gets a **blurred content transition**. Images and SF Symbols animate.
- Supported transitions: `.opacity`, `.move(edge:)`, `.slide`, `.push(from:)`.
- Use `numericText(countsDown:)` for numbers and timers.
- **Animations last 2 seconds at most.** Nothing animates on the reduced-luminance Always-On display.

**Motion vocabulary as commonly observed** [U]:

| Pattern | Description |
|---|---|
| Spring expand | Slight overshoot (a "bounce"). |
| Collapse | Quicker, no overshoot. |
| "Metaball" / gooey split | A second activity stretches off the edge of the island, necks, and pinches off into the detached circle. It merges back when it ends. |
| Alert pop | Expand, hold for about 1.5–3 s, collapse back to compact. |
| Shape | Continuous-curvature capsule (squircle). |
| Rubber-banding on over-swipe | [V Six Colors] |
| Symbol effects | Bounce and pulse on state changes, such as the bell for silent mode. |

**Haptics:**
- A Live Activity cannot trigger haptics. `AlertConfiguration` carries only title, body and sound [V].
- On iPhone, haptics accompany **direct manipulation** (touch-and-hold to expand) and **physical hardware actions** the island reflects (the ring/silent switch, the Action button) [U].
- Lesson for Islet: **haptics belong to user-initiated physical interactions, never to passive events.**

### 1.4 First-party system activities and alerts

**Where the lists come from.** The event lists are from the MacRumors guide [V]. The visual descriptions are [U] unless tagged otherwise.

**Persistent activities** (they stay in the island while the activity is ongoing)

| Activity | Typical compact / expanded content | Since | Tag |
|---|---|---|---|
| Phone / FaceTime call | Green phone or video glyph plus elapsed time and a waveform. An incoming call expands to a banner with Decline and Accept. | iOS 16 | list [V]; look [U] |
| Call recording indicator | — | iOS 18.1 | [U] |
| Hold Assist and Call Screening states | — | iOS 26 | [U] |
| Now Playing (Music, Podcasts, any audio app) | Artwork on the leading side; animated waveform tinted from the artwork on the trailing side. Long-press shows controls (art, title, scrubber, play, AirPlay). | iOS 16 | list and long-press [V]; look [U] |
| Timers (Clock) | Timer glyph plus countdown (orange). Minimal shows time remaining. Multiple timers since iOS 17 [U]. AlarmKit (iOS 26) gives third-party alarms and timers countdown Live Activities [U]. | iOS 16 | HIG minimal example [V] |
| Stopwatch | — | ? | [U] |
| Maps turn-by-turn | Next-turn arrow plus distance; expanded shows the instruction and ETA | iOS 16 | list [V]; look [U] |
| Screen recording | Red indicator plus elapsed time | iOS 16 | list [V] |
| Voice Memos recording | Red waveform plus elapsed time | iOS 16 | list [V] |
| Personal Hotspot | Link glyph (plus number of connected devices) | iOS 16 | list [V]; count [U] |
| SharePlay | SharePlay glyph | iOS 16 | list [V] |
| Sports scores (Apple Sports, TV app) | Both scores; minimal shows the score | iOS 16.x | list [V] |
| **Workout (Fitness app)** | Elapsed time plus a **pause** control | iOS 26 | [V 9to5Mac] |
| **Wallet boarding pass** | Flight info; shareable | iOS 26 | [V 9to5Mac] |
| **Flashlight** | Torch glyph; tap opens a two-axis beam and intensity panel | iOS 18 | [S] |
| **Siri** | Orb animates *inside* the island. Compact answers appear around it; swipe down for more or to follow up. | iOS 27 | [V MacRumors] |
| Privacy indicators | Green (camera) or orange (mic) dot | iOS 16 | list [V] |
| Background Tasks (iPad; Lock Screen only, no island) | Export or processing progress | iPadOS 26 | [V 9to5Mac] |

**Transient alerts** (the island pops open for a few seconds, then collapses)

| Alert | Content | Tag |
|---|---|---|
| Silent mode on/off (switch or Action button) | Bell glyph; red with a strike-through when silent | list [V]; look [U] |
| Action button | Shows the assigned action's icon; press-and-hold feedback | [U] |
| Charging started | Charge glyph plus battery % | list [V] |
| Low battery (20%) | **iOS 26:** an island alert; tap it to turn on **Low Power Mode**. Redesigned in beta 5. | [S MacRumors, xarkas] |
| Face ID | Animated face glyph, then a checkmark (unlock, app sign-in, Apple Pay) | list [V]; look [U] |
| Lock / unlock | Padlock animation | [S] |
| Apple Pay / Wallet | Face ID plus a "done" confirmation | list [V] |
| AirDrop | Transfer progress | list [V]; progress [S] |
| AirPods / Beats connected | Device glyph plus battery | list [V]; look [U] |
| AirPods noise-control mode change | — | [U] |
| Focus changed | Focus glyph plus name | list [V] |
| Apple Watch unlock · Car Key lock/unlock · NFC tag · accessory connected (e.g., MagSafe) | — | list [V] |
| AirPlay connection · Music's AirPlay-to-HomePod prompt (`.transient`) | — | list [V]; transient [V DocC] |
| Shortcut actions running or completing | — | list [V] |
| Airplane mode · no data · SIM alerts | — | list [V] |
| Find My alerts | — | list [V] |

**Asked about but not confirmed as island surfaces** [U]:
- Shazam / Music Recognition
- Live Listen and hearing features
- Live Translation (calls, AirPods)
- Visual Intelligence
- CarPlay connection
- NameDrop
- Emergency SOS via satellite

### 1.5 Third-party Live Activity categories

**Caveat:** app-by-app confirmation was blocked by the tool outage. The only confirmed facts in this section are:
- Apple highlighted **Flighty** at the iPhone 18 Pro event [V AppleInsider];
- **Uber** and **Zomato** use Android's equivalent [V];
- the category patterns themselves are well established.

| Category | Example apps | Compact pattern | Expanded pattern | Mac-native analogue for Islet |
|---|---|---|---|---|
| Food delivery | Uber Eats, DoorDash, Instacart, Swiggy, Zomato [U] | Brand mark + ETA in minutes | Stage stepper (ordered → preparing → on the way → arriving), courier | Webhook/plugin only (no Mac API) |
| Rideshare | Uber, Lyft [U] | Car glyph + ETA / plate | Driver, car, progress to pickup | Same |
| Flights / travel | **Flighty [V]**, airlines [U], Wallet boarding passes [V] | Gate / time to departure | Flight progress bar, delays | Calendar-detected flight + flight-data plugin |
| Transit | Transit app [U] | Line + minutes | Stops remaining | Plugin |
| Sports | Apple Sports, TV app [V list]; ESPN, theScore, FotMob [U] | Score – score | Clock, period, last play | Score plugin (feed or "broadcast channel") |
| Parcels | Parcel, Deliveries [U] | Carrier + status | Stepper | Plugin (tracking APIs) |
| Workouts | Apple Fitness [V]; Strava, NRC [U] | Elapsed time | Metrics | n/a |
| Stocks / crypto | Robinhood, Coinbase [U] | Ticker + % change | Sparkline | Market plugin (compare TickerNotch, report 01) |
| Focus / Pomodoro | Structured, Focus Flow, Forest [U] | Countdown ring | Task + controls | **Native** |
| Meetings / calls | Zoom, Teams [U] | Elapsed + mute state | Mute / leave | **Native** (mic-in-use detection, grade A) |
| Fasting, habits, baby tracking | Zero, Huckleberry [U] | Elapsed / remaining | — | Plugin |
| Parking / EV | ParkMobile, Tesla [U] | Time left / charge % | — | Plugin |
| Navigation | Google Maps [U] | Arrow + distance | Instruction | n/a on Mac |
| **AI assistants / agents** | ChatGPT, Perplexity, Claude, Gemini: **none confirmed** [U]. Apple put **Siri in the island** in iOS 27 [V]. | Status glyph + phase | Transcript / approvals | **Native** (agent hooks, see reports 01–03) |
| Uploads / backups | Google Photos, Dropbox [U] | % ring | File, speed | `Progress` subscriber (grade B) |
| Novelty | Pixel Pals (a pet), "Hit the Island" (game) [U] | — | — | Plugin |

**Policy** [V]:
- The HIG forbids ads and promotions in Live Activities.
- App Review Guideline 4.5.3 names Live Activities in its anti-spam rule.
- Live Activities are for tasks with a defined start and end, capped at 8 hours.

**Mac-native "live" sources.** These have no iPhone equivalent but map naturally onto the island:
- CI / builds / tests (GitHub Actions via `gh`)
- AI coding agents (hooks)
- Downloads and file copies (`Progress` subscriber)
- Exports and renders
- `brew` installs
- Time Machine (`tmutil status`) [U]
- Calls and meetings (mic in use)
- Timers
- Next-meeting countdown (EventKit)
- AirDrop received
- Battery and charging
- Media

### 1.6 ActivityKit concepts, and what they mean for Islet

**Apple's behaviour** [V: DocC, HIG, WWDC26-223]; **Islet today** is read from `Sources/IsletCore/Activity.swift`, `ActivityCenter.swift` and `Presenter.swift`.

| Concept | Apple behaviour | Islet today | Recommendation |
|---|---|---|---|
| Static attributes vs dynamic `ContentState` | Two parts; **combined ≤ 4 KB** including push payloads | Flat `ActivitySpec` upsert | Keep the flat JSON. Enforce a payload cap (4–8 KB) so the island stays cheap. |
| Lifecycle limits | Active **≤ 8 h**; may linger **≤ 4 h** more on the Lock Screen, Mac menu bar and Watch (12 h total). Leaves the island **immediately** when ended. | `ttl`; `finishedTTL` = 10 s | Add optional `maxDuration`. Ended activities leave the compact island at once and move to a "Recent" list in the expanded view. |
| Dismissal policy | `.default` (≤ 4 h), `.immediate`, `.after(date)`. HIG suggests **15–30 min** in most cases. | — | Add `dismissal: {policy: default\|immediate\|after, at}`. |
| `staleDate` / `isStale` | Show an "outdated" UI once stale; keep pushing the stale date forward | — | Add `staleAt`: dim the view, add a clock badge and "Updated 5 min ago", auto-remove after a grace period. |
| `relevanceScore` | Orders activities **within one app**; ties go to the first started | 4-level `priority` | Add `relevance` (0–100) for ordering within a source. Keep `priority` as the cross-source interruption level. |
| `AlertConfiguration(title, body, sound)` | No separate banner: **expands the island** and lights the screen. Use sparingly. | `sneak: Bool` | Add `alert {title, body, sound}` with a per-source rate limit. |
| `.transient` style (iOS 18) | Temporary extended view that ends on outside tap | `sneak` | Same concept; document it as such. |
| Push tokens, push-to-start (17.2), broadcast channels (18), APNs budget (priority 5 vs 10), `NSSupportsLiveActivitiesFrequentUpdates` | Remote updates without the app running; low-priority pushes don't count against the budget | Local HTTP API, LAN bridge | Webhook relay and ntfy subscription. Per-source update budget with coalescing (≤ 1 visual update/s). A "quiet update" flag that doesn't animate. |
| Scheduled start (iOS 26) | `start:` date; an alert is required | — | Add `startAt` (e.g., meeting starts, game begins, flight boards). |
| Interactivity (iOS 17) | `Button` / `Toggle` via `LiveActivityIntent`. HIG prefers **one** control. Works on the Mac menu bar; disabled in CarPlay. | `actions` (URL buttons) | Add a toggle action type with a callback (HTTP, URL scheme or shell) and optimistic UI. |
| Deep links | `widgetURL` for compact/minimal/Lock Screen; `Link` in expanded | Action URLs | Add `url` for a tap on the compact view. |
| Styling | Island background always black; `keylineTint` colours the thin edge; Lock Screen card background customizable | `tint` | Tint drives the keyline, glow and waveform only; the island stays `#000` (see report 03 on Liquid Glass). |
| Content transitions | Blur-replace, `numericText`, ≤ 2 s | — | Adopt as-is. |
| `isDynamicIslandLimitedInWidth` (iOS 27) | Compact/minimal can't widen; show an icon or abbreviation | — | Add `compactShort` (≤ 4 chars or icon-only) for crowded menu bars, narrow external displays and the bubble view. |
| `.supplementalActivityFamilies([.small])` | Watch and CarPlay layout | — | Reuse `.small` for the non-notch "pill" and for bubbles. |
| Authorization per app | User toggles Live Activities per app | `mutedSources` | Surface this in Settings as "Allow live activities from…" with per-source switches. |

### 1.7 Beyond the phone

- **Apple Watch** (iOS 18 / watchOS 11) [V]:
  - Activities appear at the top of the Smart Stack automatically. The default view merges compact leading and trailing.
  - Alert updates auto-open the Smart Stack.
  - `.small` custom layouts are available.
  - `isActivityUpdateReduced` is true when the Watch only syncs alert updates.
- **CarPlay** (iOS 26) [V]:
  - Activities appear on the Dashboard as merged compact views or `.small`.
  - Controls are disabled.
  - Sizes: 240×78, 240×100 or 170×78 pt.
  - iOS 27 adds a persistent CarPlay mini-player [V MacRumors].
- **iPad** [V]: no island. Live Activities show on the Lock Screen only (425–500 pt wide). iPadOS 26 uses them for Background Tasks.
- **StandBy** [V]: minimal view at the top; tap shows the Lock Screen view at 2×; Night Mode adds a red tint.

---

## 2. Live Activities on the Mac (macOS 26 Tahoe → macOS 27 Golden Gate)

### 2.1 How it works in macOS 26 Tahoe [V unless marked]

- **Requirements:**
  - macOS 26 or later.
  - iPhone on **iOS 18 or later**. iOS 26 is *not* required (WWDC25 session 278; 9to5Mac).
  - The same Apple Account on both, with two-factor authentication.
  - Devices near each other with Bluetooth and Wi-Fi on (about 10 m per iDownloadBlog).
  - The Mac must not be using AirPlay or Sidecar.
  - Intel support is not documented [U]. It is likely tied to iPhone Mirroring, which needs Apple silicon or a T2 Mac.
- **Where it appears and what it looks like:**
  - A **menu-bar item** that shows the iPhone's **compact leading and trailing views side by side**, "just like in the Dynamic Island" (WWDC25-278).
  - If the menu bar is crowded, it shows **a small Live Activity icon** instead (Apple Support 120684).
  - HIG: the Mac uses the **compact, minimal and expanded** presentations at **iOS dimensions**.
  - Reviewers describe it as a **pill**.
  - Exact placement relative to the notch and status items is **not documented** [U: in the status-item area].
- **Clicking:**
  - Click → **expands** to the Lock Screen / expanded presentation.
  - Click that view, or **double-click** the menu-bar item → opens the app in **iPhone Mirroring** (if the iPhone is nearby).
  - Buttons and deep links work.
- **Developer work:** none. WWDC25: "There are no code changes required." WWDC26-223 repeats this.
- **After it ends:** it may stay in the menu bar for up to 4 hours (HIG).
- **Settings:**
  - System Settings → Notifications → *Allow notifications from iPhone* → **Allow Live Activities from iPhone**. On by default.
  - Each activity has a close button in the menu bar.
  - Per-app control is on the iPhone: Settings → Apps → [app] → Live Activities.
  - Apple's page now shows separate steps for **macOS 26.4+**, so the settings UI changed.
  - Dismissing on one device also clears it on the other (iDownloadBlog).
- **Not documented:** how many activities show at once, behaviour in full screen, and external displays [U: probably follows normal menu-bar behaviour].
- **Reported issues:**
  - Timers and stopwatches did not appear on the Mac (iDownloadBlog, mid-2025).
  - An Apple Community thread reports activities not appearing at all.

### 2.2 What macOS 27 Golden Gate changed

macOS 27 was announced 2026-06-08, released **2026-09-14**, and runs on Apple silicon only [V].

- **Live Activities:** no Apple-announced change.
  - No Mac-native ActivityKit.
  - No news on multiple activities or interactivity.
  - WWDC26-223 describes the Mac only as *receiving* iPhone activities [V].
  - A beta-1 user note says Live Activities are "now visible in the menu bar". That is ambiguous and probably a rediscovery of the Tahoe feature [U].
- **Menu bar** (highest impact for notch apps):
  - A native **overflow chevron** reveals items hidden by the notch [V, several third-party sources].
  - Third parties report the whole menu bar is now **one window**, which broke Bartender, Ice, Thaw and Barbee [V third-party; not stated by Apple].
  - Menus dropped Tahoe's per-item icons [V AppleInsider].
  - Liquid Glass has an opacity slider [V].
- **Intelligence:**
  - **Siri AI** with onscreen awareness.
  - **"Search or Ask"** in Spotlight (⌘-Space).
  - **Visual Intelligence** on Mac (⇧⌘-Space) [V].
  - No island-style Siri UI on the Mac was found [V absence].

### 2.3 What this means for Islet

1. **Coexist; don't duplicate.**
   - No public API exposes other apps' iPhone Live Activities.
   - An iPhone companion app could only forward *its own* activities.
   - Apple already puts iPhone activities in the menu bar.
   - Islet's lane is **Mac-native activities** (agents, builds, calls, timers, media, downloads, devices).
2. **Avoid the right side of the menu bar.** Apple's Live Activity pill and the macOS 27 overflow chevron sit in the status-item band.
   - Islet's detached bubbles should detect collisions or offer a "hang below the notch" placement.
   - Islet should never cover Apple's pill.
3. **Copy the contract.** Apple ported the four presentations unchanged, so an Islet API built on compact, minimal, expanded and card matches Apple's mental model.
   - Bloomberg and MacRumors (Feb 2026) and AppleInsider (Jun 2026) report an OLED touchscreen MacBook Pro with a real Dynamic Island in late 2026–2027 [U, from report 01].
   - If that ships with a Mac ActivityKit, Islet should be a superset that can bridge to it.

---

## 3. Android equivalents

### 3.1 Platform summary

| Platform (since) | What shows | Interaction | Developer API | Tag |
|---|---|---|---|---|
| **Samsung Now Bar + Live Notifications** (One UI 7, Jan 2025 → One UI 9, Jul 2026) | See below | Tap to expand; **swipe up to cycle** activities; **long-press → options / remove / Now Bar settings**; per-app toggles | Android 16 Live Updates from One UI 8 (before that, mostly Samsung apps) | [V Samsung, SamMobile, Android Authority] |
| **Samsung Now Brief** | AI brief labelled by time of day ("Good morning", "Tonight's brief") covering health, travel, events, settings, news and smart home | **Audio playback**; One UI 9 adds **action buttons**. "Now Nudge" (One UI 9) offers screen-aware suggestions inside apps. | Partner integrations | [V] |
| **Xiaomi HyperOS 3 "Super Island" / HyperIsland** (Aug 2025) | Up to **three coexisting islands** (e.g., charging, navigation and delivery at once); 70+ apps [S] | **Pull down → floating mini-window of the app** [V TechNode]; **long-press and drag the island into a chat to send the ride or trip details** [S 36kr]; drag music out to share [S] | Focus Notifications templates [U] | [V/S] |
| **Oppo Fluid Cloud / OnePlus Live Alerts** (ColorOS 14 → OxygenOS/ColorOS 16) | Timers, recordings, calls, charging, rides, delivery, music waveform | Top-left capsule with a **progress ring**; tap → drop-down card | Android 16 Live Updates from 16 [U] | [U] |
| **Vivo Origin Island** ("原子岛", OriginOS 4–6) | Timers, recording, calls, charging, navigation | **Clipboard-aware one-tap suggestions** (tracking number → courier, address → maps, phone number → call); **drag items in to hold them, then drop into another app** | — | [U] |
| **Honor Magic Capsule** (MagicOS 7–10) | Calls, timers, recording, charging, navigation, delivery, face-unlock feedback; several capsules at once | "Magic Portal" drag-to-act; the YOYO agent's multi-step task progress | — | [U] |
| Huawei Live Window (HarmonyOS 4) · Nothing Glyph Progress · Realme Mini Capsule | Capsule + lock-screen card (Live View Kit) · progress on the rear LEDs · charging and steps chips | — | Huawei: Live View Kit | [U] |
| **Google Android 16 Live Updates** | Nav, calls, rideshare, delivery, any continuous user-started task | Promoted notification: **expanded by default** at the top of the shade, on the lock screen and AOD, plus a **status-bar chip**; tap the chip for the full notification | `POST_PROMOTED_NOTIFICATIONS` + `setRequestPromotedOngoing(true)` | [V developer.android.com] |
| **Android 17 MetricStyle** (Jun 2026) | Up to **3 metrics** (label, value, unit) + 3 actions | Layout adapts: glanceable on AOD and lock screen, side by side when expanded, one line when collapsed | MetricStyle | [V] |
| Pixel At a Glance · Pixel Now Playing | Boarding passes, commute, location-triggered passes · **on-device ambient song ID** (standalone app since Mar 2026) with searchable history | — | — | [V] |
| **dynamicSpot** (Jawomo) and similar clones | Pill over the punch-hole | See below | Uses accessibility and notification-listener permissions | [U] |

More detail on the rows above:

- **Samsung Now Bar content:**
  - Where: a pill at the bottom of the lock screen and AOD, status-bar chips, and the top of the notification shade.
  - Base set: media, timers, stopwatch, recording, Interpreter, Maps, sports, Samsung Health, current mode, DND and torch.
  - One UI 8.5 adds Auracast broadcast and "Commute" by time of day.
  - Missed calls [S].
- **Google Live Updates rules:**
  - **Banned uses:** ads, chat, alerts, calendar events, ambient info and package tracking.
  - **ProgressStyle:** coloured **segments**, milestone **points**, a moving **tracker icon**, start and end icons, and an indeterminate state.
  - **Chip:** at most 96 dp; an icon plus ≤ 7 characters, or a time. It shows an **automatic countdown** when `setWhen` is ≥ 2 min away, and uses `setShortCriticalText`.
  - Custom RemoteViews and colourised notifications are not allowed.
  - Design rule: **never show an empty state**; use placeholders such as "Thinking…".
- **dynamicSpot settings:** size and position offsets, per-app allow/deny lists, hide in fullscreen or landscape, show on lock screen, and gesture remapping. The Pro tier shows two items at once.

### 3.2 Standout features neither the iPhone island nor Mac notch apps offer

| # | Feature | Origin | Tag |
|---|---|---|---|
| 1 | Drag a *live activity* out of the island into another app to share its content (ETA, trip, track) | Xiaomi | [S] |
| 2 | Pull down on the island to spawn a floating mini-window of the source app | Xiaomi | [V] |
| 3 | Segmented progress with milestone points and a moving tracker icon | Android 16 | [V] |
| 4 | A live dashboard of up to 3 metrics that adapts its layout to context | Android 17 | [V] |
| 5 | Chip countdown derived automatically from a timestamp; icon-only fallback when less than half the text fits | Android 16 | [V] |
| 6 | A time-of-day AI brief with audio and action buttons, in the same surface as live activities | Samsung | [V] |
| 7 | Vertical swipe through a stack of activities; long-press jumps to *that item's* settings or removal | Samsung | [V] |
| 8 | Ambient state items (current mode, DND, torch) living alongside activities | Samsung | [V] |
| 9 | Hard eligibility rules (ongoing and user-started only; no ads or chat) as a public contract | Android | [V] |
| 10 | Clipboard-aware one-tap suggestions | Vivo | [U] |
| 11 | The island as a drag-and-drop holding area | Vivo | [U] (Mac shelves partly do this already) |
| 12 | A progress ring on the collapsed pill | Oppo / OnePlus | [U] |
| 13 | Agent multi-step task progress in the capsule | Honor YOYO | [U] |
| 14 | Passive on-device song recognition with history | Pixel | [V] |

---

## 4. Synthesis: what Islet should build

### 4.0 Design principles

1. **One contract.**
   - Compact (leading + trailing), minimal, expanded, and card (the full stack in the expanded panel).
   - The island is pure black; tint is only an accent (keyline, glow, waveform).
   - Content animations last ≤ 2 s, using blur-crossfade and `numericText`.
2. **Ambient, not noisy.**
   - Adopt Android's eligibility rule (ongoing and user-started) and the HIG ban on ads.
   - Alerts are rate-limited per source.
   - Passive updates never animate the shape; only alerts do.
3. **Zero idle cost** (report 02 §4B): no timers or animation while collapsed and idle.
4. **Haptics only for direct manipulation.**
5. **Every "wow" has an off switch.** "Wobbly" animations are the most-voted complaint in report 02.

### 4.1 P0: build next

Each item lists: what, why, feasibility, the ideal interaction and animation, and Islet's current state.

**P0-1. Split island: up to three concurrent activities**
- **What:**
  - 1 activity → compact wings.
  - 2 → the primary shows *minimal-attached* (or compact if space allows) plus a **detached circular bubble**.
  - 3 → two bubbles, matching iPhone 18 Pro.
  - More → the last bubble shows "+N".
- **Why:** the island's signature behaviour. Mac users routinely run music, a timer and an agent together, and today Islet shows one item plus a counter.
- **Feasibility:** public SwiftUI/AppKit, grade A.
  - Risk: the right-of-notch band is shared with status items, Apple's iPhone Live Activity pill and the macOS 27 overflow chevron.
  - Offer placement options: **right of the notch** (default), **left**, or **hang below the notch**. Use icon-only `compactShort` when space is tight.
- **Interaction:**
  - Click a bubble → it swaps into the primary slot with a cross-morph.
  - Two-finger horizontal swipe on the island → cycles the primary.
  - Hover a bubble → a mini tooltip card.
- **Animation (metaball split):**
  - The trailing wing stretches about 20–30 pt, necks, and pinches into the bubble, which springs to rest with one small overshoot, over about 350–450 ms. When the activity ends, the bubble merges back.
  - Implement it with a SwiftUI `Canvas` using `.alphaThreshold` plus blur (classic metaball), or a Metal SDF `layerEffect` (macOS 14+) [U: API names from prior knowledge, standard].
  - Reduce Motion → cross-fade.
- **Islet today:** `Presenter.present` returns a single `.compact(.activity(top, others:))`. Replace it with ordered **slots**.

**P0-2. ActivityKit-parity semantics in the API**

Add to `ActivitySpec`:

| Field | Purpose |
|---|---|
| `staleAt` | Dimmed "stale" UI |
| `relevance` 0–100 | Ordering within a source |
| `alert {title, body, sound}` | Replaces the bare `sneak` |
| `dismissal {policy, at}` | End behaviour |
| `startAt` | Scheduled start |
| `url` | Tap deep link |
| `compactShort` | Limited-width fallback |
| Toggle action | Single interactive control |

- **Why:** developers already know the model, and it makes Islet predictable. Section 1.6 has the details.
- **Feasibility:** own code, grade A.
- **Interaction:** an alert expands the island for about 2.5 s (Islet's `sneakDuration`), then collapses; stale activities dim with a small clock badge.

**P0-3. iPhone-style system event "splashes"**

Transient alerts, sized like a short expanded view, held 1.5–2.5 s. Section 4.2 has the full spec. The set, with feasibility grades from report 03:
- charging on/off, time-to-full and wattage (A);
- low battery at 20% and 10% with an "Open Battery Settings / Low Power Mode" button (A; toggling it directly needs admin rights, so link to Settings);
- Low Power Mode on/off (A);
- **AirPods / Beats / Bluetooth headphones connected**, with L/R/case battery rings (C: public connect events, private battery keys, Bluetooth permission);
- **output device switched**, e.g. "Playing on AirPods Pro" (A);
- **output mute and mic mute**, the Mac's "silent switch" (A);
- **Focus changed** (B via a Shortcuts automation, C via Full Disk Access);
- Caps Lock (B);
- **screen unlocked**: a padlock "welcome back" that can carry a digest of what happened while away (B/C: the long-stable but undocumented `com.apple.screenIsUnlocked` distributed notification);
- Wi-Fi, VPN or iPhone hotspot joined (B; the Wi-Fi network name needs Location permission [U]);
- AirDrop received (B);
- timer finished (A).

Why: these tiny moments are what make the iPhone island feel "alive". Every top paid Mac app sells them (report 01), and AirPods battery is among the most-requested features (report 02 #7).

**P0-4. Gesture grammar and expanded views**

| Input | Action |
|---|---|
| Hover | Peek (exists) |
| Click | Open the source (`url`) |
| **Press and hold ≥ 0.5 s, or Force Click** | Full expanded view; haptic `.levelChange` on Force Touch trackpads |
| **Two-finger horizontal swipe** | Cycle activities |
| **Swipe or scroll up / drag inward** | Hide an activity (it keeps running) |
| Swipe outward / hover | Restore |
| **Right-click** | Per-activity menu: mute source, "don't show from this app", settings. This is Samsung's long-press-to-settings. |
| Global hotkey | Expand, then ←/→ to cycle, Return to open, Esc to close |

- **Expanded view** = the activity's regions (leading, trailing, center, bottom, as on iPhone), plus below it a **stack of all activities as cards** (the Lock Screen equivalent) and a "Recent" section for ended ones.
- **Feasibility:** public `NSEvent` (pressure and stage for Force Click, scroll phases), grade A.

**P0-5. Progress visuals**
- **Compact:** a trailing **progress ring** (Oppo, Apple timers).
- **Expanded:**
  - **Segmented progress with milestone points and a tracker icon**, from Android ProgressStyle. Examples: an agent's plan steps, build stages, a delivery stepper.
  - Indeterminate shimmer with "Thinking…" placeholders, never empty.
- **Countdowns and count-ups** use `numericText`. Islet already has `endsAt` and `startedAt`.
- **Feasibility:** own code, grade A.

**P0-6. First-class calls, timers and media**
- **Call pill:**
  - Shown when a call app has the mic (FaceTime, Zoom, Teams, Meet in a browser; grade A via CoreAudio process objects).
  - Green glyph, elapsed time, and a red mic-slash when muted.
  - Expanded: mute toggle and "go to call".
  - Leaving the call needs AX / AppleScript per app (grade C).
- **Timers, stopwatch, Pomodoro:**
  - Orange ring countdown; minimal view shows time left.
  - When done, the island alert-expands with Stop and Snooze and plays a sound.
- **Media** (exists): tint the waveform from the artwork, and add a scrubber and output picker to the expanded view.

**P0-7. Motion and haptics contract**

Apple publishes no spring constants. These are Islet recommendations, to be tuned by eye:

| Motion | Spring |
|---|---|
| Expand | response ≈ 0.42 s, damping ≈ 0.78 (one small overshoot) |
| Collapse | response ≈ 0.34 s, damping ≈ 0.92 |
| Alert pop | response ≈ 0.38 s, damping ≈ 0.70 |
| Content | blur-crossfade ≈ 0.25 s |

- Cap overshoot at about 3–5% of size.
- Styles: "fluid", "snappy", "smooth", "minimal" and "off", plus the system Reduce Motion setting.
- No idle animation.
- Haptics as in §4.5.

**P0-8. Customization essentials** (§4.4)
- Add: per-activity-type toggles, bubble placement, maximum concurrent (1, 2 or 3), alert duration, haptics mode, quiet hours, and a live preview.
- Many of these already exist in `IsletSettings`.

### 4.2 Event animation spec (P0-3)

| Event | Trigger / API | Content | Motion | Hold | Haptic | Grade |
|---|---|---|---|---|---|---|
| Charger connected | IOKit `IOPSNotificationCreateRunLoopSource`; adapter watts and time-to-full from IOPS [U: key names] | Left: green bolt glyph filling. Right: `87%` + "1 h 10 m to full". MagSafe: "MagSafe · 96 W". | Pop + bolt "fill" symbol effect | 2 s | none | A |
| Unplugged | Same | White/grey battery + % | Short pop | 1.2 s | none | A |
| Low battery 20% / 10% | IOPS | Red battery + % + **[Battery Settings]** button (iOS 26 analogue) | Pop, then stays compact red until charging | 4 s (10%: sticky) | none | A |
| Low Power Mode on/off | `ProcessInfo.isLowPowerModeEnabled` + power-state notification | Yellow battery + "Low Power Mode On/Off" | Pop | 1.5 s | none | A |
| AirPods / Beats connected | IOBluetooth connect notification; battery via guarded private KVC | Left: model glyph (`airpodspro`, `beats.headphones`…) + name + "Connected". Right: **rings for L, R and case** (green > 20%, red ≤ 20%) that fill from 0 to value. | Expanded-lite pop; rings animate 0.6 s | 2.5 s, then compact glyph + lowest % for 3 s | none | C |
| Output switched | CoreAudio default-output listener | Device glyph + "Playing on …" | Pop | 1.5 s | none | A |
| Output muted / mic muted | CoreAudio mute property on the output or input device [U: exact property] | `speaker.slash` / `mic.slash` in **red**, with a strike-through drawn left to right (the iPhone silent-switch analogue) | Pop + draw-on | 1.2 s (mic muted during a call: persistent red dot) | none | A |
| Focus on/off | Shortcuts "When Focus turns on" automation → `islet://focus?...`, or the FDA reader | Focus glyph (moon, bed, briefcase…) in the Focus colour + name + On/Off | Pill widens; glyph bounces | 1.5 s | none | B/C |
| Caps Lock | Modifier-flags monitor or IOHID [U: permission] | `capslock.fill` + "Caps Lock On" | Pop | 1 s | none | B |
| Unlocked / woke | `com.apple.screenIsUnlocked` | Padlock opens → "Welcome back" + optional one-line digest (see AI, §4.6) | Padlock symbol effect, then content push | 2 s | none | B/C |
| Wi-Fi / VPN / hotspot | CoreWLAN; VPN via SystemConfiguration [U] | Glyph + network name | Pop | 1.5 s | none | B |
| AirDrop received | `~/Downloads` `Progress` subscriber / watcher | Thumbnail + file name; **drag it out** (shelf) | Pop | 3 s | none | B |
| Timer finished | Own | Orange ring full → "Timer" + Stop / Snooze | Alert expand with a gentle repeated pulse until acknowledged | Sticky | none (sound) | A |

**Rules for these events:**
- Coalesce bursts: e.g., when AirPods connect *and* output switches, show one combined card.
- Never interrupt an expanded view the user is interacting with; queue behind it.
- In fullscreen, show only the HUD and critical events (Islet's `isSuppressed` logic already does this).

### 4.3 Concurrency model (P0-1)

**Ordering score**, recomputed on change rather than per frame:

```
score = priorityWeight(priority)            // critical ≫ high > normal > low
      + relevance(0…100) within its source   // ActivityKit parity
      + recencyBoost(updatedAt)              // decays over minutes
      + engagementBoost(source)              // learned: expanded/opened vs dismissed (P1, §4.6)
ties → earliest startedAt (iOS rule)
```

**Slots:**
- `primary`: compact wings, or minimal-attached when bubbles are present.
- `bubble1`, `bubble2`: minimal content — a ring, ≤ 4 characters, or a glyph.
- **HUDs and alerts temporarily take the whole island**, then give it back with the reverse morph.
- Media yields to high-priority items; Islet already does this.

**Overflow:** anything beyond three goes into the expanded stack. The last bubble shows "+N".

**User hide** (swipe inward): the activity moves to the stack and does not return to a slot until it updates with an alert.

**Collision handling:** if the bubbles' region intersects the menu-bar item area, fall back to "hang below", or to the primary alone plus "+N".

### 4.4 Customization users ask for

| Option | Evidence of demand | Islet status |
|---|---|---|
| Island size: custom width and height; compact never wider than the notch | report 02 #5 (#300, #1037, #1353, #1513) | ✅ presets + custom; add a "never wider than notch" compact |
| Animation style, including **off** | report 02 #4 (≈ 83 👍 combined, the most-voted theme) | ◐ has fluid, snappy, smooth, minimal + reduceMotion; **add "off"** |
| Theme: black, graphite, glass; album-art tint | report 02 #12 (Liquid Glass #922) | ✅ |
| Per-app appearance and behaviour: tint, icon, mute, priority, hide when frontmost, fullscreen | dynamicSpot per-app lists [U]; report 02 #3 | ✅ `AppRule` |
| **Per-activity-type toggles** ("Allow live activities from…") | iOS per-app switch [V]; Samsung per-app Now Bar switch [V] | ◐ `mutedSources`; needs UI |
| Per-display rules keyed by display UUID; follow the focused display | report 02 #3 | ◐ `DisplayMode`; add per-UUID |
| **Bubble placement** (right, left, below) and **max concurrent** (1–3) | New (from P0-1) | ❌ |
| Alert (sneak) duration; HUD duration | Implied by #4 | ❌ fixed at 2.5 s / 1.6 s |
| Quiet hours / Focus-aware suppression | CodeIsland "quiet hours" (report 01) | ❌ |
| Haptics: off / direct-only / all | report 02 §4C (off or single pulse by default) | ◐ bool |
| Gesture remapping | dynamicSpot [U] | ❌ |
| Pill position offsets on non-notch displays | dynamicSpot [U] | ◐ |
| Config as JSON (dotfiles) | — | ✅ `~/.config/islet/config.json` |

### 4.5 Haptics usage patterns

- **Hardware and API:**
  - `NSHapticFeedbackManager.defaultPerformer.perform(_:performanceTime:)` with `.generic`, `.alignment` or `.levelChange`.
  - Force Touch trackpads only. The feedback is felt only while a finger is on the trackpad [U].
  - Atoll reports haptics are **intermittent on macOS 27** (report 03).
- **Mapping:**

| Moment | Pattern |
|---|---|
| Force-click / hold opens expanded | `.levelChange` |
| Scrubbing crosses a detent (volume 0/100 %, each timer minute, a segment boundary) | `.alignment` |
| Two-finger swipe lands on the next activity | `.alignment` |
| Drop accepted on the shelf, or drag-out completed | `.generic` |

- **Never** for passive events (alerts, activity updates, device connects). The user's hand may be resting on the trackpad for unrelated work.
- Default to **direct-only**.

### 4.6 AI features: feasibility and design

| Feature | What | Why | Feasibility | Interaction |
|---|---|---|---|---|
| **On-device summarization** | Condense a burst of mirrored notifications, agent transcripts or CI logs into one compact line ("3 builds passed · 1 failed") and a 2–3 line expanded summary. Auto-generate `compactShort`. | The Apple Intelligence notification-summary precedent [U]; the compact wing holds ~10–14 characters | **Foundation Models framework**: public, on-device, macOS 26+, Apple Intelligence-capable Apple-silicon Macs with AI enabled [U: API not re-fetched]. Fallback: NaturalLanguage + rules. Guided generation for structured output. | Summaries marked with a small sparkle glyph; tap shows the originals |
| **Smart icons and tints** | Classify an activity (build, delivery, call, agent, download) → SF Symbol + tint when the source sends none. Tint from the app icon's dominant colour. | HIG says brand mark + colour; Islet's `smartIcons` exists | Rules + NaturalLanguage; app-icon colour via `NSWorkspace` + Core Image area average. Grade A. | Invisible; "Why this icon?" in the right-click menu |
| **Priority ranking** | `engagementBoost` learned locally from expands, opens and dismisses per source; interruption levels passive / active / time-sensitive / critical | iOS Priority Notifications and Reduce Interruptions precedent [U]; Samsung ordering | Own code; on-device only | Right-click: "Show less like this" |
| **"Ask" in the island** (iOS 27 Siri analogue) | Hotkey, or swipe down on the island → a prompt field under the notch. Route to Foundation Models or a user-chosen agent CLI. Stream progress as a Live Activity with "Thinking…" placeholders. | Apple moved Siri into the island [V]; Android's never-empty-state rule [V] | Public (the panel must become key only while typing; report 03 §3.2) | Answer collapses into a compact response bubble; click to expand |
| **Extract actions** | Meeting links, tracking numbers, addresses, OTP-like codes in activities or mirrored notifications → one-tap buttons | Vivo clipboard suggestions [U]; Samsung action buttons [V] | `NSDataDetector` (public) + LLM fallback | Buttons in the expanded view |
| **Welcome-back digest** | On unlock, one line of what changed while away | iPhone summary precedent | Combines P0-3 unlock with summarization | Tap → the stack |
| **Time-of-day brief** (P2) | Morning and evening: calendar, weather, reminders, overnight agent and CI results; optional speech via `AVSpeechSynthesizer` | Samsung Now Brief [V] | Public | Appears once per window; swipe away |

**Privacy:** everything runs on-device by default. Never send notification content off-device without explicit per-feature opt-in.

### 4.7 P1: next wave

| # | Feature | What / why | Feasibility | Ideal interaction |
|---|---|---|---|---|
| P1-1 | **Drag an activity out to share** | Drag a timer, ETA, agent result, build URL or now-playing link into Messages or Slack (Xiaomi) [S] | `NSDraggingSource` with text/URL items. Grade A. | Press and drag the island; a card "lifts" and follows the cursor; `.generic` haptic on drop |
| P1-2 | Notification mirroring as expanded alerts | The #1 request in report 02; the HIG says expand instead of banner | AX mirror, grade C (opt-in, labelled experimental) | Alert-expand with app icon, sender and two lines; hover pauses the timeout |
| P1-3 | AI summaries, smart icons, priority ranking | §4.6 | Foundation Models [U] / rules | §4.6 |
| P1-4 | **ProgressStyle and MetricStyle templates** | `segments[]`, `points[]`, `trackerIcon`, `startIcon/endIcon`; `metrics[≤3]{label,value,unit}` (Android 16/17) [V] | Own code | Compact shows the most important metric; expanded shows all three side by side |
| P1-5 | Remote updates | Webhooks, ntfy / SSE subscription, and **shared "channels"** (e.g., a sports feed many users subscribe to, like iOS broadcast channels) | Public networking; token auth | Same as local updates, with a per-source update budget |
| P1-6 | Plugin eligibility policy | Publish the Android/HIG rule: ongoing, user-started, no ads | Docs + enforcement (rate limits, per-source mute) | — |
| P1-7 | "Ask" field | §4.6 | Public | §4.6 |
| P1-8 | Limited-width mode | Mac equivalent of iOS 27 landscape: icon-only or `compactShort` when crowded or on narrow external displays | Own code | Automatic, with a subtle cross-fade |
| P1-9 | Right-click per-item settings | Samsung long-press → settings [V] | `NSMenu` | — |
| P1-10 | Welcome-back digest | §4.6 | B/C | — |

### 4.8 P2: later or experimental

| # | Feature | Feasibility | Notes |
|---|---|---|---|
| P2-1 | **Pull down to detach** a floating mini-window (timer, agent log, call controls) | Public (`NSPanel`) | Xiaomi [V] |
| P2-2 | Ambient song recognition ("What's playing around me?") | ShazamKit, public, mic permission; needs the ShazamKit service on the App ID [U] | Pixel Now Playing [V] |
| P2-3 | Time-of-day brief | Public | Samsung [V] |
| P2-4 | Clipboard-aware suggestions | `NSDataDetector`; macOS pasteboard-privacy prompts [U] → opt-in | Vivo [U] |
| P2-5 | **Two-axis scrub** in the expanded HUD: horizontal = one dimension, vertical = another (e.g., brightness × keyboard backlight, volume × balance) | Brightness and backlight grade C, volume A | The iOS 18 flashlight UI [S] |
| P2-6 | Live Activities on the lock screen (StandBy-like) | Private SkyLight, grade C, opt-in | Alcove and Atoll have lock-screen widgets (report 01) |
| P2-7 | iPhone companion for *Islet's own* activities, plus iOS Shortcuts → LAN bridge pushes | Needs an iOS app; cannot read other apps' activities | Apple already shows iPhone activities on Mac |
| P2-8 | Screen-recording indicator | Grade D heuristics | Only if reliable |
| P2-9 | Novelty (island pet, mini-game) as plugins | Public | Pixel Pals precedent [U] |

### 4.9 Infeasible or not worth it

- Reading other apps' iPhone Live Activities on the Mac: no API.
- Apple Pay, Face ID, Find My, NFC, Car Key and Apple Watch-unlock events: no Mac API. Touch ID prompts are not observable.
- AirPods noise-control mode changes: no known public API [U].
- Toggling Low Power Mode without admin rights: link to Settings instead.
- Focus via `INFocusStatusCenter`: entitlement only (report 03). Use the Shortcuts bridge.

### 4.10 Proposed API additions (illustrative JSON)

```json
{
  "id": "gh-run-123", "source": "github-actions",
  "title": "Deploy web", "icon": "sf:shippingbox.fill", "tint": "#34C759",
  "compactShort": "3/5", "url": "https://github.com/org/repo/actions/runs/123",
  "priority": "normal", "relevance": 60,
  "startedAt": "2026-09-30T18:00:00Z", "staleAt": "2026-09-30T18:20:00Z",
  "segments": [{"length": 1, "color": "green"}, {"length": 1, "color": "green"},
               {"length": 1, "color": "orange"}, {"length": 2, "color": "gray"}],
  "points": [{"at": 0.6, "label": "Tests"}], "trackerIcon": "sf:arrow.right.circle.fill",
  "metrics": [{"label": "Jobs", "value": "3/5"}, {"label": "Elapsed", "value": "4:12"}],
  "alert": {"title": "Tests failed", "body": "2 failures in api/", "sound": "default"},
  "dismissal": {"policy": "after", "at": "2026-09-30T18:45:00Z"},
  "actions": [{"title": "Re-run", "url": "islet-cb://gh/rerun/123", "kind": "button"}],
  "share": {"text": "Deploy web: 3/5 jobs", "url": "https://github.com/org/repo/actions/runs/123"}
}
```

---

## 5. Sources

### Apple (primary)
- HIG, Live Activities: https://developer.apple.com/design/human-interface-guidelines/live-activities · JSON: https://developer.apple.com/tutorials/data/design/human-interface-guidelines/live-activities.json [V]
- ActivityKit, Displaying live data: https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities [V]
- ActivityKit push notifications: https://developer.apple.com/documentation/activitykit/starting-and-updating-live-activities-with-activitykit-push-notifications [V]
- Creating custom views: https://developer.apple.com/documentation/activitykit/creating-custom-views-for-live-activities [V]
- Launching your app from a Live Activity: https://developer.apple.com/documentation/activitykit/launching-your-app-from-a-live-activity [V]
- ActivityKit updates: https://developer.apple.com/documentation/updates/activitykit [V]
- WWDC23 10194, "Design dynamic Live Activities": https://developer.apple.com/videos/play/wwdc2023/10194/ [V]
- WWDC25 278, "What's new in widgets": https://developer.apple.com/videos/play/wwdc2025/278/ [V]
- WWDC26 223, "Live Activities essentials": https://developer.apple.com/videos/play/wwdc2026/223/ [V] · third-party summary: https://wwdc.ai/2026/223
- App Review Guidelines (4.5.3): https://developer.apple.com/app-store/review/guidelines/ [V]
- Apple Support 120684, Live Activities on Mac: https://support.apple.com/en-us/120684 [V]
- Apple Support, Dynamic Island on iPhone: https://support.apple.com/guide/iphone/view-live-activities-in-the-dynamic-island-iph28f50d10d/ios (partially read)
- Apple Support 127257, macOS 27 what's new: https://support.apple.com/en-us/127257 [V]
- apple.com macOS: https://www.apple.com/os/macos/ [V]
- Newsroom, macOS Tahoe (Jun 2025): https://www.apple.com/newsroom/2025/06/macos-tahoe-26-makes-the-mac-more-capable-productive-and-intelligent-than-ever/ [S]
- Newsroom, WWDC26 (Jun 2026): https://www.apple.com/newsroom/2026/06/apple-unveils-next-generation-of-apple-intelligence-siri-ai-and-more/ [V]
- Newsroom, Siri AI (Sep 2026): https://www.apple.com/newsroom/2026/09/siri-ai-a-profoundly-more-capable-and-personal-assistant-is-here/ [V]

### iPhone press
- MacRumors, Dynamic Island guide: https://www.macrumors.com/how-to/use-dynamic-island-iphone-14-pro/ [V]
- MacRumors, iPhone 18 Pro smaller island with three Live Activities: https://www.macrumors.com/2026/09/09/iphone-18-pro-features-smaller-dynamic-island/ [V] · https://www.macrumors.com/2026/09/09/iphone-18-pro-dynamic-island-to-shrink/ [S]
- AppleInsider: https://appleinsider.com/articles/26/09/09/dynamic-island-now-shows-three-live-activities [V] · https://appleinsider.com/articles/26/09/09/dynamic-island-is-shrinking-yet-becoming-more-useful-in-the-iphone-18-pro [S]
- GadgetReview (the "below 100 layout points" claim): https://www.gadgetreview.com/iphone-18-pros-dynamic-island-shrinks-gets-a-third-live-activity-slot [S] · The Apple Post: https://www.theapplepost.com/2026/09/09/71936/iphone-18-pros-smaller-dynamic-island-can-show-three-live-activities-at-once/ [S]
- 9to5Mac, "iPhone 18 Pro's best Dynamic Island feature…": https://9to5mac.com/2026/09/22/iphone-18-pros-best-dynamic-island-feature-is-one-apple-barely-mentioned/ (title only; fetch failed)
- MacRumors, iOS 27 roundup: https://www.macrumors.com/roundup/ios-27/ [V] · iOS 27 Lock Screen: https://www.macrumors.com/2026/09/15/ios-27-five-new-features-iphone-lock-screen/ [S]
- Beebom, iOS 27 island gesture: https://gadgets.beebom.com/stories/ios-27-dynamic-island-gesture-rewired-how-i-use-my-iphone [V]
- 9to5Mac, iOS 26 Live Activities: https://9to5mac.com/2025/12/04/ios-26-made-live-activities-even-better-on-iphone-heres-whats-new/ [V]
- MacRumors, iOS 26 battery: https://www.macrumors.com/guide/ios-26-battery-improvements/ [S] · xarkas, iOS 26 beta 5 battery alert: https://blog.xarkas.com/ios-26-beta-5-update-rolls-out-with-dynamic-island-battery-warning-new-passcode-animation/ [S]
- Six Colors, island gestures (2022): https://sixcolors.com/post/2022/10/using-gestures-inside-the-dynamic-island/ [V]
- AppleInsider, iOS 17 island management: https://appleinsider.com/inside/ios-17/tips/how-to-manage-activity-on-the-dynamic-island-in-ios-17 [S]
- iOS 18 flashlight: https://appleinsider.com/inside/ios-18/tips/how-to-adjust-the-flashlights-focus-and-beam-shape-in-ios-18 [S] · https://9to5mac.com/iphone-flashlight-ios-18-how-it-works/ [S]

### Mac
- 9to5Mac, Mac Live Activities need only iOS 18: https://9to5mac.com/2025/06/16/macos-26-live-activities-work-even-if-your-iphone-is-on-ios-18/ [V]
- 9to5Mac, Live Activities on iPad and Mac: https://9to5mac.com/2025/06/13/live-activities-are-coming-to-ipad-and-mac-heres-how-theyll-work/ [V]
- iDownloadBlog, how to use Live Activities on Mac: https://www.idownloadblog.com/2025/06/28/how-to-use-live-activities-mac/ [V]
- Apple Community report: https://discussions.apple.com/thread/256139534 [V]
- MacRumors, macOS 27: https://www.macrumors.com/roundup/macos-27/ · https://www.macrumors.com/2026/06/08/apple-announces-macos-golden-gate/ [V] · Wikipedia: https://en.wikipedia.org/wiki/MacOS_Golden_Gate [V]
- macOS 27 menu bar: https://github.com/jordanbaird/Ice/issues/954 · https://badgeify.app/macos-27-golden-gate-menu-bar-changes/ · https://community.folivora.ai/t/macos-27-golden-gate-menu-bar-management-broken-solutions-ice-thaw-bartender-barbee-etc/47232 · https://www.bartendermacoslounge.com/blog/macos-golden-gate-menu-bar-management · https://appleinsider.com/articles/26/06/09/macos-golden-gate-menus-revert-to-having-no-icons-by-each-item-as-it-should-be [V third-party]
- Six Colors, Golden Gate first look: https://sixcolors.com/post/2026/07/first-look-macos-golden-gate-public-beta/ (via report 03)
- Tahoe menu bar height: https://forums.macrumors.com/threads/yet-another-stupid-thing-about-tahoe-new-ui-the-menu-bar-is-taller-for-no-reason.2465392/ · https://www.macrumors.com/2025/09/24/all-the-new-macos-tahoe-features/ [U, not re-verified]
- MacBook Pro with Dynamic Island rumors (via report 01): https://www.macrumors.com/2026/02/24/touchscreen-macbook-pro-dynamic-island/ · https://appleinsider.com/articles/26/06/26/oled-touchscreen-and-more-what-to-expect-from-the-2027-macbook-pro

### Android
- Samsung: https://www.samsung.com/us/support/answer/ANS10004605/ · https://www.samsung.com/in/support/mobile-devices/how-to-use-the-now-bar-on-the-lock-screen-of-your-samsung-galaxy-device/ · https://www.samsung.com/us/apps/one-ui/ [V]
- One UI coverage: https://www.androidauthority.com/one-ui-8-live-updates-support-3573794/ · https://www.sammobile.com/news/one-ui-8-5-two-more-additions-now-bar/ · https://www.androidauthority.com/one-ui-9-design-updates-3651981/ · https://www.androidpolice.com/one-ui-9-update-now-bar-widgets-gallery-details/ · https://www.sammobile.com/news/now-bar-one-ui-9-support-three-more-types-third-party-apps/ [V] · https://www.androidauthority.com/samsung-now-bar-missed-calls-3635654/ [S] · https://m.gsmarena.com/one_ui_7_now_bar_gains_google_maps_support-news-66311.php [S] · https://sammyguru.com/samsung-expands-app-support-for-now-bar-and-live-notifications/ [S]
- Xiaomi: https://technode.com/2025/08/29/xiaomi-rolls-out-hyperos-3-with-super-island-interface-similar-to-apples-dynamic-island/ [V] · https://eu.36kr.com/en/p/3443194625365637 [S] · https://xiaomiforall.com/xiaomi-hyperos-3-super-island-features/ [S] · https://gadgets.beebom.com/news/xiaomi-hyperos-3-announced [S] · https://baike.baidu.com/en/item/Xiaomi%20Super%20Island/3204198 [S]
- Google: https://developer.android.com/develop/ui/views/notifications/live-update · https://developer.android.com/reference/android/app/Notification.ProgressStyle · https://developer.android.com/develop/ui/views/notifications/metric-style · https://9to5google.com/2025/07/03/google-details-android-16-live-updates/ · https://www.androidauthority.com/android-16-qpr1-live-updates-3573399/ · https://www.androidauthority.com/android-17-live-updates-metric-style-template-3669117/ · https://www.androidauthority.com/android-17-stable-rollout-features-3675016/ · https://9to5google.com/2026/06/16/google-android-17-pixel-launch/ · https://9to5google.com/2025/02/27/pixel-at-a-glance-android/ · https://9to5google.com/2026/04/09/pixel-at-a-glance-location/ · https://blog.google/products-and-platforms/devices/pixel/march-2026-pixel-drop/ · https://www.androidcentral.com/apps-software/google-turns-pixels-now-playing-into-a-standalone-app-and-its-a-big-deal [V]
- Oppo, OnePlus, Vivo, Honor, Huawei, Nothing, Realme, dynamicSpot: **no pages fetched**. All [U]; re-verify.

### Companion reports (context)
- `01-market-analysis.md`, `02-pain-points.md`, `03-integrations-feasibility.md` in this folder.
- Islet source read: `Sources/IsletCore/Activity.swift`, `ActivityCenter.swift`, `Presenter.swift`, `Settings.swift`.
