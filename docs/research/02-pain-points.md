# 02 — User Pain Points with macOS "Dynamic Island / Notch" Apps

*Research date: 2026-09-30. Scope: NotchNook, Alcove, DynamicLake, MediaMate, TopNotch, boring.notch, NotchDrop, Atoll, MewNotch, Droppy and a few newer entrants.*

## How this was gathered and how far to trust it

- **GitHub issues** (primary, highest signal). I pulled these through the GitHub API, sorted by 👍 reactions and by comment count, and read the issue bodies and comment threads. Repos: `TheBoredTeam/boring.notch` (913 issues, ★10.9k), `Ebullioscopic/Atoll` (355 issues, ★4.8k), `Lakr233/NotchDrop`, `monuk7735/mew-notch`, `Wouter01/MediaMate-Releases`, `ungive/mediaremote-adapter`, `aviwad/LyricFever#94`, and `jordanbaird/Ice`.
- **Reddit** (r/macapps, r/MacOS, r/mac, r/macbookpro, r/swift). reddit.com blocks both automated fetching and the browser pane, so threads were read from the **Arctic Shift archive API**. Scores and comment counts are archive snapshots, and some posts show as `[removed]` by moderators.
- **Press and other sources**: MacStories, Macworld, Six Colors, 9to5Mac, Michael Tsai, the Apple Developer Forums, MacUpdate, Product Hunt, the HN Algolia API, Jamf and Help Net Security, and the Homebrew API.
- **Excluded as evidence**: SEO pages written by competing notch apps (notchnook.org, notchy.dev, getseam.app, favtray.com, crestnotch.app, brow-app.com, getdroppy.app/blog). They repeat claims such as "5% an hour" that I could not trace to a primary source.
- **Mac App Store reviews**: not usable. The iTunes Search API returns 0 ratings for almost every Mac notch app. The store also carries dozens of low-effort clones (NotchNest, NotchOS, GlowIsland, NotchThings, Notchly, and others).
- **Quotes**: all quotes are verbatim and 15 words or fewer. Where I paraphrase, the text says so.

---

## 0. Market snapshot (state on 2026-09-30)

| App | Model | Status / notable facts |
|---|---|---|
| **NotchNook** (lo.cafe) | $25 lifetime or $3/mo | **Effectively dead.** The license server is offline, lo.cafe does not resolve in DNS, and Homebrew **disabled** the cask on 2026-09-19 (`disable_reason: "unreachable"`). MacUpdate marks it "no longer supported by its developer". A long history of CPU/battery complaints preceded this. |
| **boring.notch** | Free, GPL-3.0 | The most popular (★10.9k), with 394 open issues. The last *stable* release was v2.7.3 on 2025-11-24; v2.8 RCs arrived 2025-09-23/25. It is **not Developer-ID signed**. |
| **Atoll** | Free, GPL-3.0 (a boring.notch fork) | Releases often, including alpha, beta and nightly channels. It had a CPU regression in 2.3.x, and it sent a DMCA notice that took down Droppy's repository. |
| **Alcove** | ~$14.99–16.99 one-time | Widely praised on r/macapps as the most polished. The solo developer was absent for months in 2025, which left license resets stuck. It showed on the main display only until mid-2026. |
| **DynamicLake** | Paid "Pro" | Updates often and added "Initial support for macOS 27" on 2025-08-15. A fake `DynamicLake.dmg` has been used to spread the **DigitStealer** infostealer. |
| **MediaMate** | Paid (Gumroad) | HUD and Now Playing focus. Sales were **paused** in April 2025. It **crashes on launch on macOS 27 betas and 27.x** because of a missing private SwiftUI symbol, and it has a memory leak. Users ask "Is this still alive?" |
| **NotchDrop** | Free, MIT | Shelf and AirDrop focus. Dragging files out of the shelf broke on Tahoe. |
| **MewNotch** | Free, GPL-3.0 | HUD focus. Some users got macOS malware warnings. Now Playing broke on 15.4. |
| **Droppy** | Paid (formerly open source) | An "all-in-one" app with a large feature list. Its GitHub repo was taken down after Atoll's DMCA notice in Feb 2026. |
| **TopNotch** | Free | Hides the notch with a black menu bar. A secondary source reports it broke on macOS 27. |

Apple context: **macOS 26 Tahoe** (2025) moved the volume and brightness HUD into small top-right popovers and started showing **iPhone Live Activities in the Mac menu bar**. **macOS 27 "Golden Gate"** (public 2026-09-14) redrew the menu bar as a single window, added a native overflow chevron for icons hidden by the notch, broke Bartender, Ice, Thaw and others, and renamed the **Accessibility** permission pane. Bloomberg reported in Feb 2026 that Apple's touch-screen MacBook Pro will have a Dynamic Island, so native competition from Apple is likely.

---

## 1. Ranked pain points

Ranking combines frequency (issue counts, 👍, comment volume, number of apps affected) with severity (whether it makes the app useless, costs money, or harms security).

### #1 — Now Playing / media integration keeps breaking (Critical · every app)

- **Apps affected**: all of them. boring.notch, NotchNook, MediaMate, MewNotch and Alcove all broke on macOS 15.4, and several broke again on Tahoe 26.0.
- **Frequency**:
  - boring.notch #417 is the **most-upvoted and most-commented issue in the repo** (54 👍, 58 comments). Its duplicate #434 has another 14 comments.
  - About 180 boring.notch issue titles mention music, media or now playing.
  - MediaMate #87 has 36 comments. Three or more r/macapps threads cover the same breakage.
