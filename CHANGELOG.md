# Changelog

## 0.2.0 (unreleased)

Islet now shows the Live Activities your iPhone sends to the Mac, answers coding agents' permission requests, runs timers, and asks Apple Intelligence, Claude or ChatGPT. It also stays beside the notch and shrinks to the free space in the menu bar.

### iPhone Live Activities
- Rides, deliveries, scores, flights and other Live Activities that macOS 26 and later show in the menu bar now appear in the island, including ones macOS has tucked behind the notch. Islet recognises them by the label macOS gives them, in all 41 of its languages, and never mistakes Now Playing, the Clock timer or the camera controls for one.
- A catalogue of 119 apps that use Live Activities gives each its icon, colour and layout: ride or delivery ETA with a moving marker, order stages, flight board, transit route, live score, timer ring, workout, gauge, live audio, media and agent.
- Clicking a mirrored activity opens Apple's own view of it. Nothing outside Islet can trigger that click.
- Needs Accessibility. Settings can limit mirroring to activities the notch hides, and mirrored text is kept out of the API unless you allow it.

### The menu bar
- The closed island always stays in the top row, beside the notch, like the iPhone's. With Accessibility it measures the free space beside the notch and fits itself to it, down to icon-only wings on a crowded menu bar. If even those don't fit, it keeps the icon-only wings, which may then cover the nearest menu bar item.
- Bubbles for other activities sit beside the island in the menu bar row and never cover a menu bar icon or hang below the row. When there's no room for them, the island shows how many there are ("+2") instead.
- It keeps clear of macOS 27's overflow chevron whenever there's room, and items hidden behind the chevron no longer make the menu bar look full.
- Measuring reads one window of the system menu bar instead of asking every app, and only while the island is showing.
- Mission Control now hides the island.
- **In full screen** chooses between Keep showing, Hide music only (timers, activities and HUDs stay) and Hide everything, replacing the on/off switch.
- On a display without a notch the island is a **Floating pill** inside the menu bar by default. It can also be a notch shape at the top edge, appear only when the pointer reaches the top edge, or not show at all. This replaces "Show on displays without a notch".

### Coding agents
- **Approvals.** Claude Code, Codex and Cursor can ask in the island: Allow, Always for this session, Deny, or answer in the terminal. Commands are shown in full, risky ones (recursive deletes, force pushes, sudo and more) need a second click, and questions and plans can be answered there too. If Islet isn't running or you don't answer, the agent asks in the terminal as usual.
- **Usage limits.** Claude Code's and Codex's 5-hour and weekly limits appear on Home, with one alert at 90% and at 100%. They come from files the tools write locally; no tokens are read and nothing goes over the network.
- Claude Code only hands its usage to its status line, so its limits need Islet's status line. When Claude Code is installed without it, Home shows Claude with a **Show usage** button that opens Settings at Usage limits, where a plain note says what changes (only `statusLine` in `~/.claude/settings.json`, with a backup) and nothing is written until you confirm. Home then says it is waiting for Claude Code until the first figures arrive. The "x" hides the hint for good.
- **Status for every connected agent.** Codex and Cursor, connected from Settings, now show each session in the island (Thinking, the command or tool that's running, Waiting, Done), not only approval cards. Codex's older `notify` setup still works.
- When Islet.app moves after an agent was connected, Coding agents says **Needs an update** instead of Connected, with a dot in the sidebar (checked once at launch), and **Update…** points the hooks at the new place. Hooks that call `isletctl` by name, as the examples in `integrations/` do, stay Connected. **Disconnect…** takes Islet's hooks out again after showing what it removes, and leaves everything else.
- **MCP.** `isletctl mcp` lets agents show progress, notes and timers in the notch as tools.
- Commands shown in the notch, and Codex's last message, hide anything that looks like a key or password.

### Ask
- An Ask box answered on the Mac by Apple Intelligence, by Claude or ChatGPT with your own API key (kept in the Keychain), or by the Claude Code and Codex command-line tools with the login you already have. ⌃⌥A opens it from anywhere.
- Answers stream in and stop when the island closes. Nothing is kept on disk, and an `islet://ask` link only fills in the question.
- Apple Intelligence now picks icons from a fixed set of categories, so its answers are always usable.

### Timers and Siri
- Timers you can start, pause, extend and stop from the island, the API, the URL scheme or `isletctl`, including phrases like "tea 4m" or "in 20 minutes to check the oven". A Pomodoro cycle. Timers survive a relaunch and ring with a sound of your choice.
- Siri reaches Islet through Shortcuts; [docs/SHORTCUTS.md](docs/SHORTCUTS.md) has the recipes.

### Now Playing and controls
- The scrubber seeks. ±15 seconds, shuffle and repeat where the player supports them, the system volume and an output picker.
- A new song shows for a moment: the island opens a little below the notch with the artwork, title and artist, then closes again. Skipping through tracks shows only the one you stop on, a song is shown once, and nothing shows for the first song after launch, while the island is open or hidden, or over a HUD or another peek. **Show the new song for a moment** in Settings (`songChangePeek`) turns it off.
- Changing song no longer snaps: the artwork swaps with a short spring, and in the open island the title and artist slide in from below. With Reduce Motion they fade.
- Two-finger swipes: down to open, up to close, sideways over music to change track. **Reverse sideways swipes** turns the sideways ones round.
- Keep awake for 15 minutes, an hour, two hours or until you turn it off.
- Battery thresholds are adjustable, with an optional "charged to 80%" alert.
- The playing indicator springs down to a dim, flat line when you pause and rises back into motion when you play, instead of jumping. Settings → Now Playing chooses its look (bars, slim bars, dots, wave, pulse or none) and its colour (from the artwork, the accent colour or white). With the accent colour on automatic, "accent" means the artwork's colour, as it does everywhere else. With Reduce Motion a playing song no longer looks paused, and in Low Power Mode the indicator holds still.
- Paused music stays beside the notch (or in its bubble beside an activity) for a while so the pause can be seen: the artwork dims and the indicator settles, then the island goes back to the notch. **Hide paused music after** sets how long (right away to 5 minutes, or never; 10 seconds by default) and replaces "Show paused music" (on becomes never).
- Play and pause change the moment you click, with the symbol morphing between them, then follow what the player reports.
- **Show song progress** (off by default) draws a thin ring round the artwork beside the notch that fills as the song plays. Core Animation fills it, so Islet does nothing while the song plays on.
- One **Music colour** now colours the playing indicator, the progress ring and the open island's progress bar, shuffle and repeat. It replaces the indicator's own colour setting (`visualiserColour` becomes `musicColour`).
- A new song stays on show for as long as **New activities stay open for** says, instead of a fixed 2.5 seconds.
- When the island opens on click, resting the pointer on the notch peeks at what's playing until the pointer leaves (**Peek at what's playing**, in General).
- **Switch between players.** With several players at once (a video in Chrome and a song in Spotify), the open island shows the others as small app icons beside the title, with a dot on one that is playing. Clicking one shows and controls that player, and the closed island follows, until another player starts playing. Commands go to the player on show: a press on Spotify no longer pauses the video Chrome is playing. A player the system doesn't treat as now playing is controlled directly, which for Spotify and Music needs Automation; without it, the island says **Allow Islet to control Spotify…** and opens Settings → Permissions.