- **Evidence**:
  - "Now Playing no longer working after updating to MacOS 15.4" — [boring.notch #417](https://github.com/TheBoredTeam/boring.notch/issues/417)
  - The maintainer said it will not be fixed by Apple: "the change was intentional and a security patch, not a bug." — [#417](https://github.com/TheBoredTeam/boring.notch/issues/417)
  - "MacOS 15.5 and still not working.. Will it ever get fixed?" — [r/macapps, NotchNook](https://www.reddit.com/r/macapps/comments/1j9fyys/)
  - "MediaMate sales have been paused until I can make sure the Now Playing functionality" — quoted in [MediaMate #91](https://github.com/Wouter01/MediaMate-Releases/issues/91)
  - "Apple broke the private API that allowed these apps to grab media playing from anywhere." — [r/macapps, Alcove](https://www.reddit.com/r/macapps/comments/1me5h94/)
  - Tahoe broke the Music app again: "Apple Music media source not working after updating to macOS 26" — [boring.notch #779](https://github.com/TheBoredTeam/boring.notch/issues/779) (8 👍)
  - The Tahoe breakage reached every scripting path: "It's broken with AppleScript, it's broken with Shortcuts" — [Apple Dev Forums 801357](https://developer.apple.com/forums/thread/801357)
- **Long tail**: users also ask for Tidal (#717), Plexamp (#730), Deezer (#1432), iTunes (#508, 15 comments), YouTube Music via Pear (#659, #1457), Cider, browser tabs (#1501) and Safari web apps. They report that switching between players loses media info (#1394) and that the repeat and shuffle state is wrong (#1510).
- **Release lag**: boring.notch stable went from **v2.6 (2025-02-23) to v2.7 (2025-11-22)**. Now Playing was broken in the stable build for about 8 months. Meanwhile users were told to build the `dev` branch in Xcode ([r/macapps "[FIX]" thread](https://www.reddit.com/r/macapps/comments/1kwik7c/)).

### #2 — CPU, battery and memory drain (Critical · NotchNook, boring.notch, Atoll, MediaMate)

**NotchNook**
- "why does nothnook take almost 40% of cpu usage" — [r/macapps, 2024](https://www.reddit.com/r/macapps/comments/1ejqaeb/)
- "The current versione is draining battery in an extreme way." — ["Don't buy NotchNook", r/macapps, 2025-10](https://www.reddit.com/r/macapps/comments/1o6epbk/dont_buy_notchnook/)
- "constantly using over 100% of the cpu and never going down" — same thread
- A separate thread is titled "NotchNook is sooo power-hungry after the last update" ([r/macapps](https://www.reddit.com/r/macapps/comments/1mt1mqm/)). Users there worked around it by downgrading to 1.4.6.

**boring.notch**
- "I get 3-5 hours instead of the normal 12-13." — [#338](https://github.com/TheBoredTeam/boring.notch/issues/338), M4 MacBook Pro
- In May–Aug 2026, users reported idle drain on 2.7.3 in [#1260](https://github.com/TheBoredTeam/boring.notch/issues/1260): "Sustained 26–41% CPU while idle." A community profile found "2,243 live NSTimer objects". The cause was leaked `Timer`s in the idle-face blink animation, one leaked on every play/pause transition.
- The 2.8 RC regressed: "The usage is consistently hifh, even if nothing is playing." — [#1607](https://github.com/TheBoredTeam/boring.notch/issues/1607)
- A user reported 336 MB of memory and asked for about 100 MB ([#1637](https://github.com/TheBoredTeam/boring.notch/issues/1637)).

**Atoll**
- "draining my battery by 20% in less than a hour" — [#641](https://github.com/Ebullioscopic/Atoll/issues/641) (12 comments)
- "Atoll always stays at 100% cpu utilization" — same issue
- An infinite SwiftUI render loop grew memory to "~2–3GB" ([#169](https://github.com/Ebullioscopic/Atoll/issues/169)).
- A Codex usage provider used more than 1 GB by loading the entire session history ([#701](https://github.com/Ebullioscopic/Atoll/issues/701)).

**MediaMate**
- The album-art cache is never released: "I just found it using 8GB of real memory on 15.7.7." — [#117](https://github.com/Wouter01/MediaMate-Releases/issues/117)

**Other signals**
- In the r/macapps thread about Droppy, a commenter reports Droppy "is around 100MB" of memory while idle ([thread](https://www.reddit.com/r/macapps/comments/1rdi2b0/)).
- New entrants now market "0% idle CPU" and "<30 MB RAM" as their headline ([r/MacOS](https://www.reddit.com/r/MacOS/comments/1rvydiu/)). Low resource use is now a buying criterion.

### #3 — Abandonment, business risk and licensing (Critical for trust · NotchNook, Alcove, MediaMate, Droppy, boring.notch)

**NotchNook**
- "Purchased a year ago, but now the license server is down" — [MacUpdate review, 2026-09-14](https://notchnook.macupdate.com/)
- Homebrew cask **disabled 2026-09-19, reason "unreachable"** — [formulae.brew.sh](https://formulae.brew.sh/cask/notchnook)
- "NotchNook's license server went offline this month" — [ILoveNotch PR #24](https://github.com/niyamvora/ILoveNotch/pull/24)
- The creators' notice attributes this to a dispute with former partners. They promise a successor called "NOOTCH" and a 90% discount for NotchNook license holders. I could only see this notice through search snippets because lo.cafe no longer resolves, so treat it as unverified.
- Earlier warning signs: "NotchNook also hasn't been updated in around 6 months now" ([r/macapps rant](https://www.reddit.com/r/macapps/comments/1kyfctg/)). Refunds were slow ([r/macapps "Scammers?"](https://www.reddit.com/r/macapps/comments/1n7caa2/)).

**Alcove**
- The solo developer's absence stalled license resets. Users responded: "This process should be automatic, independent of the developer" — [r/macapps, 64 pts / 48 comments](https://www.reddit.com/r/macapps/comments/1k93vkz/)
- "I don't like server-authenticated license schemes." — same thread
- Separately, the app stopped working for some users and could not open its settings ([r/macapps](https://www.reddit.com/r/macapps/comments/1luo5zk/)).

**MediaMate**
- "the app is currently not for sale, as I have little time" — developer, [MediaMate #96](https://github.com/Wouter01/MediaMate-Releases/issues/96)
- A user opened [#123](https://github.com/Wouter01/MediaMate-Releases/issues/123), "Is this still alive?"

**boring.notch**
- One user asked "why hasn't this repository been updated for 9 months?" ([#1491](https://github.com/TheBoredTeam/boring.notch/issues/1491)). A maintainer replied that there are about 101 open PRs and effectively one active maintainer.
- A Reddit thread asks "Boring Notch not updated in over half a year. Time to move?" ([r/macapps, 47 comments](https://www.reddit.com/r/macapps/comments/1u50f9e/))

**Droppy**
- Its repo went down after a DMCA notice from Atoll. A buyer was "dismayed to see an app I purchased discontinued" ([r/macapps, 158 comments](https://www.reddit.com/r/macapps/comments/1rdi2b0/)).

**Price and subscriptions**
- NotchNook's $3/mo option drew "ESPECIALLY the subscription!" ([r/macapps](https://www.reddit.com/r/macapps/comments/1ejqaeb/)).
- At launch it was around $40 (per the same thread).

### #4 — Fullscreen, video and accidental triggers (High · boring.notch, NotchNook, Atoll, NotchDrop, Droppy)

- "the boring notch on a external display is jarring and usually covers content" — [#119](https://github.com/TheBoredTeam/boring.notch/issues/119) (14 👍)
- "It's frustrating to have the notch show up when I'm watching netflix" — [#239](https://github.com/TheBoredTeam/boring.notch/issues/239)
- MacStories noted that NotchNook's Now Playing preview obscured fullscreen video ([MacStories](https://www.macstories.net/reviews/notchnook-and-mediamate-two-apps-to-add-a-dynamic-island-to-the-mac/), paraphrased).
- Hovering in a fullscreen Space reveals the title bar and it stays: "The icons remain visible and do not disappear until you exit fullscreen" — [#814](https://github.com/TheBoredTeam/boring.notch/issues/814), also [#522](https://github.com/TheBoredTeam/boring.notch/issues/522)
- False triggers:
  - "boring notch thinks I am trying to drag something into it and opens up" when dragging Safari tabs — [#1530](https://github.com/TheBoredTeam/boring.notch/issues/1530), [#875](https://github.com/TheBoredTeam/boring.notch/issues/875)
  - Moving the pointer across the notch to a monitor above "mistakenly activates" the notch — [#427](https://github.com/TheBoredTeam/boring.notch/issues/427)
  - Atoll: fast hover "triggers a rapid open-and-close cycle" — [#457](https://github.com/Ebullioscopic/Atoll/issues/457); hover fires twice — [#326](https://github.com/Ebullioscopic/Atoll/issues/326)
  - NotchDrop: users complained about trackpad haptics firing on every accidental sweep ([#43](https://github.com/Lakr233/NotchDrop/issues/43), [#25](https://github.com/Lakr233/NotchDrop/issues/25), paraphrased from Chinese)
- The opposite complaint, that the HUD disappears in fullscreen: "Does the app not appear over any other full screen app other than on desktop?" — [r/macapps, Droppy](https://www.reddit.com/r/macapps/comments/1un7biy/). MediaMate 3.8.2 had to fix "HUD would not appear in fullscreen apps on macOS 26" ([release notes](https://github.com/Wouter01/MediaMate-Releases/releases)).
- Games: I found no specific issue reports. Game engines already struggle with notch fullscreen (e.g., [winit #4162](https://github.com/rust-windowing/winit/issues/4162), [SDL #15071](https://github.com/libsdl-org/SDL/issues/15071)). Games are therefore covered only by generic "hide in fullscreen" requests.

### #5 — Multi-monitor, external displays, clamshell and notch geometry (High · all apps)

- "The monitor that wakes up first gets the notch." — [#174](https://github.com/TheBoredTeam/boring.notch/issues/174). Related: #348 (the notch jumps screens), #363 (it stays after a display is unplugged), #250 (it floats mid-screen after connecting a display).
- "The notch sometimes appears too far down and to the right." — after the lid is closed, [#352](https://github.com/TheBoredTeam/boring.notch/issues/352)
- Users want the notch to follow the focused display ([#1424](https://github.com/TheBoredTeam/boring.notch/issues/1424)) and to be off on non-primary or non-notch displays (#247 8 👍, #1415, #786, #829, #1281).
- A "software notch where there isn't a hardware one on my actual monitor" is jarring — [MacStories](https://www.macstories.net/reviews/notchnook-and-mediamate-two-apps-to-add-a-dynamic-island-to-the-mac/)
- Atoll:
  - "The Notch and Dynamic Island only hide after being expanded first." — [#487](https://github.com/Ebullioscopic/Atoll/issues/487)
  - The UI froze and was misplaced after returning to clamshell mode — [#327](https://github.com/Ebullioscopic/Atoll/issues/327)
  - Hide-until-hover broke on external displays — [#338](https://github.com/Ebullioscopic/Atoll/issues/338)
- NotchDrop broke when the built-in display is not the main display ([#9](https://github.com/Lakr233/NotchDrop/issues/9)).
- NotchNook: "No dual monitor support." ([r/macapps](https://www.reddit.com/r/macapps/comments/1o6epbk/dont_buy_notchnook/))
- Geometry:
  - The layout breaks on the M4 Pro notch width ([#448](https://github.com/TheBoredTeam/boring.notch/issues/448)).
  - The "whole screen shrinks" when a no-notch mode is mis-detected ([#683](https://github.com/TheBoredTeam/boring.notch/issues/683)).
  - Sneak peek renders outside the menu bar on non-notch displays ([#1410](https://github.com/TheBoredTeam/boring.notch/issues/1410)).

### #6 — Volume/brightness HUD replacement conflicts (High · boring.notch, Atoll, MediaMate, MewNotch)

- About 56 boring.notch issue titles mention HUD, brightness or volume.
- "When replace system HUD option is on, I can't adjust the brightness" — [#1040](https://github.com/TheBoredTeam/boring.notch/issues/1040). This happens with an external display, BetterDisplay or MonitorControl connected.
- "Boring Notch consumes the brightness key event and prevents it from reaching BetterDisplay" — [#943](https://github.com/TheBoredTeam/boring.notch/issues/943) (17 comments). Duplicate: [#1389](https://github.com/TheBoredTeam/boring.notch/issues/1389), in clamshell mode.
- "when the HUD is enabled, half-step increments are disabled" — [#1428](https://github.com/TheBoredTeam/boring.notch/issues/1428). Related: "extremely rigid screen brightness adjustment" — [#874](https://github.com/TheBoredTeam/boring.notch/issues/874)
- The native HUD still shows when brightness keys come from an external keyboard or Logi Options+ ([#1055](https://github.com/TheBoredTeam/boring.notch/issues/1055), [#1418](https://github.com/TheBoredTeam/boring.notch/issues/1418)). The native HUD also comes back after sleep ([#1381](https://github.com/TheBoredTeam/boring.notch/issues/1381), [#1426](https://github.com/TheBoredTeam/boring.notch/issues/1426)).
- Atoll:
  - "the Atoll animation and the native macOS “liquid glass” indicators appear simultaneously" — [#419](https://github.com/Ebullioscopic/Atoll/issues/419)
  - Its HUD changed volume in only the left ear with Bluetooth headphones — [#70](https://github.com/Ebullioscopic/Atoll/issues/70)
- MediaMate: "the method used with the system event controller does not work anymore on macOS 26.3" — developer, [#115](https://github.com/Wouter01/MediaMate-Releases/issues/115). Duplicate HUDs: [#104](https://github.com/Wouter01/MediaMate-Releases/issues/104), [#130](https://github.com/Wouter01/MediaMate-Releases/issues/130).
- MewNotch: automatic brightness changes trigger the HUD ([#5](https://github.com/monuk7735/mew-notch/issues/5)).

### #7 — Sleep/wake, lock and long-uptime instability (High · boring.notch, Atoll, Alcove, MediaMate)

- "The notch crashes/disappers/doesnt reopen once the device goes to sleep" — [#336](https://github.com/TheBoredTeam/boring.notch/issues/336) (44 comments, open since Jan 2025 and still recurring on Tahoe 26.3 in Apr 2026)
- The app freezes after about 2 days of uptime ([#438](https://github.com/TheBoredTeam/boring.notch/issues/438)).
- Quitting fails ([#1260](https://github.com/TheBoredTeam/boring.notch/issues/1260): "does not respond to the quit command").
- "Having to do things the app should've done itself after every restart" — a user explaining why they quit notch apps ([r/macapps](https://www.reddit.com/r/macapps/comments/1qihla1/))
- Atoll crashes when locking or starting the screensaver on macOS 27 ([#659](https://github.com/Ebullioscopic/Atoll/issues/659)).

### #8 — Install, trust, signing and permissions friction (High · boring.notch, MewNotch, Atoll, NotchNook)

**Signing and updates**
- The boring.notch updater failed with "The update is improperly signed" ([#855](https://github.com/TheBoredTeam/boring.notch/issues/855), 11 comments). The workaround people used was `xattr -d com.apple.quarantine`.
- A request to "avoid users needing to work around Gatekeeper when installing the app" — [#1460](https://github.com/TheBoredTeam/boring.notch/issues/1460). Related: #905, #1140, #115.
- r/macapps thread "Is boring notch safe?" (68 pts, 49 comments) — [link](https://www.reddit.com/r/macapps/comments/1mwr4kg/)
- MewNotch users got macOS malware warnings ([#21](https://github.com/monuk7735/mew-notch/issues/21)).

**Real malware**
- Jamf found **DigitStealer** shipped as a fake `DynamicLake.dmg` and spread through YouTube ([Help Net Security](https://www.helpnetsecurity.com/2025/11/20/macos-digitstealer-malware-poses-as-dynamiclake-targets-apple-silicon-m2-m3-devices/), [developer's HN post](https://news.ycombinator.com/item?id=46230333)).
- Training users to bypass Gatekeeper makes this attack easier.

**Permission sprawl**
- "Starting Atoll requests access to Developer Tools." It kept asking even after the features that need it were disabled — [#280](https://github.com/Ebullioscopic/Atoll/issues/280), also #299 and #480.
- Accessibility access is shown as not granted after it was granted ([#443](https://github.com/Ebullioscopic/Atoll/issues/443)).
- "NotchNook asks for permission to access aspects of your data several times." This was at a time when it had no privacy policy — [Macworld](https://www.macworld.com/article/2406934/notfhnook-macbook-dynamic-island-widgets-files-tray.html)
- macOS 27 renamed Accessibility to **"Device Control and Data Access"**, so in-app instructions now point to a pane that no longer exists ([#1561](https://github.com/TheBoredTeam/boring.notch/issues/1561)).

### #9 — Feature bloat, janky animations and "vibe-coded clone" fatigue (Medium–High · NotchNook, Droppy, Atoll, boring.notch)

**Polish versus features**
- "Seems instead of polishing the existing features, the developer just keeps on adding new ones." — [r/macapps (116 pts)](https://www.reddit.com/r/macapps/comments/1ejqaeb/)
- "I think of it as bloated rather than full of features" — [r/macapps](https://www.reddit.com/r/macapps/comments/1u50f9e/)

**Clone fatigue**
- "now it's just a bunch of broken vibecoded clones unfortunately" — [r/MacOS, 2026-09](https://www.reddit.com/r/MacOS/comments/1wqie07/)

**Forced animations**
- boring.notch's 2.5 "wobbly" animation produced the **top-voted feature requests in the repo**: #364 (26 👍), #350 (21), #335 (21), #303 (15), #316, #325.
- "Stuttering when opening" — [#341](https://github.com/TheBoredTeam/boring.notch/issues/341) (12 👍)
- Atoll's idle animations cause hover lag ([#624](https://github.com/Ebullioscopic/Atoll/issues/624)).

**What users praise instead**
- Alcove: users say it "feels almost like a system-level feature" ([r/macapps](https://www.reddit.com/r/macapps/comments/1opqfck/)).
- Minimal apps such as DynamicHorizon and MediaMate, because they stay small and subtle.

### #10 — Menu bar overlap, Mission Control and menu-bar-manager conflicts (Medium · boring.notch, MediaMate, Atoll)

- Expanded live activity "covers part of the options on the menu bar" — [#1399](https://github.com/TheBoredTeam/boring.notch/issues/1399). The maintainer replied that "the positioning is controlled by macOS and they cannot be moved."
- "collides with and partially covers the rightmost menu bar items" — [#1513](https://github.com/TheBoredTeam/boring.notch/issues/1513), also [#1091](https://github.com/TheBoredTeam/boring.notch/issues/1091)
- "Notch blocks spaces selector and controls" in Mission Control — [#1059](https://github.com/TheBoredTeam/boring.notch/issues/1059)
- Conflicts with menu-bar tools:
  - MediaMate overlapped Ice on Tahoe ([#107](https://github.com/Wouter01/MediaMate-Releases/issues/107)).
  - Ice hid the Tahoe HUD ([Ice #719](https://github.com/jordanbaird/Ice/issues/719)).
  - Atoll cannot be triggered while iBar runs ([#600](https://github.com/Ebullioscopic/Atoll/issues/600)).
- macOS 27 now draws the menu bar as one window, which broke Bartender, Ice, Thaw, Hidden Bar, Barbee, BetterTouchTool and others in beta ([Badgeify](https://badgeify.app/macos-27-golden-gate-menu-bar-changes/)).
- Stage Manager: I found **no** meaningful reports in any repo searched.

### #11 — File shelf, AirDrop and drag-and-drop bugs (Medium · boring.notch, NotchDrop, Atoll, NotchNook)

- About 42 boring.notch issue titles mention the shelf.
- Dragging Outlook attachments "fails with 'file not found'", and "isn't correctly resolving NSFilePromises" — [#1044](https://github.com/TheBoredTeam/boring.notch/issues/1044)
- "the file ends up on the desktop, right behind the notch." — [#1011](https://github.com/TheBoredTeam/boring.notch/issues/1011)
- NotchDrop on Tahoe: "Does not allow me to drop a file to desktop from the notch" — [#72](https://github.com/Lakr233/NotchDrop/issues/72)
- AirDrop:
  - "Airdrop is not available" happens when `NSSharingService(.sendViaAirDrop)` returns nil, typically because Desktop folder access is missing ([NotchDrop #4](https://github.com/Lakr233/NotchDrop/issues/4)).
  - boring.notch's direct AirDrop target was replaced by the Share menu ([#1276](https://github.com/TheBoredTeam/boring.notch/issues/1276)).
- No batch handling: "you must click and drag each file one at a time" — [Macworld on NotchNook](https://www.macworld.com/article/2406934/notfhnook-macbook-dynamic-island-widgets-files-tray.html). Also boring.notch #361 and #1039, Atoll #433.
- Atoll drag-and-drop is very slow ([#842](https://github.com/Ebullioscopic/Atoll/issues/842), [#688](https://github.com/Ebullioscopic/Atoll/issues/688)). In Atoll, shelf files can be dragged in but not out ([#749](https://github.com/Ebullioscopic/Atoll/issues/749)).

### #12 — Calendar and Reminders correctness and permissions (Medium · Atoll, boring.notch, NotchNook)

- About 44 boring.notch issue titles mention calendar or reminders.
- Atoll 2.3.2 shipped with Hardened Runtime but no entitlements, so "macOS refuses to even display the TCC prompt unless the matching resource-access entitlement is present" — [#634](https://github.com/Ebullioscopic/Atoll/issues/634). The same cause broke the camera and AppleScript. Earlier: [#41](https://github.com/Ebullioscopic/Atoll/issues/41).
- Date bugs:
  - All-day reminders show on the previous day ([#737](https://github.com/TheBoredTeam/boring.notch/issues/737), [#1134](https://github.com/TheBoredTeam/boring.notch/issues/1134)).
  - Tomorrow's reminders show in today's view ([#1469](https://github.com/TheBoredTeam/boring.notch/issues/1469)).
  - Hidden calendars still show ([#275](https://github.com/TheBoredTeam/boring.notch/issues/275)).
  - Atoll shows the wrong weekday ([#335](https://github.com/Ebullioscopic/Atoll/issues/335), [#352](https://github.com/Ebullioscopic/Atoll/issues/352)).
- Performance: Atoll takes seconds to switch dates ([#513](https://github.com/Ebullioscopic/Atoll/issues/513)).
- NotchNook: "There is no way to choose a default calendar" — [r/macapps](https://www.reddit.com/r/macapps/comments/1ejqaeb/)

### #13 — macOS 26 Tahoe and macOS 27 Golden Gate compatibility (Rising)

**Tahoe 26.x**
- AppleScript and ScriptingBridge for Music broke for streaming and non-library tracks (see #1).
- The HUD was redesigned, which caused duplicate HUDs (#6).
- MediaMate had to fix "notch HUD would appear behind the menu bar on macOS 26" (3.8.2 notes).
- The system-HUD suppression method stopped working on 26.3 (MediaMate #115).
- Users request Liquid Glass styling (boring.notch [#922](https://github.com/TheBoredTeam/boring.notch/issues/922)). Atoll had a "liquid glass freezing" bug ([#304](https://github.com/Ebullioscopic/Atoll/issues/304)).

**macOS 27**
- MediaMate crashes at launch: "dyld symbol resolution failure at launch rather than a runtime crash". The missing symbol is `SwiftUI._GraphValue.unsafeCast` — [#133](https://github.com/Wouter01/MediaMate-Releases/issues/133), [#134](https://github.com/Wouter01/MediaMate-Releases/issues/134), [#124](https://github.com/Wouter01/MediaMate-Releases/issues/124) (17 reactions, 21 comments).
- Atoll crashes on the lock screen ([#659](https://github.com/Ebullioscopic/Atoll/issues/659)).
- The Accessibility pane was renamed ([#1561](https://github.com/TheBoredTeam/boring.notch/issues/1561)).
- Brightness OSD replacement broke on a 27.x beta, reportedly transiently ([#1575](https://github.com/TheBoredTeam/boring.notch/issues/1575)).
- The menu bar is now a single window.
- There are energy reports on 27.0 ([#1607](https://github.com/TheBoredTeam/boring.notch/issues/1607)).
- The Perl MediaRemote adapter **still works on macOS 27.0** (badge: "last tested Sep 4 2026, macOS 27.0 (26A5425a)", [mediaremote-adapter](https://github.com/ungive/mediaremote-adapter)).

---

## 2. Top requested features (by 👍 / comment volume / cross-app repetition)

1. **Notifications in the notch**, with reply. This is boring.notch's top *open* feature request: [#592](https://github.com/TheBoredTeam/boring.notch/issues/592), 13 👍, "a must have". DynamicLake's notifications are the reference users cite. Also Atoll #808 and boring.notch #1489 ("True macOS Dynamic Island").
2. **Universal Now Playing from any app**: Tidal, Plexamp, Deezer, Cider, iTunes, browser players, Safari web apps. Users also want the ability to pin or focus one source (#391, #60) and a "favorite current song" control (Atoll #599).
3. **Per-display and per-context visibility**:
   - Disable on external displays (#247)
   - Hide in fullscreen or when media apps are active (#119, #239, #879)
   - Show only on the focused display (#1424)
   - Clamshell awareness (#786, #829)
   - Auto-hide in Mission Control (#301)
4. **Control over animations**: a toggle for the "wobbly" animation (#364/#350/#335/#303, about 83 👍 combined, the most-voted theme overall) and smoother open behavior (#341).
5. **Size and compact modes**: custom width and height (#300), a smaller music widget (#1037), a narrower open notch (#1353, #1377), and a compact pill that does not cover menu items (#1513).
6. **AI coding-agent status and approvals in the notch**. Examples: Claude Code session monitoring (boring.notch #951), and "Dynamic Island Integration for Terminal Command Permissions" (Atoll #390, Atoll's most 👍 issue). Standalone repos show the same demand: vibe-notch ★2.5k, CodeIsland ★2.4k, notchi ★1.0k, notchy ★0.7k.
7. **Headphone/AirPods battery and connection activity** (#1387 10 comments, #206 10 comments, #985, #694, #1614) and output-device switching (#1456, #1385).
8. **Lyrics**: a current lyric line, karaoke fill, and a multi-monitor lyrics bar (#1384, #1400, #617).
9. **More calendar providers**: Google, Outlook and Notion (#1473, #1270, #1413, #1235; Atoll #342), plus a configurable default calendar.
10. **Better shelf**: multi-select, grouping or stacking, a Dropover-style floating shelf with a shake trigger, and Quick Look (#361, #890, #1039, #1572, Atoll #433).
11. **External monitor brightness integration** with BetterDisplay or Lunar (#943, 17 comments; the BetterDisplay developer offered help).
12. **Smaller utilities**:
    - Teleprompter (#351, 8 👍)
    - Caffeine or keep-awake toggle (#1310, 11 comments)
    - Clipboard history and quick notes (#780)
    - Pomodoro (#1383)
    - Calls (#414)
    - Lock-screen widgets (the reason Alcove is popular)
    - NearDrop for Android (#768)
    - Homebrew install (#37, #281 with 13 comments, Atoll #306)
    - Liquid Glass theme (#922)
    - Localization (#1073)

---

## 3. Technical root causes and known workarounds

### 3.1 Now Playing (MediaRemote)

**Root cause (macOS 15.4, March 2025)**
- `mediaremoted` began checking the client's entitlements. It requires `com.apple.mediaremote.now-playing-read-access` / `full-now-playing-read-access` before returning now-playing info.
- Commands such as play and pause (`MRMediaRemoteSendCommand`) still work, which is why controls kept working while the UI went blank.
- Reverse engineering showed that the `localOrigin` path only allows `kernel_task`. This is documented by Mx-Iris in [LyricFever #94](https://github.com/aviwad/LyricFever/issues/94#issuecomment-2746155419).
- The error apps saw: `kMRMediaRemoteFrameworkErrorDomain Code=3 "Operation not permitted"`.

**Workarounds in use**
1. **Perl platform-binary adapter** ([ungive/mediaremote-adapter](https://github.com/ungive/mediaremote-adapter), BSD-3).
   - How it works: bundle an Objective-C `MediaRemoteAdapter.framework` and load it via `/usr/bin/perl` (a platform binary, which is privileged for private frameworks). The adapter streams JSON over stdout and supports `get`, `stream`, `send`, `seek`, `shuffle`, `repeat`, `speed` and `test`.
   - Status: last tested on **macOS 27.0 in Sept 2026** and actively developed. Recent work adds per-app reads (`--bundle-id`), sessions without a title, and fixes for a stream-startup race.
   - Used by boring.notch 2.7+, Atoll, and others. There is a Swift package fork, [ejbills/mediaremote-adapter](https://github.com/ejbills/mediaremote-adapter).
   - Caveats:
     - Apple can close this path at any time. The README says to ship the `test` command and fall back if it fails.
     - One downstream library states that the adapter framework needs a **Developer ID signature**, because ad-hoc signing "loads fine but every query returns an empty session" ([ultra-media-remote](https://github.com/michael-berardi/ultra-media-remote)). This is unverified by me.
     - The bundled test client loses hardened runtime during Developer ID export, so notarization fails unless handled ([boring.notch #1460](https://github.com/TheBoredTeam/boring.notch/issues/1460)).
     - Artwork on `MRNowPlayingRequest` is unreliable.
2. **Per-app AppleScript / ScriptingBridge** for Music and Spotify.
   - Needs one Automation (Apple Events) consent per target app. Users get stuck at that prompt and have to fix it with `tccutil reset` ([#779](https://github.com/TheBoredTeam/boring.notch/issues/779)).
   - Broke on **Tahoe 26.0** for streaming, autoplay and non-library Music tracks. It was partially restored in 26.1: song detected, album art missing ([#779](https://github.com/TheBoredTeam/boring.notch/issues/779)).
3. **Distributed notifications** from Music (`com.apple.Music.playerInfo`) and Spotify still work without entitlements ([LyricFever #94](https://github.com/aviwad/LyricFever/issues/94)). They are event-driven and cheap, but limited to those apps.
4. **App-specific local APIs**, for example the Pear Desktop (th-ch YouTube Music) HTTP API. These are fragile across app versions ([#1457](https://github.com/TheBoredTeam/boring.notch/issues/1457)).
5. **SIP-off injection** into `mediaremoted` ([MediaRemoteWizard](https://github.com/Mx-Iris/MediaRemoteWizard)). This is not acceptable for a mainstream app.
6. Browser extensions: I found no well-documented notch app that depends on one. Browser tabs are covered by the Perl adapter via Chromium and Safari MediaSession.

**State in macOS 26/27**: the restriction still stands. I found no public API or user-grantable entitlement for reading system-wide Now Playing as of Sept 2026. The adapter works on 27.0.

### 3.2 Performance

- **Leaked timers.** `Timer.scheduledTimer` is created inside SwiftUI views that are rebuilt on every play/pause and never invalidated. In boring.notch this produced 2,243 timers and roughly 748 fires per second. It was fixed on `dev` with a cancellable `Task` plus `onDisappear`, which dropped idle CPU from 26–41% to about 0% and memory from 157 MB to 73 MB ([#1260](https://github.com/TheBoredTeam/boring.notch/issues/1260)).
- **SwiftUI render loops.** A Music live activity animation re-triggered `GraphHost.runTransaction` about 1,900 times in a row ([Atoll #169](https://github.com/Ebullioscopic/Atoll/issues/169)).
- **Always-on visualizers and idle animations** kept running while the notch was collapsed (boring.notch #1260 maintainer note; Atoll #624).
- **Unbounded artwork caches and full-resolution decoding.** MediaMate #117 reached 8 GB. boring.notch #1427 decodes artwork at full resolution just to compute an average color.
- **Loading unbounded data** into memory, for example the entire Codex session history ([Atoll #701](https://github.com/Ebullioscopic/Atoll/issues/701)).
- **Hot hover and drag monitors.** Global mouse monitors and extended drag-detection areas run on every mouse move (see Ice #334 for the same energy pattern in menu-bar tools).

### 3.3 HUD replacement

Apps use three techniques today:

1. **A `CGEventTap` on `NX_SYSDEFINED` (type 14) media-key events** (boring.notch `MediaKeyInterceptor`, Atoll).
   - Requires Accessibility.
   - It consumes the key and **re-implements** volume and brightness itself, with fixed 1/16 steps. That loses Option+Shift quarter steps (#1428, #874), external-display DDC (#943, #1040), keyboards remapped by Logi Options+ or Karabiner (#1055), and per-channel Bluetooth volume (Atoll #70).
2. **Suspending `OSDUIHelper` with SIGSTOP**, plus a watcher, because launchd respawns it (Atoll `SystemOSDManager`).
   - The app must send `SIGCONT` or `launchctl kickstart` when it quits, or the system HUD stays frozen after the app exits.
   - This is why duplicates come back after a restart ([#419](https://github.com/Ebullioscopic/Atoll/issues/419)).
3. **A "system" event controller** (MediaMate). It broke on 26.3 ([#115](https://github.com/Wouter01/MediaMate-Releases/issues/115)).

Other approaches:
- **Observe instead of intercept.** Listen for CoreAudio volume changes and display-brightness changes, and show a HUD without eating the key. MewNotch does this. The side effect is that auto-brightness triggers the HUD, which needs filtering ([#5](https://github.com/monuk7735/mew-notch/issues/5)).
- **BetterDisplay OSD-notification integration** is now free (v4.1.2+), and the BetterDisplay developer offered to help ([#943](https://github.com/TheBoredTeam/boring.notch/issues/943)).

### 3.4 Windowing, fullscreen and geometry

- **Window setup.** The island is a borderless `NSPanel` at a high window level with `.canJoinAllSpaces` and `.fullScreenAuxiliary`. Some apps use private **SkyLight** calls (`SLSRemoveWindowsFromSpaces`, lock-screen spaces), as boring.notch's `BoringNotchSkyLightWindow` does. Private SPI is what breaks on new OS releases (Atoll #659 lock-screen crash on 27).
- **Fullscreen detection.** It relies on enumerating Spaces and fullscreen state through private CGS (boring.notch uses MacroVisionKit). Hovering the top edge in a fullscreen Space shows the title bar, and macOS only hides it again when the pointer re-crosses it (#814). There is no API for this.
- **Menu bar items cannot be moved** by third parties (#1399). Any island wider than the physical notch will cover menu items. macOS 27's single-window menu bar makes coordinating with menu-bar managers harder.
- **Notch geometry.** Use `NSScreen.safeAreaInsets` / `auxiliaryTopLeftArea` / `auxiliaryTopRightArea`. They return 0 or nil when the user picks a "below-notch" scaled resolution ([memo.d.foundation](https://memo.d.foundation/macbook-notch-macos-27)), which is the cause of mis-detection like #683. Notch width varies by model (#448).
- **Display reconfiguration.** Sleep, wake, lid, clamshell and hot-plug events are not re-handled robustly. Display identity is keyed by order rather than a persistent UUID, which explains "the monitor that wakes up first gets the notch" (#174), misplaced windows (#352) and disappearing windows (#336).

### 3.5 File shelf

- **File promises.** Drags from Mail and Outlook deliver `NSFilePromiseReceiver` promises. The boring.notch path checks only for a SwiftUI staging directory and misses Foundation's ([#1044](https://github.com/TheBoredTeam/boring.notch/issues/1044) root-cause comment).
- **Permissions.** Security-scoped bookmarks and folder TCC (Desktop, Downloads) are needed, or `NSSharingService(.sendViaAirDrop)` returns nil ([NotchDrop #4](https://github.com/Lakr233/NotchDrop/issues/4)). Bookmarks to unavailable SMB shares hang launch ([Atoll #583](https://github.com/Ebullioscopic/Atoll/issues/583)).
- **Drag-detection heuristics.** Detection triggers on non-file drags such as Safari tabs (#875, #1530).

### 3.6 EventKit

- On macOS 14+, apps must call `requestFullAccessToEvents` / `requestFullAccessToReminders` and include the `NSCalendarsFullAccessUsageDescription` / `NSRemindersFullAccessUsageDescription` Info.plist keys.
- Under Hardened Runtime, the `com.apple.security.personal-information.calendars` entitlement (and camera and Apple Events equivalents) must be present, or no prompt ever appears ([Atoll #634](https://github.com/Ebullioscopic/Atoll/issues/634)).
- All-day reminders use floating date components. Converting them through a time zone shifts them by a day (#737, #1134, #1469).

### 3.7 Notifications

- There is no public API for reading other apps' notifications.
- boring.notch 2.8 mirrors Notification Center banners through the **Accessibility tree** and replies via AX, parking the banner off-screen to keep it alive ([PR #1447](https://github.com/TheBoredTeam/boring.notch/pull/1447)).
- It is already buggy in nightlies: it re-triggers when Notification Center opens (#1577), and icons are missing (#1605).
- It is inherently fragile across macOS releases, as the Tahoe and 27 AX renames show.

### 3.8 Distribution and licensing

- **Unsigned builds.** No Developer ID leads to Gatekeeper friction, "is it safe?" threads and malware warnings. Users get used to bypassing Gatekeeper, and impersonators exploit that (DigitStealer).
- **Update-feed signature mismatches** break auto-update (#855).
- **Private SwiftUI/AttributeGraph symbols** in a shipped binary cause launch-time `dyld` failures on new OS releases (MediaMate on 27.x).
- **Server-validated licenses** fail when the vendor disappears (NotchNook, and Alcove resets in 2025).
- **Solo-maintainer bottlenecks** leave fixes stuck on `dev` for 9–10 months (boring.notch).

---

## 4. How a new open-source app should fix this

### A. Media: a layered, self-testing Now Playing pipeline
1. Use a **provider chain** ordered from cheapest to most complete:
   1. Distributed notifications (Music, Spotify)
   2. The MediaRemote Perl adapter (`stream`), validated at startup with `test`
   3. Per-app AppleScript/ScriptingBridge, prompting for consent only for apps the user enables
   4. Plugin providers (Pear, Cider, Tidal and others)
2. Make the active source visible in the UI, with a "why isn't my player showing?" diagnostic.
3. Isolate the adapter in a **separate helper process** with a clean restart and back-off policy. Treat its output as untrusted JSON and handle `Infinity`/`NaN` durations (adapter #8, #28). Developer-ID-sign the framework and keep hardened runtime on the test client.
4. Add a **"pin source" / per-app allowlist**, so browsers do not hijack the island, and handle multiple concurrent players (#1394).
5. Downsample artwork to display size and keep an LRU cache of about 20 items. Never hold full-resolution images.
6. Keep a **CI job on every macOS beta** (GitHub macOS runners plus a self-hosted beta Mac) that runs the adapter `test` and AppleScript probes. Publish a public compatibility matrix per macOS build.

### B. Performance as a feature, with published budgets
1. Budget: **0% CPU and no timers when collapsed and idle**, under 60 MB RSS at idle, and no animation when not visible. Enforce it with a performance test in CI: launch, run for 10 minutes, simulate 1,000 play/pause cycles, and assert on timer count, CPU and RSS.
2. Drive everything by events: NotificationCenter, KVO, CoreAudio listeners and async streams. Use no `Timer.scheduledTimer` in views, only `.task {}` with cancellation, and pause `TimelineView` and visualizers when collapsed or occluded (`NSWindow.occlusionState`).
3. Show an **"Energy" panel** in Settings with live CPU and RSS figures, and a one-click "Sample & export logs" button. Maintainers keep asking users for Activity Monitor samples, so build that in.
4. Load lazily. Features that are turned off (calendar, shelf, agents) should not initialize or hold data.

### C. Windowing, displays and fullscreen
1. Model visibility per display: {built-in notch, external with notch shape, external as pill, off}, plus a **"follow focused display"** mode. Key displays by `CGDisplayCreateUUIDFromDisplayID`, not order.
2. Offer **context rules**: hide in fullscreen (all apps, video apps only, or a custom list), hide during screen sharing and recording, and hide in Mission Control. Allow the HUD to still show in fullscreen as a separate toggle, because users want the HUD there but not the island.
3. Tune hover: a configurable dwell time, a velocity filter (ignore fast pointer passes across the notch toward a monitor above), and hysteresis and an exit buffer to prevent open/close bounce. Only enter "drop mode" for file, URL or text pasteboard types, never for tab drags. Haptics should be off by default or single-pulse.
4. Rebuild windows and re-read geometry on every `didChangeScreenParameters`, wake, screens-did-wake, lid and clamshell event, and on session switch. Add a watchdog that re-creates the panel if it disappears.
5. Detect geometry from `safeAreaInsets` and auxiliary areas, handle below-notch resolutions, and provide **manual width and height overrides** and a **compact mode** that never grows wider than the physical notch while a menu item sits under it.
6. Avoid private SkyLight and CGS calls in the core. Put any private SPI behind feature flags with runtime `dlsym` checks, so an OS update disables a feature instead of crashing the app.

### D. HUD: observe, don't hijack
1. Default to **observing** volume and brightness changes and suppressing the system OSD without consuming keys, so fine steps, DDC tools and Karabiner keep working.
2. Offer interception only as an opt-in "advanced" mode that forwards unhandled keys and honours Option+Shift steps.
3. Ship **native integrations** with BetterDisplay (OSD notification dispatch) and Lunar.
4. If `OSDUIHelper` is ever suspended, guarantee `SIGCONT` from a crash-safe path, such as a separate tiny watchdog or launch agent, so the system HUD cannot be left frozen.

### E. Trust and distribution
1. **Developer ID signed, notarized and stapled** from day one. Use reproducible builds from tagged CI with Sparkle EdDSA update signatures verified in CI (prevents #855). Publish a Homebrew cask with an automated SHA bump.
2. Put a **permission manifest in the README and in-app**: which feature needs which permission and why. Ask **just in time** and never at startup (Atoll #280). Use OS-version-aware wording for the macOS 27 pane rename and deep links.
3. Collect no telemetry by default, and publish a privacy policy (Macworld flagged NotchNook for lacking one).
4. Publish checksums and one official download domain, and warn about fake DMGs (DigitStealer).

### F. Sustainability (the anti-NotchNook guarantees)
1. **No license server.** Free and open source, with an optional donation or "supporter" build that never gates functionality.
2. **Governance**: at least 2–3 maintainers with release rights, a documented release train (for example, a stable release every 4–6 weeks plus beta and nightly channels), and a "macOS beta day-one" checklist. Avoid 9–10-month gaps between stable releases.
3. Use a permissive or clear license for the core, with **attribution hygiene** (the Atoll/Droppy DMCA fight hurt users of both).
4. A **plugin or extension API** for long-tail features (agents, stocks, Slack, lyrics, Pomodoro), so the core stays lean. Addresses the "bloat" complaint while still meeting demand.

### G. Features to prioritize (in order)
1. Rock-solid Now Playing plus the HUD, with the performance guarantees above. This is the "boring but perfect" core that Alcove and MediaMate fans value.
2. File shelf done right: file promises, multi-select, drag out to Finder and the web, AirDrop, Quick Look, and an optional floating Dropover-style shelf.
3. Display and fullscreen rules, compact mode and size overrides.
4. Calendar and Reminders with correct all-day handling, a default calendar and hidden-calendar support. Add Google and Outlook via EventKit accounts first, and a plugin for API providers.
5. Device activities: AirPods and headphone battery, connect and disconnect, output switching, and a charging activity.
6. An **AI coding-agent activity and approval plugin** (Claude Code, Codex, Cursor) built on local hooks and sockets, with no screen scraping. This is the fastest-growing demand signal.
7. Notifications with an **opt-in, clearly labelled experimental** AX mirror. Be honest that it is fragile, and never mark a reply as "sent" unless it really was sent (a lesson from PR #1447).
8. Liquid Glass theming as an option on Tahoe and later, with the classic black island as the default for continuity.

---

## 5. Sources

### GitHub issues and PRs (primary)

**boring.notch**
- Now Playing: [#417](https://github.com/TheBoredTeam/boring.notch/issues/417), [#434](https://github.com/TheBoredTeam/boring.notch/issues/434), [#779](https://github.com/TheBoredTeam/boring.notch/issues/779)
- Stability, performance and release cadence: [#336](https://github.com/TheBoredTeam/boring.notch/issues/336), [#338](https://github.com/TheBoredTeam/boring.notch/issues/338), [#341](https://github.com/TheBoredTeam/boring.notch/issues/341), [#1260](https://github.com/TheBoredTeam/boring.notch/issues/1260), [#1607](https://github.com/TheBoredTeam/boring.notch/issues/1607), [#1637](https://github.com/TheBoredTeam/boring.notch/issues/1637), [#1491](https://github.com/TheBoredTeam/boring.notch/issues/1491)
- Signing and installation: [#1460](https://github.com/TheBoredTeam/boring.notch/issues/1460), [#855](https://github.com/TheBoredTeam/boring.notch/issues/855)
- Displays and fullscreen: [#119](https://github.com/TheBoredTeam/boring.notch/issues/119), [#239](https://github.com/TheBoredTeam/boring.notch/issues/239), [#814](https://github.com/TheBoredTeam/boring.notch/issues/814), [#522](https://github.com/TheBoredTeam/boring.notch/issues/522), [#174](https://github.com/TheBoredTeam/boring.notch/issues/174), [#352](https://github.com/TheBoredTeam/boring.notch/issues/352), [#427](https://github.com/TheBoredTeam/boring.notch/issues/427), [#1424](https://github.com/TheBoredTeam/boring.notch/issues/1424), [#1281](https://github.com/TheBoredTeam/boring.notch/issues/1281), [#683](https://github.com/TheBoredTeam/boring.notch/issues/683), [#448](https://github.com/TheBoredTeam/boring.notch/issues/448)
- Menu bar and Mission Control: [#1399](https://github.com/TheBoredTeam/boring.notch/issues/1399), [#1513](https://github.com/TheBoredTeam/boring.notch/issues/1513), [#1091](https://github.com/TheBoredTeam/boring.notch/issues/1091), [#1059](https://github.com/TheBoredTeam/boring.notch/issues/1059)
- HUD: [#943](https://github.com/TheBoredTeam/boring.notch/issues/943), [#1040](https://github.com/TheBoredTeam/boring.notch/issues/1040), [#1389](https://github.com/TheBoredTeam/boring.notch/issues/1389), [#1428](https://github.com/TheBoredTeam/boring.notch/issues/1428), [#874](https://github.com/TheBoredTeam/boring.notch/issues/874), [#1055](https://github.com/TheBoredTeam/boring.notch/issues/1055), [#1418](https://github.com/TheBoredTeam/boring.notch/issues/1418), [#1575](https://github.com/TheBoredTeam/boring.notch/issues/1575)
- Permissions: [#1561](https://github.com/TheBoredTeam/boring.notch/issues/1561)
- Shelf: [#1044](https://github.com/TheBoredTeam/boring.notch/issues/1044), [#1011](https://github.com/TheBoredTeam/boring.notch/issues/1011), [#1276](https://github.com/TheBoredTeam/boring.notch/issues/1276), [#875](https://github.com/TheBoredTeam/boring.notch/issues/875), [#1530](https://github.com/TheBoredTeam/boring.notch/issues/1530)
- Calendar and Reminders: [#737](https://github.com/TheBoredTeam/boring.notch/issues/737), [#1469](https://github.com/TheBoredTeam/boring.notch/issues/1469), [#1334](https://github.com/TheBoredTeam/boring.notch/issues/1334)
- Notifications and feature requests: [#592](https://github.com/TheBoredTeam/boring.notch/issues/592), [#1489](https://github.com/TheBoredTeam/boring.notch/issues/1489), [#1577](https://github.com/TheBoredTeam/boring.notch/issues/1577), [#922](https://github.com/TheBoredTeam/boring.notch/issues/922), [#364](https://github.com/TheBoredTeam/boring.notch/issues/364), [#951](https://github.com/TheBoredTeam/boring.notch/issues/951), [PR #1447](https://github.com/TheBoredTeam/boring.notch/pull/1447)
- Source files: `MediaKeyInterceptor.swift`, `BoringNotchSkyLightWindow.swift`, `FullscreenMediaDetection.swift`

**Atoll**
- Issues: [#641](https://github.com/Ebullioscopic/Atoll/issues/641), [#169](https://github.com/Ebullioscopic/Atoll/issues/169), [#701](https://github.com/Ebullioscopic/Atoll/issues/701), [#659](https://github.com/Ebullioscopic/Atoll/issues/659), [#487](https://github.com/Ebullioscopic/Atoll/issues/487), [#327](https://github.com/Ebullioscopic/Atoll/issues/327), [#338](https://github.com/Ebullioscopic/Atoll/issues/338), [#419](https://github.com/Ebullioscopic/Atoll/issues/419), [#70](https://github.com/Ebullioscopic/Atoll/issues/70), [#280](https://github.com/Ebullioscopic/Atoll/issues/280), [#443](https://github.com/Ebullioscopic/Atoll/issues/443), [#634](https://github.com/Ebullioscopic/Atoll/issues/634), [#41](https://github.com/Ebullioscopic/Atoll/issues/41), [#513](https://github.com/Ebullioscopic/Atoll/issues/513), [#457](https://github.com/Ebullioscopic/Atoll/issues/457), [#624](https://github.com/Ebullioscopic/Atoll/issues/624), [#842](https://github.com/Ebullioscopic/Atoll/issues/842), [#390](https://github.com/Ebullioscopic/Atoll/issues/390), [#600](https://github.com/Ebullioscopic/Atoll/issues/600)
- Source file: `SystemOSDManager.swift`

**MediaMate** (Releases repo)
- Issues: [#87](https://github.com/Wouter01/MediaMate-Releases/issues/87), [#91](https://github.com/Wouter01/MediaMate-Releases/issues/91), [#96](https://github.com/Wouter01/MediaMate-Releases/issues/96), [#104](https://github.com/Wouter01/MediaMate-Releases/issues/104), [#107](https://github.com/Wouter01/MediaMate-Releases/issues/107), [#115](https://github.com/Wouter01/MediaMate-Releases/issues/115), [#117](https://github.com/Wouter01/MediaMate-Releases/issues/117), [#123](https://github.com/Wouter01/MediaMate-Releases/issues/123), [#124](https://github.com/Wouter01/MediaMate-Releases/issues/124), [#130](https://github.com/Wouter01/MediaMate-Releases/issues/130), [#133](https://github.com/Wouter01/MediaMate-Releases/issues/133), [#134](https://github.com/Wouter01/MediaMate-Releases/issues/134)
- [Release notes](https://github.com/Wouter01/MediaMate-Releases/releases)

**NotchDrop**
- Issues: [#4](https://github.com/Lakr233/NotchDrop/issues/4), [#9](https://github.com/Lakr233/NotchDrop/issues/9), [#25](https://github.com/Lakr233/NotchDrop/issues/25), [#43](https://github.com/Lakr233/NotchDrop/issues/43), [#72](https://github.com/Lakr233/NotchDrop/issues/72)

**MewNotch**
- Issues: [#5](https://github.com/monuk7735/mew-notch/issues/5), [#16](https://github.com/monuk7735/mew-notch/issues/16), [#21](https://github.com/monuk7735/mew-notch/issues/21)

**MediaRemote**
- [ungive/mediaremote-adapter](https://github.com/ungive/mediaremote-adapter)
- [ejbills/mediaremote-adapter](https://github.com/ejbills/mediaremote-adapter)
- [nohackjustnoobb/media-remote](https://github.com/nohackjustnoobb/media-remote)
- [Mx-Iris/MediaRemoteWizard](https://github.com/Mx-Iris/MediaRemoteWizard)
- [michael-berardi/ultra-media-remote](https://github.com/michael-berardi/ultra-media-remote)
- [LyricFever #94](https://github.com/aviwad/LyricFever/issues/94)

**Other GitHub**
- [Ice #719](https://github.com/jordanbaird/Ice/issues/719)
- [ILoveNotch PR #24](https://github.com/niyamvora/ILoveNotch/pull/24)
- AI-agent notch repos: [vibe-notch](https://github.com/farouqaldori/vibe-notch), [CodeIsland](https://github.com/wxtsky/CodeIsland), [notchi](https://github.com/sk-ruban/notchi)

### Reddit (via the Arctic Shift archive)
- r/macapps:
  - [NotchNook launch](https://www.reddit.com/r/macapps/comments/1d6jh22/)
  - [NotchNook Not Ready for Prime Time](https://www.reddit.com/r/macapps/comments/1ejqaeb/)
  - [Don't buy NotchNook](https://www.reddit.com/r/macapps/comments/1o6epbk/dont_buy_notchnook/)
  - [NotchNook power-hungry](https://www.reddit.com/r/macapps/comments/1mt1mqm/)
  - [NotchNook Rant](https://www.reddit.com/r/macapps/comments/1kyfctg/)
  - [NotchNook Scammers?](https://www.reddit.com/r/macapps/comments/1n7caa2/)
  - [NotchNook media broken 15.4](https://www.reddit.com/r/macapps/comments/1j9fyys/)
  - [MediaMate 15.4](https://www.reddit.com/r/macapps/comments/1jpxybv/)
  - [Alcove license reset](https://www.reddit.com/r/macapps/comments/1k93vkz/)
  - [Alcove stopped working](https://www.reddit.com/r/macapps/comments/1luo5zk/)
  - [Alcove YouTube](https://www.reddit.com/r/macapps/comments/1me5h94/)
  - [MediaMate vs Alcove](https://www.reddit.com/r/macapps/comments/1opqfck/)
  - [Droppy down / Alcove or Atoll](https://www.reddit.com/r/macapps/comments/1rdi2b0/)
  - [Boring Notch not updated](https://www.reddit.com/r/macapps/comments/1u50f9e/)
  - [Is boring notch safe?](https://www.reddit.com/r/macapps/comments/1mwr4kg/)
  - [Boring Notch Now Playing fix](https://www.reddit.com/r/macapps/comments/1kwik7c/)
  - [Should I keep Boring.Notch](https://www.reddit.com/r/macapps/comments/1qihla1/)
  - [Notch app recommendation](https://www.reddit.com/r/macapps/comments/1kth7qj/)
  - [DynamicHorizon minimal](https://www.reddit.com/r/macapps/comments/1rya7xv/)
  - [Droppy all-in-one](https://www.reddit.com/r/macapps/comments/1un7biy/)
- r/MacOS:
  - [0% idle notch app](https://www.reddit.com/r/MacOS/comments/1rvydiu/)
  - [ILoveNotch / vibecoded clones](https://www.reddit.com/r/MacOS/comments/1wqie07/)
  - [Tahoe iPhone Live Activities in menu bar](https://www.reddit.com/r/MacOS/comments/1onhhrl/)
  - [dynamic-island menu bar ask](https://www.reddit.com/r/MacOS/comments/1weplbk/)
- r/swift: [15.4 broke Now Playing](https://www.reddit.com/r/swift/comments/1jrj0wj/)

### Press, forums and other sources
- MacStories — [NotchNook and MediaMate](https://www.macstories.net/reviews/notchnook-and-mediamate-two-apps-to-add-a-dynamic-island-to-the-mac/) (Aug 2024)
- Macworld — [NotchNook](https://www.macworld.com/article/2406934/notfhnook-macbook-dynamic-island-widgets-files-tray.html) (Jul/Aug 2024)
- Six Colors — [macOS 27 review](https://sixcolors.com/post/2026/09/macos-27-golden-gate-review-bridging-the-tahoe-gap/)
- Michael Tsai — [Golden Gate and the Notch](https://mjtsai.com/blog/2026/09/25/golden-gate-and-the-notch/)
- 9to5Mac — [macOS 27 available](https://9to5mac.com/2026/09/14/macos-27-golden-gate-now-available-here-is-everything-new/)
- Badgeify — [macOS 27 menu bar changes](https://badgeify.app/macos-27-golden-gate-menu-bar-changes/)
- memo.d.foundation — [macOS 27 notch / 32-pt](https://memo.d.foundation/macbook-notch-macos-27)
- Apple Developer Forums — [801357](https://developer.apple.com/forums/thread/801357), [798267](https://developer.apple.com/forums/thread/798267)
- Doug's AppleScripts — [Tahoe and Music](https://dougscripts.com/itunes/2025/10/whats-up-with-macos-26-tahoe-and-music/)
- Jamf — [DigitStealer](https://www.jamf.com/blog/jtl-digitstealer-macos-infostealer-analysis/)
- Help Net Security — [DigitStealer / DynamicLake](https://www.helpnetsecurity.com/2025/11/20/macos-digitstealer-malware-poses-as-dynamiclake-targets-apple-silicon-m2-m3-devices/)
- HN — [fake DynamicLake post](https://news.ycombinator.com/item?id=46230333), [Apple touch MacBook with Dynamic Island (Bloomberg)](https://news.ycombinator.com/item?id=47162516)
- MacUpdate — [NotchNook](https://notchnook.macupdate.com/)
- Homebrew — [notchnook cask](https://formulae.brew.sh/cask/notchnook)
- Product Hunt — [NotchNook reviews](https://www.producthunt.com/products/notchnook/reviews)
- Vendor pages — [DynamicLake changelog](https://www.dynamiclake.com/changelog), [Alcove](https://tryalcove.com/)
- volumeHUD — [Tahoe HUD redesign context](https://github.com/dannystewart/volumeHUD)