### Calendar and reminders
- A Today tab with the rest of the day's events, Join buttons and reminders you can tick off. Repeating meetings now alert every time, and the agenda rolls over at midnight.
- **Meeting reminders that stay until you join.** From 10 minutes before a meeting (**Remind me before meetings**: off, 5, 10, 15 or 30 minutes), it shows beside the notch with its call app's icon (Zoom, Teams, Webex, FaceTime) or its calendar's colour, counting down ("9 min"), then "Now". It opens for a moment when it appears and again at the start, when it starts to glow. With **Keep reminding until I join** (on by default) it stays until you press Join, dismiss it (its ×, a swipe up, or Dismiss in its menu) or the meeting ends; without, it goes a few minutes after the start. Clicking it opens Home on the meeting with a large Join button. Being in a call in the meeting's app counts as joining, even one you joined a few minutes early from somewhere else, so it never glows while you are in the meeting.
- Only meetings with a call link remind you (**Only meetings with a call link**, on by default). All-day events, cancelled meetings and invitations you declined never do. Each occurrence of a repeating meeting is its own, and what you joined or dismissed is remembered across a relaunch. A Mac asleep through the start catches up when it wakes, and full screen and app rules hide reminders like other activities. These replace the old "starting soon" alert, and nothing checks the calendar every minute any more: Islet wakes only when a reminder is due.
- **Calendar access that explains itself.** The Calendar & Reminders page, the Today page and Settings → Permissions now say what macOS allows in plain words: not asked yet (**Allow…** asks), turned off in System Settings, restricted, or **Islet can only add events** ("Add events only"), each with **Open System Settings** at Privacy & Security → Calendars or Reminders and one line on what to switch. When Allow comes back refused without macOS asking, the System Settings route shows instead of nothing happening. While the calendar is on but can't be read, Home says so in one quiet line with the same button. Coming back from System Settings starts the calendar at once, without a relaunch.
- `GET /v1/state` and `isletctl state` include `calendar` with the access for events and reminders and how many events are left today, never their titles. Meeting reminders stay out of what scripts can read, change or remove: clearing the `calendar` source from a script leaves them alone.

### Look
- A calmer open island. The pages move out of the menu bar row into a small glass switcher under the island (Home, Today, Shelf and a menu for the rest), with a timer button on one side and Ask on the other. Home shows one main thing large, usually what's playing, with a quiet column beside it. Cards lost their borders, and spacing, corners and type follow one set of sizes.
- Dynamic Glass is the default theme. The open island takes a stem-and-body shape: only a notch-wide black stem sits in the menu bar row, so the menu bar beside the notch stays in view, and the island is Liquid Glass from the bottom of the menu bar (a blurred material before macOS 26), with the black melting a little way down under the stem. A faint smoke keeps text readable, and a slow sheen drifts across unless Reduce Motion or Low Power Mode is on. **Glass level** in Settings sets how far the black melts and how dark the glass is. The pin moves to the page switcher's menu as **Keep open**. Black and Graphite keep the full-width row.
- The closed island widens a little while the pointer rests on it, before it opens. It never grows downwards, and not at all with Reduce Motion.
- **Subtle outline** (Appearance) draws a faint edge round the island for dark wallpapers; Increase Contrast always draws it. **Glass on displays without a notch** makes the closed pill glass too with the Glass theme.
- **Animation speed** (Appearance) makes every move Relaxed, Normal or Quick, whatever the animation style.
- The island moves like liquid: bubbles bud off its side and are pulled back in, the shell springs open before its content fades in and the page switcher rises after it, closing clears the content first, a new activity's icon bounces in, a changed value morphs instead of popping, and a peek's shoulders no longer flash square corners or a nub, with or without a notch. Growing out of the notch and bouncing when something arrives, it keeps clear of the menu bar items beside it. Reduce Motion, Minimal, Off and Low Power Mode keep to short fades.
- An app on the Apps page can take any colour from the system colour panel, as the accent can, and a priority for its activities and notifications (low to urgent).
- **Reset appearance…** at the end of Appearance puts the look back as Islet came, after asking: everything on that page and the music's look. Fit to the notch stays as it is.
- **Artwork corners** (Appearance) go from square to round beside the notch, in a new song's peek and in the open island.
- **Fit to the notch** (Appearance) nudges the notch's width by up to 20 points and its height by up to 4, so the closed island lines up with the hardware. Hovering and clicking follow.
- Volume and brightness HUDs can be white, the accent colour or colourful (volume green, brightness yellow, keyboard light blue).
- HUDs can be **Compact** (in the wings, as before) or **Detailed**: a short line just below the notch with the icon, the level and a percentage, leaving the menu bar beside the notch clear. Keyboard brightness and microphone HUDs have their own switches beside volume and display brightness.

### Settings
- Settings is a sidebar window like System Settings, with a search field that finds any setting and opens its page at that row. Each feature page starts with its switch and one plain line; Appearance gathers every look, with a live drawing of the island, any accent colour and sizes you can drag; shortcuts are set by pressing them; Coding agents connects Claude Code, Codex and Cursor with one button each, showing the change first; and ports, tokens, hook commands and script widgets wait under Advanced.
- Appearance and Now Playing open with a live drawing of the closed island and a play/pause button, so the indicator and the pause can be judged without music playing.
- A shortcut field can record a combination that is already one of Islet's shortcuts; they pause while it listens, and come back if you switch to another app or close Settings.
- Buttons use sentence case. The Ask box says plainly when Claude Code or Codex isn't installed; where Islet looked is in Advanced → Diagnostics.

### Safer and lighter
- A crash when the Now Playing helper stopped, and a core spinning at 100% after it did, are fixed.
- Module switches in Settings take effect at once, and turning clipboard history off clears it, pinned items too.
- A typo in `config.json` no longer resets every setting. Islet keeps the settings it had and saves nothing over the file until it parses again; Settings → Advanced says which line has the error, and **Replace…** writes the settings in use over it, keeping a copy as `config.json.broken`. A file that is already broken when Islet starts (edited while it was quit) gives the settings from the last time it parsed, kept in `~/Library/Application Support/Islet/config-last-good.json`, rather than the defaults; with no such copy, Advanced says Islet is on its defaults. Keys Islet doesn't know, from a newer version or added by hand, survive a save.
- An unreadable `shelf.json` or `timers.json` is moved to `shelf.json.corrupt` or `timers.json.corrupt` before the shelf or timers start empty, instead of being saved over. Files on a disk that isn't connected stay on the shelf, dimmed, until it comes back.
- Clipboard history leaves out text that looks like a password when a browser copied it, since password manager extensions copy as the browser (**Skip passwords copied in a browser**, on by default), and **Ignore apps** leaves out any app you choose. **Clear unpinned** sits at the end of the Clipboard page.
- A calmer island: unlocking no longer shows an empty "Welcome back" when nothing arrived, and Clipboard is in the island's menu only while clipboard history is on.
- **Replace the system volume and brightness display** lets a key through to macOS when Islet can't act on it: brightness on another display or with the lid closed, brightness while BetterDisplay, MonitorControl or Lunar is running, volume on a fixed-volume output, and Option with a key, which opens Sound or Displays settings. Islet's HUD shows only a change that really happened. A key held down keeps the answer its press got, so macOS never sees a release without its press. Allowing Accessibility in System Settings starts it at once, without a relaunch.
- **Hide from screenshots** says that some screen-sharing and recording apps still show the island, and the island's glass draws solid while it's on, so it can't turn into a black slab.
- With the Now Playing helper unavailable, a Music or Spotify control that macOS hasn't allowed Islet to use now says **Allow Islet to control Spotify…** in place of the buttons, instead of doing nothing. Music or Spotify switched off in Settings sends no AppleScript at all, and a script can no longer reopen a player that has just quit.
- An activity's end, a HUD or a peek that fell due just as something else changed no longer stays on screen until the next event.
- `islet://` links can't replace Islet's own activities or open anything but https. Script widgets are off until you turn them on and only run files you own. Meeting links must be on the real host to get a Join button.
- Downloads, the clipboard and plugins stop checking while nothing changes or the screen is locked.
- A browser video no longer stays "playing" in the island after you close its window, and a video that finished without saying so shows as stopped and then goes.
- Local builds use the hardened runtime.
- Islet builds with Xcode 26 and the macOS 26 SDK as well as the macOS 27 one. Built with the macOS 26 SDK, the on-device model's errors are read from their description rather than macOS 27's error type.
- The iPhone bridge has its own token, separate from the local API's, with Copy and New Token in Settings → Advanced. It only accepts notifications, timers, Focus and simple activities (no links, buttons or image files), refuses a wrong token before reading the body, and limits bodies to 16 KB and connections to 8, 2 per client. Connections whose headers take longer than 2 seconds are closed. Bonjour advertises it as "Islet" rather than the Mac's name. `isletctl token --lan` prints its token.
- A request refused from its headers alone (a wrong token, a refused route, a body that's too large) now gets its answer through to clients still sending a large body, such as URLSession, instead of ending in a timeout or a lost connection.
- Calendar and Reminders access works in the app bundle: the hardened runtime needed the calendars entitlement, without which macOS refused access and never asked.
- Hovering opens the island when the pointer is pushed against the top edge of the screen. Settings can switch it to open on click instead.

### Measured on an M3 Pro MacBook Pro, macOS 27.0.1

MEASURED_TABLE

### Known issues
- Tested on macOS 27 only; mirroring Live Activities on macOS 26 is untested.
- How much text a Live Activity exposes varies by app.
- Apple Intelligence features need the on-device model to be downloaded.
- Siri can't call Islet directly yet: that needs App Intents metadata only Xcode can build.
- The build is ad-hoc signed, so macOS asks you to confirm the first launch.

## 0.1.0 (30 September 2026)

First version. Islet puts live activities in the space around the MacBook notch and lets other apps and scripts put their own there.

### What's in it

- **Now Playing** for any app that reports to macOS, including browser tabs. It works on macOS 15.4 and later, where Apple locked the private API most notch apps relied on. A small helper runs inside `/usr/bin/perl`, and the Music and Spotify notifications back it up.
- **Live activities** with progress, steps, countdowns and count-ups, states, buttons and links. You can send them with the `isletctl` CLI, a local HTTP API (loopback only, token required), the `islet://` URL scheme, or xbar-style script widgets.
- **Coding agents.** Claude Code hooks and Codex `notify` show what the agent is doing, and flag when it's waiting for you.
- **Calls.** A timer appears when FaceTime, Zoom, Teams, Slack, Discord, WhatsApp or a browser call is using the microphone.
- **System events.** Volume and brightness HUD, charging, low battery, Low Power Mode, audio output changes, Focus (through a Shortcuts automation) and a summary on unlock.
- **Calendar.** Next event, a reminder five minutes before, and a Join button for Zoom, Meet, Teams and Webex links.
- **File shelf** with AirDrop, clipboard history (off by default, skips password managers), download progress and system stats.
- **Notification mirroring.** Experimental and opt-in; needs Accessibility.
- **iPhone Shortcuts bridge.** Off by default. The same API is served on the local network with a token and a rate limit.
- **Appearance.** Compact, Standard and Large sizes; Black, Graphite and Glass themes; five motion styles including Off; up to three activities at once; per-app rules.

### Measured on an M3 Pro MacBook Pro, macOS 27.0.1

From `scripts/perf.sh` (8-second windows) and `Tests/E2E/e2e.py`:

| State | CPU |
|---|---|
| Idle | 0.0% |
| Music playing, closed island | 0.0% |
| Live countdown | 0.62% |
| Island open with Now Playing | 0.25% |

Memory stayed between 73 and 88 MB across those runs. 132 unit and system tests and 51 end-to-end checks pass.

### Known issues

- When something is showing in the closed island, its sides can cover menu bar icons that sit close to the notch. Fixed in the next version.
- Notification mirroring depends on Notification Center's accessibility tree and hasn't been tested against every app.
- Apple Intelligence features only switch on when the on-device model is downloaded. Otherwise Islet falls back to its own icon rules.
- The build is ad-hoc signed, so macOS will ask you to confirm the first launch.
