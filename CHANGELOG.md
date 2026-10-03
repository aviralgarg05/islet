# Changelog

## 0.3.0 (3 October 2026)

Islet now covers the Live Activities macOS draws in the menu bar, so each one shows in the island rather than twice, and it reads them properly: two at once are two rows, a pill that names no app is titled by what it says, and a countdown runs in the island instead of waiting on the menu bar. Music and videos playing in a browser show again, the icons beside the song offer every player macOS lists, and the island does far less work while music plays or a coding agent works.

### New
- **Hide the menu bar’s own** (Settings → Live Activities, on to begin with) covers each Live Activity macOS draws in the menu bar, so it shows in the island only instead of twice. While it’s on, every activity shows in the island, whether or not the notch hides it.

### Fixes
- A Live Activity whose app names its own picture something like `food_di_preparing_icon` no longer shows that as its title, and a time that arrives in two pieces reads as “13:01 min” rather than “13:01 · min”.
- Two Live Activities on screen at once show as two rows in the island instead of collapsing into one, and clicking one opens the one you clicked. Every pill macOS draws carries the same identifier, so Islet follows each by the pill itself.
- A Live Activity that begins just after another ends gets its own sneak peek, isn’t swallowed by the activity you dismissed before it, and no longer inherits its countdown or its layout.
- Muting a Live Activity from an app Islet doesn’t know mutes Live Activities, instead of muting a name taken from the pill’s own words: a cricket score gave `live-activity:ind-245-3`, which stopped matching on the next ball, and a flight gave `live-activity:on-time`. Nothing a pill says is written to `config.json`.
- A level score keeps both numbers: one-all reads “1 · CHE · 1” rather than “1 · CHE”, and the compact wing no longer shows a team’s abbreviation in place of a value.
- A unit in a language other than English stays with its number (“8 मिनट”, not “8 · मिनट”), and a word with no number in it, such as “Arriving”, “Boarding” or “On time”, no longer sits in the compact wing as though it were a value.
- A Live Activity whose title has an underscore in it, such as a Home Assistant entity (`washing_machine`) or a shortcut’s name (`morning_routine`), keeps its title instead of reaching the island with none.
- A Live Activity that names no app is titled by what it says, so the island reads “Delivered” rather than “Live Activity” above “Delivered”. Most pills expose one short label and no app name, so this is the usual case.
- A pill whose words merely hold an app’s name no longer takes that app’s name, symbol and layout: “Man United 2 - 1 Arsenal” was titled with the whole phrase and drawn as a flight. An address with a comma in it is no longer split into a title and a subtitle either.
- A countdown the island animates stops as soon as Islet can no longer tell which way the time is going, instead of counting down to a moment that is no longer true.
- A Live Activity that shows its countdown with the unit beside it, such as “13:01 min”, counts down in the island, instead of showing a number that moved only when the menu bar did. Islet reads the time wherever it sits in the pill’s words rather than only at the end.
- A link such as `islet://activity?title=x&steps=1e300` no longer ends Islet. Every number in an `islet://` link is now checked before it is used, and one too big for Islet to hold is refused like any other bad value.
- A pill whose value reads like a clock no longer ends Islet when the figure in front of the colon is absurdly large, whether it came from a link, a script or your iPhone.
- A song whose lyrics file holds an absurd timestamp no longer ends Islet. Anyone can upload lyrics to LRCLIB, so one bad line used to crash Islet for everyone who played that song.
- Sales figures, model sizes, request counts and a temperature reading from a service that sends something absurd no longer end Islet.
- Typing in the island and then letting your Mac sleep no longer leaves the island holding the keyboard. Before, after waking (or after a display change, or a change to the island’s size in Settings) the island never closed when you moved away, and it took keystrokes meant for the app you were in.
- A scrub or volume drag interrupted by waking, or by a display change, no longer leaves the island open for good.
- When a timer rings, opens the island and you then close it, reopen it and choose **Keep open**, the island stays open when the timer stops ringing instead of losing the pin you set.
- `config.json` kept in your dotfiles as a symlink stays a symlink: the first change in Settings used to replace it with an ordinary file, after which Islet and your repo quietly held different settings.
- A focus sound keeps playing when you connect or disconnect AirPods, instead of going silent for the rest of the round while Islet still showed it as playing.
- A video or live stream whose player reports no real length no longer stops Now Playing from letting go of the track.
- Switching Now Playing off and on quickly, or using **Try again**, no longer leaves a stray helper behind or counts a failure against the restart limit.
- Turning the privacy indicators off and on during a video call brings the camera dot back, instead of leaving it off for the rest of the call.
- Deleting a script widget while the screen is locked or asleep no longer ends Islet, and a widget that leaves something running in the background (`foo &`, ssh, a daemon) no longer ties up a little more of Islet on every run.
- A shortcut that leaves something running in the background now reports back instead of never finishing.
- Muting a Live Activity mirrored from the menu bar no longer leaves a black rectangle over the menu bar’s own pill, which hid it altogether.
- A request waiting for an answer in the notch is only ever shown on a display that has an island, so an agent is no longer left waiting with no card anywhere after your Mac wakes or the displays change.
- A busy Exchange or Google calendar no longer makes the island hitch while it is read.
- The iPhone bridge can no longer fill the island with pills that never go: each one lasts at most an hour unless it is sent again.
- Download pills keep working after the Downloads folder is replaced or restored from the Trash.
- An `islet://ask` link opened with no island on any display no longer leaves the island pinned shut.
- A chunked upload to the local API gets its `411` with an explanation instead of a reset connection.
- Spotify cover art is fetched the way every other request Islet sends is: nothing kept between songs, nothing written to disk.
- A title, subtitle, trailing value or source sent by a script, a link or your iPhone is cut to one line of what the island can draw, instead of stretching the row.
- The local API caps how many connections it keeps at once, and lets go of one whose request never arrives, so another program on this Mac can’t tie it up.
- The iPhone bridge no longer tells anyone on the Wi-Fi Islet’s exact version when they ask whether it’s there.
- A script widget’s link opens only if it’s a web address, and a command you run from its menu starts with the same scrubbed environment a scheduled run gets.
- The files holding the API and bridge tokens are written afresh and moved into place, so a link left where one of them goes can’t catch the token.
- Oversized request headers are refused however they arrive.
- Lyrics and weather requests refuse redirects, so a song’s title or a place you typed can’t be carried to another site.
- Scripts can no longer read the text of the notifications Islet mirrors. Banner titles and text now need **Let scripts read Live Activities and notifications** (Settings → Advanced → Local API), the same setting as the Live Activities Islet mirrors, instead of showing in `GET /v1/activities` and `GET /v1/state` whatever the setting said.
- A Focus pill set by a link now shows as its own pill rather than replacing the one Islet shows for the Mac’s Focus, and a very long Focus name is shortened to fit the island. A Focus from your iPhone still shares that pill, so only one Focus shows at a time.
- Live Activities from your iPhone show in the island again. macOS builds the menu bar’s Live Activity differently from every other item, so Islet read an empty part of it and passed over it.
- Music and videos playing in a browser show on the island again. A live stream, or a video whose length the browser doesn’t know, used to stop Now Playing for every app until the Mac slept and woke.
- The app icons beside the song now offer every player macOS lists, such as Spotify paused a while ago beside a video playing in Chrome. For a player macOS hasn’t given the controls to, a press says which app has them and offers to open the player, instead of doing nothing.
- A video’s artwork from Chrome no longer blinks off and on while it plays, and the next video no longer keeps the last one’s picture.
- If Islet stops seeing what other apps play, the video it last showed no longer stays on the island as playing with controls that do nothing. Islet tries again on its own a few minutes later, and switching Now Playing off and on starts it afresh.
- A browser video playing beside a song in Spotify or Music no longer takes the island back every few seconds after the next song starts.
- Closing a video that was playing no longer brings back a song paused minutes earlier as if you had just paused it.
- Next and previous are faint for a browser video without a next track, rather than doing nothing when pressed.
- With nothing on the island, play or pause from a link, a script or **Your music** goes only to a player the island would offer, never to an app in **Ignore apps** or a source you switched off, and a seek goes nowhere.
- At the end of a focus round, **Your music** pauses only the player it started, so a video you started during the round keeps playing.
- Swiping to move through a live stream, or skipping 15 s from a script, no longer takes it back to its start.
- Lyrics for a song in a browser show even when the browser sends the video’s length a moment after its title.
- Opera Beta, Opera Developer, Opera Air, Helium, SigmaOS, Waterfox, LibreWolf, Tor Browser, Mullvad Browser, Yandex Browser and DuckDuckGo from the App Store count as web browsers, for Now Playing’s **Web browsers** switch, lyrics and calls in a browser.
- Settings changed from the island (time left, a Pomodoro length, a tool’s **Turn on**, Lyrics, Mute, turning on the calendar) are saved and applied at once, and Settings shows them straight away.
- A change made just after Islet saved something else, such as a slider still moving in Settings, is no longer undone a moment later.
- Switching to a busy app no longer makes the island hitch while Islet starts following that app’s windows for full screen.
- With an island on every display, moving from the open island onto another display closes it after the usual moment instead of leaving it open.
- With Shelf off, files dropped on the notch are refused rather than kept on a hidden shelf.
- Turning off **Answer requests in the island** sends waiting requests back to the terminal at once, and lets go of the island.
- Closing the island while a request waits no longer pins it or closes it later under the pointer. A card with several questions keeps the answers given when hidden or moved to another display.
- **Fit the menu bar** fits the wings again as soon as a menu bar item appears or widens, with Live Activities off too.
- The Clipboard page goes back to All once its filter has nothing left, and stays there when such a clip comes back.
- With Accessibility, a video or game that goes full screen without switching apps is noticed, and so is it leaving, for **In full screen**.
- The Ask chip in the island now changes the provider in Settings → Ask & AI, and it’s kept after a restart. A link’s provider lasts until the island closes.
- Changes made while `config.json` has a typo are kept when it’s fixed, rather than lost.
- Edits to `config.json` by hand always load, including undoing one and a config folder replaced by a dotfiles tool. With Settings open, Islet no longer rewrites a file you edited by hand.
- **Mute** in the island now silences Islet’s own cards too: battery, sound output, keep awake and welcome back. A battery about to run out still warns you.
- An app muted from the island shows as muted in its row on the Apps page, and a muted feature, such as meeting reminders, is listed on its own page with **Unmute**.
- Unmuting brings back a running timer, stopwatch, meeting reminder or keep awake at once, and so does **Reset**.
- Settings follows Accessibility, camera and location changes made in System Settings while it’s open.
- Turning Accessibility off and on again no longer hands the volume and brightness keys back to macOS’s display.
- Turning on Lyrics shows the playing song’s lyrics at once, not from the next song.
- After a smaller size, the closed island starts at the new width instead of shrinking to it, and bubbles moved to the left of the notch can be clicked at once.
- Opening the lid of a Mac that started with it closed shows Islet’s brightness display when you change the brightness.
- Dismissing a Live Activity from the island uncovers the pill it came from, instead of leaving a black rectangle in the menu bar with the activity nowhere to be seen until the pill went away on its own.
- A Live Activity you muted is no longer covered for a moment after Islet starts, which showed as a black rectangle in the menu bar on an otherwise quiet Mac.
- A timer that rings while there is no island anywhere just rings, instead of pinning a display that draws nothing.
- A coding agent’s request that arrives in the first second after waking waits for the island rather than going straight back to the terminal.
- An `islet://ask` link or ⌃⌥A with no island on screen keeps the question for the next time the island opens, instead of dropping it.
- A Downloads folder sent to the Trash and put back is followed again, rather than leaving download pills off for the rest of the session.
- A script widget removed while the screen is locked no longer leaves a row behind that nothing clears, and a widget whose script keeps working after closing its own output no longer stops every other widget.
- The Shortcuts page says it couldn’t read your shortcuts rather than showing an empty list as though you had none.
- Scripts can no longer count or clear the notifications Islet mirrors while **Let scripts read Live Activities and notifications** is off. A count alone said how many banners were on screen.
- A script’s `source` is taken as written: one with a stray space is refused for the names Islet keeps for itself, instead of slipping through and then escaping **Mute**, and one too long to hold is refused rather than shortened into a name that **Mute** and `?source=` would never match again.
- `config.json` linked into a dotfiles repo that isn’t set up yet stays a link, and the first change in Settings writes the repo’s file and makes its folder.
- A client using a short `ttl` as a liveness window, re-armed every second, keeps its activity on the island instead of losing it between two of its own reports.
- `isletctl` reports a number it can’t hold as a mistake in the command, and the MCP server ignores one instead of stopping.
- Agendas are read with their own handle on your calendar, so a busy Exchange or Google account can’t clash with the month view on Today.

### Performance
- Islet does far less while music plays and while a coding agent works. Both used to tell Islet the same thing over and over — a player reports its position about once a second, and an agent’s hooks fire a couple of times a second — and each report redrew the whole island although nothing on it had changed. Now a report that says nothing new leaves the island exactly as it is, while a seek, a pause, a new track, a new step or any other real change still shows at once.
- The island works out the order of what it shows once per change instead of once per thing that asks, and its right-click menu is built when you right-click rather than on every update.
- A coding agent’s hooks are quicker to take in: the patterns that hide secrets and read a command are prepared once instead of for every event.
- Full screen detection skips its Accessibility checks when the windows haven’t moved, and reading the menu bar no longer goes through every running app each time.
- Cover art is decoded at the size the island draws it, so a 3000 pixel cover no longer costs tens of megabytes of memory while its track plays, and Music’s cover art is no longer decoded twice.
- `make perf` now measures two more states, with a client reporting throughout, so this can’t quietly come back.

## 0.2.0 (2 October 2026)

Islet now shows the Live Activities your iPhone sends to the Mac, lets you answer coding agents' permission requests in the island, runs timers, and asks Apple Intelligence, Claude or ChatGPT. It also stays beside the notch and shrinks to the free space in the menu bar.

### Highlights
- **Your iPhone's Live Activities** in the island: rides, deliveries, scores and flights, with their own look for 137 apps.
- **Answer Claude Code, Codex and Cursor from the notch**, and see Claude Code's and Codex's usage limits on Home.
- **Ask** Apple Intelligence, Claude, ChatGPT or your command-line agent a quick question with ⌃⌥A.
- **Timers, a Pomodoro and a stopwatch**, started from the island, a phrase like "tea 4m", Siri or a script.
- **Meeting reminders** that count down beside the notch and stay until you join.
- **Tools you switch on when you want them**: to-dos, a note, a converter, emoji, lyrics, the weather, a camera mirror, a teleprompter, stocks and sales.
- **More from Now Playing**: switch between players, see each new song for a moment, and choose a turning record or an animated sticker beside the notch.
- **A calmer look**: the Glass theme, a page switcher under the island, and Settings rebuilt as a sidebar window you can search.

### iPhone Live Activities
- Rides, deliveries, scores, flights and other Live Activities that macOS 26 and later show in the menu bar now appear in the island, even ones hidden behind the notch. Islet recognises them in any of macOS's 41 languages. Needs Accessibility.
- 137 apps get their own icon, colour and layout, such as a ride ETA with a moving marker, a flight board or a live score.
- Clicking one opens Apple's own view of it. You can mirror only what the notch hides, and mirrored text stays out of the API unless you allow it.
- Before macOS 26, which has no Live Activities in the menu bar, the page says so and Islet doesn't ask for Accessibility to read them.
- **Only when the notch hides them** applies at once to what is already showing, rather than at the next change in the menu bar.
- **Mute** in the right-click menu silences one app's Live Activities, and Settings → Apps lists what you've muted, each with **Unmute**. One you dismiss stays away until it leaves the menu bar, and one unchanged for 30 minutes dims.

### The menu bar
- The closed island always stays in the menu bar row beside the notch. With Accessibility it fits the free space, down to icon-only wings; without it, a display narrower than 1500 points (a 13-inch MacBook Air) gets icon-only wings.
- Other activities sit in bubbles beside the island and never cover a menu bar icon. With no room for them, the wing counts them ("+2").
- Values beside the notch are never squeezed or cut: a narrow wing says "18m" or "2h", or shows a symbol. Flight countdowns read in minutes like every other countdown, and a finished activity's tick shows once.
- Something urgent lights the island's edge from inside rather than glowing over the icons beside it. The island keeps clear of the overflow chevron when there's room, and items hidden behind the chevron no longer make the menu bar look full.
- With only the music sticker to show (**Also when nothing is playing**), the island hugs the notch with one small wing.
- **In full screen** offers Keep showing, Hide music only or Hide everything, worked out per display, and an app's **Keep the island in full screen** rule on the Apps page overrides it. A game that goes full screen a moment after opening is caught, a large window under a menu bar that hides itself no longer counts by mistake, and Mission Control hides the island.
- On a display without a notch the island is a **Floating pill** in the menu bar by default, which grows out of the middle of the row when something appears. It can also be a notch shape, appear only when the pointer reaches the top edge, or stay hidden.

### Coding agents
- **Approvals.** Claude Code, Codex and Cursor can ask in the island: Allow, **Always** (for the rest of the session), Deny or **Answer in the terminal**. Risky commands (recursive deletes, force pushes, sudo and more) need a second click. Questions and plans can be answered there too.
- If Islet isn't running or you don't answer in time, the agent asks in the terminal as usual. A card that runs out of time leaves the agent's status saying **Answer in the terminal**, so it never waits unseen.
- **Status for every agent.** Codex and Cursor now show each session (Thinking, the running command, Waiting, Done), as Claude Code does. Codex's older `notify` setup still works.
- Settings → Coding agents connects each agent with one button, showing the change first. If Islet.app moves, the agent's row says so and **Update…** fixes it. **Disconnect…** removes Islet's hooks and nothing else.
- Connecting an agent or adding the status line says what changes in plain words, with the exact lines under **Show the exact change**. A settings file Islet can't read or change is said in a sentence, never as a file format or a system error.
- With **Accept requests from apps on this Mac** off, Coding agents says connected agents can't reach Islet and offers **Turn on**, and the iPhone bridge's switch says it needs it.
- **MCP.** `isletctl mcp` lets agents show progress, notes and timers in the notch.
- An agent's status and Codex's last message hide anything that looks like a key or password. Approval cards still show the whole command, so you see what you're allowing.
- An agent's status reads in words: "Running swift build" without the `cd` into the project before it, and other tools by what they do. Approval cards show a tool's details as plain lines, and **Always** says what it allows ("commands starting with “npm test”").
- **Usage limits.** Claude Code's and Codex's 5-hour and weekly limits appear on Home, with a short alert beside the notch at 90% and again at 100%. They are read on this Mac: no sign-in is read, and nothing goes over the network.
- Claude Code shares its limits only with its status line, so Home offers **Show usage** to add Islet's. Nothing is written until you confirm; then only the status line changes, and a backup is kept.
- **More usage on Home**, each off until you switch it on under Coding agents → Usage limits: OpenRouter spending, Copilot premium requests (with a read-only GitHub key) and the models Ollama has loaded. They are fetched only when the island opens, and keys are kept in the Keychain.
- A Claude Code session that has finished stays Done: the reminder Claude Code sends a minute later, while it waits at the prompt, no longer brings it back to the notch as Waiting.

### Ask
- An Ask box answered by Apple Intelligence on the Mac, by Claude or ChatGPT with your own API key (kept in the Keychain), or by the Claude Code and Codex command-line tools with the login you already have. ⌃⌥A opens it from anywhere.
- Answers stream in and stop when the island closes, and nothing is kept on disk. A missing or refused key gets a plain hint with **Add a key…** or **Change the key…**, and the box says so when Claude Code or Codex isn't installed.
- Models are named as people say them ("Claude Opus 5.5") in Ask & AI and under each answer, and Ask & AI checks for new ones.
- When Ask can't answer it says why in words, such as a service having problems or too many questions at once, never a status code.

### Timers and Siri
- Timers from the island, the API, the URL scheme or `isletctl`, with phrases like "tea 4m" or "in 20 minutes to check the oven", and a Pomodoro cycle (25/5, 50/10 or 90/20 minutes). They survive a relaunch and ring with a sound you choose.
- A paused timer shows its time left in grey beside the notch. One that ended over an hour ago, while the Mac slept or Islet was closed, leaves a quiet note instead of vanishing.
- Siri reaches Islet through Shortcuts; [docs/SHORTCUTS.md](docs/SHORTCUTS.md) has the recipes.

### Tools
Every tool starts off until you turn it on in Settings, on the Tools page or the page of the feature it belongs to. A tool with a page of its own then appears under More. The System page (CPU and memory) now starts off too.
- **To-dos**: add, star and tick off lines; what's left comes first.
- **Quick note**: a scratch pad that saves as you type.
- **Unit converter**: type "5 ft in cm" or "100f to c" and click the answer to copy it. While it's on, the Ask box answers conversions too.
- **Emoji**: search by name or the words people use ("lol", "tada") and click one to copy it, or to type it where you were with **Type emoji where you're typing** (needs Accessibility).
- **Lyrics** (Now Playing): time-synced lyrics from LRCLIB beside the song on Home, for Music and Spotify and, with **Also for music in a web browser**, songs on YouTube, YouTube Music and other sites; click a line to jump there. Only the title, artist, album and length are sent, once per song.
- **Shortcuts**: search and run your shortcuts from the island or the Ask box.
- **Weather**: now and the week ahead from Open-Meteo, with no account, for a city or for where you are. Location is asked for only when you choose "Where I am", and the position is rounded to about a kilometre.
- **Month calendar** on Today (Calendar & Reminders), with days that have events brighter.
- **Stopwatch** (Timers) with laps, beside the notch and on Home.
- **Focus sound** (Timers): brown noise, rain, waves or your own music during Pomodoro focus rounds.
- **Camera mirror**: your camera under the notch for a quick look before a call. It runs only while the page is open, and nothing is recorded.
- **Teleprompter**: your script scrolls just under the camera at 60 to 300 words a minute, so you read while looking into the lens.
- **Stocks**: a watchlist of up to 12 shares, indices or currencies from Yahoo Finance, fetched only while the page is open.
- **Sales**: today's takings from Stripe, Shopify, Lemon Squeezy, Gumroad, Dodo Payments, Polar and Paddle, with a read-only key per store kept in the Keychain. Islet asks every 15 minutes while the Mac is unlocked and not in Low Power Mode, and when you open the page.
- Sales, stocks and usage requests go only to the service each one names, over HTTPS (Ollama stays on this Mac), with no cookies, and never follow a redirect, so a key can't end up anywhere else.

### Now Playing and controls
- The scrubber seeks, and the open island has ±15 seconds, shuffle and repeat, the system volume and an output picker.
- A quote button on the song shows or hides its lyrics. With lyrics off it says what turning them on sends, and nothing is sent until you click **Show lyrics**.
- **Switch between players.** With a Chrome video and a Spotify song at once, small app icons beside the title switch between them and the controls follow, so a press on Spotify no longer pauses Chrome's video. The closed island keeps showing whatever plays.
- When macOS doesn't list Spotify or Music as now playing, Islet controls them directly; without Automation it says **Allow Islet to control Spotify…** instead of doing nothing.
- Each new song shows for a moment below the notch, for as long as **New activities stay open for** says, and **Show the new song for a moment** turns it off. When the island opens on click, resting the pointer on the notch peeks at what's playing (**Peek at what's playing**).
- Changing song swaps the artwork with a short spring instead of snapping, and play and pause change the moment you click.
- Paused music stays beside the notch for a while, dimmed, so you can see the pause. **Hide paused music after** (10 seconds by default) replaces **Show paused music**.
- The playing indicator settles to a flat line when you pause. Settings → Now Playing chooses its look: bars, slim bars, dots, wave, pulse, **Mirror**, **Vinyl** (the artwork turns like a record) or **Sticker**. With Reduce Motion a playing song's indicator holds still and fades gently up and down, so it never looks paused.
- **Sticker** puts a little animated sticker in the right wing while music plays: one of five drawn for Islet, or up to 12 of your own GIFs, animated PNGs, WebPs or HEICs, added with **Add…**. **Left and right**, **Up and down** and **Size** place it inside the menu bar row. It freezes when you pause and stops in full screen and with Reduce Motion.
- One **Music colour** (the artwork's, the accent colour or white) colours the indicator, the progress ring and the open island's progress bar, shuffle and repeat. **Show song progress** draws a thin ring round the artwork that fills as the song plays.
- **Ignore apps** (Now Playing → Sources) keeps an app's media out, and an app that isn't a music or video player shows only once it has played for 3 seconds, so a voice message doesn't take over. More browsers, such as Dia, Opera GX and the beta versions of Chrome, Edge, Brave and Firefox, now count as web browsers, for calls and clipboard history too.
- On Home the song's title keeps its room: at the Compact size the volume button and other players (folded into one "+3" chip) make way first.
- Fixed: the progress bar drifting back after a seek in Spotify, a browser video that stayed "playing" after it ended or its window closed, and a crash and a core at 100% when the Now Playing helper stopped. If the helper stops for good, Settings → Now Playing offers **Try again**.
- Keep awake for 15 minutes, an hour, two hours or until you turn it off. Battery alerts have thresholds you set and an optional "charged to 80%", and time left reads in words ("2 h 10 min left").

### Calendar and reminders
- A Today page with the rest of the day's events, Join buttons and reminders you can tick off.
- **Meeting reminders that stay until you join.** From 10 minutes before (or 5, 15 or 30, or off), a meeting with a call link counts down beside the notch with its call app's icon, glows when it starts, and stays until you join, dismiss it or it ends. Being in the call already counts as joining.
- All-day events, cancelled meetings and declined invitations never remind you, every occurrence of a repeating meeting does, and a Mac asleep through the start catches up. These replace the old "starting soon" alert.
- **Calendar access that explains itself.** The Calendar & Reminders page, Today and Settings → Permissions say in plain words what macOS allows, with a button to the right part of Privacy & Security. Coming back from System Settings starts the calendar at once.
- On Home a meeting says "In 9 min", and a list too long to fit says how many more ("+2 more"). Cancelled events no longer show, and an event just added on another device no longer reminds you twice.

### Look
- A calmer open island: the pages move into a small glass switcher under it (Home, Today, Shelf and More), with a timer button and Ask on either side, and Home shows one main thing large. **Pages in the switcher** (General) turns pages on or off and orders them, and the pin moves to the switcher's menu as **Keep open**.
- Glass is now the default theme. Only a notch-wide black stem sits in the menu bar row, so the menu bar stays in view, and the island below is Liquid Glass (a blur before macOS 26). **Glass level** sets how far the black reaches down. Black and Graphite keep the full-width row. Closing, the glass turns black evenly and the island shrinks into the notch as one shape.
- The island moves like liquid: bubbles bud off its side, the shell springs open before its content fades in, and changed values morph. Minimal and Reduce Motion use short fades, Off doesn't animate, Low Power Mode keeps the motion at a lower frame rate, and **Animation speed** makes moves Relaxed, Normal or Quick.
- The closed island widens a little under the pointer before it opens, and a peek no longer flashes square corners.
- New in Appearance: **Subtle outline** for dark wallpapers (always on with Increase Contrast), **Glass on displays without a notch**, **Artwork corners**, **Fit to the notch** (adjusts the notch's width by up to 20 points and its height by up to 4 to match the hardware) and **Reset appearance…**.
- Graphite keeps the menu bar row black, so the notch doesn't show as a dark bite, and a player without artwork shows its own icon.
- An app on the Apps page can take any colour and a priority (low to urgent).
- When an activity sets no icon, Apple Intelligence now picks one from a fixed set of categories, so it always gets an icon that exists.
- HUDs can be **Compact** (in the wings) or **Detailed** (a short line below the notch with a percentage), and white, the accent colour or colourful. Keyboard brightness and microphone HUDs have their own switches; the keyboard's works while Islet replaces the system volume and brightness display.

### Calm by default
- Volume and brightness HUDs start off in a new setup, since macOS shows its own. Turn on **Replace the system volume and brightness display** to see only Islet's. Older configs keep what they had.
- A new sound output's card has its own switch, **Sound output changes**, and the level a new output sets for itself shows no HUD.
- Mirrored notifications stay beside the notch, since macOS shows its own banner; **Peek at new notifications** opens them below the notch too. Each banner is mirrored once.
- A call shows once its app has held the microphone for 3 seconds, and a browser or chat app first shows a quiet **Microphone in use**. A dismissed call stays away until the microphone is free.
- Unlocking no longer shows an empty "Welcome back", and Clipboard is in the More menu only while clipboard history is on.
- **Welcome back** names who sent what as you know them ("3 from Claude Code · 2 from Downloads"), never by Islet's internal names.

### Using the island
- The first time Islet runs, one short peek says how to open it: rest the pointer on the notch, or press ⌃⌥I.
- With the island open, only what is drawn takes clicks; a click just outside reaches the window underneath.
- Pushing the pointer against the top of the screen over the notch now opens the island, as resting on the notch does.
- A peek under the pointer no longer opens the island or takes a click meant for what was there, and closing the island with the pointer on the notch no longer reopens it.
- The island stays open while you type a timer, use a right-click menu or drag a file out of the shelf.
- Two-finger swipes open and close the island and change track (or skip 10 seconds) over music; **Reverse sideways swipes** turns them round.
- **Quit Islet** is in the island's right-click and More menus and Settings → About, for when the menu bar icon is hidden behind the notch.

### Shelf and clipboard
- **Keep files on the shelf for** an hour, a day (the default), a week or until you remove them; only the shelf forgets them, never the files. A shelf from an earlier version keeps its files until you choose. Each file has an AirDrop button, and files on a disconnected disk stay, dimmed.
- Clipboard history keeps links, colours, pictures and files as well as text, each shown as itself, with search, filters and **Clear unpinned**. Pictures stay in memory only, and nothing marked secret is read.
- **Skip passwords copied in a browser** (on by default) leaves out what password manager extensions copy, and text shaped like a generated password, but keeps ordinary text such as "Windows11". **Ignore apps** leaves out any app you choose.
- Turning clipboard history off clears it, pinned items too.

### VoiceOver, contrast and the keyboard
- VoiceOver reads the island in words ("Claude, my-app, waiting for you", "4 minutes 32 seconds left"), every icon button has a name, and buttons that show only under the pointer are VoiceOver actions too.
- Increase Contrast makes the faintest text read at 4.5:1 and gives controls a clear edge, in the island and in Settings.
- With Keyboard navigation on, Tab reaches every control in Settings, including **Fit to the notch**.

### Settings
- Settings is a sidebar window like System Settings, with a search field that finds any setting. Each page opens with one plain line on what it does, and technical settings wait under Advanced.
- Appearance and Now Playing show a live drawing of the closed island with a play/pause button.
- Shortcuts are set by pressing them, on a page now called **Keyboard shortcuts**. Islet's two can't share keys, and they pause while a field listens.
- Permissions shows each status on its title line, says what Accessibility lets Islet read (never your typing) and offers **Open Music** (or Spotify) when the app must be open to check. Launch at login says why a change didn't take.
- **Send feedback** (About and the More menu) opens a GitHub issue form with your versions filled in; nothing is sent until you submit it.

### Safer and lighter
- **Opened straight from Downloads**, Islet ran from a temporary copy that moved at every launch, so agents and Launch at login lost track of it. Islet now offers to move itself to Applications (putting the download in the Bin) when it opens and before connecting an agent, and General has **Move to Applications…**.
- A typo in `config.json` no longer resets your settings: Islet keeps what it had, Advanced shows the line with the error, and **Replace…** keeps a copy of the broken file. A file already broken at launch starts from the last one that worked, and unknown keys survive a save.
- A broken shelf or timers file is set aside rather than saved over.
- Feature switches take effect at once, and an activity, HUD or peek that ended just as something else changed no longer sticks on screen.
- **Replace the system volume and brightness display** passes a key to macOS when Islet can't act on it (another display, a closed lid, BetterDisplay, MonitorControl or Lunar, a fixed-volume output, Option with a key), and shows only changes that happened.
- After sleep the island's windows, keys and shortcuts are set up again, and with fast user switching nothing is read from the background session. Granting or removing Accessibility takes effect at once.
- **Hide from screenshots** says that some screen-sharing apps still show the island, and the glass draws solid while it's on, so it can't turn black.
- Music or Spotify switched off in Settings gets no AppleScript at all, and a script can no longer reopen a player that has just quit.
- `islet://` links can't replace Islet's own activities or open anything but https. Script widgets are off until you turn them on, run only files you own and get a short list of variables instead of Islet's whole environment. Meeting links must be on the real host to get a Join button.
- Hooks no longer send a tool's output, so a long one can't make the request fail, and `isletctl` ignores system proxies.
- On macOS 27, measuring the menu bar reads one system window, and only while the island shows. Notification Center and shelf files on network shares are read in the background, so a slow share can't hold up the island.
- Downloads, clipboard history and script widgets stop checking while nothing changes or the screen is locked. In Low Power Mode, looping animations such as the playing indicator keep going at half their usual frame rate instead of stopping, so the indicator never looks stuck.
- Background errors go to the system log under Islet's name, never with what you typed or copied.

### For developers
- The iPhone bridge has its own token (**Copy** and **New token…** in Settings → Advanced, or `isletctl token --lan`), takes only notifications, timers, Focus and simple activities, and limits requests and connections ([docs/API.md](docs/API.md)). Bonjour calls it "Islet", not your Mac's name.
- `GET /v1/state` and `isletctl state` include calendar access and how many events are left today, never their titles. Scripts can't read, change or remove meeting reminders.
- A request refused from its headers alone now gets its answer back while the client is still sending a large body.
- `isletctl media seek` no longer crashes, and takes 90s, 2m, 1:30 or 0 for the start.
- `isletctl hud microphone 0 --muted` and `islet://hud?kind=microphone&value=0&muted=1` show the microphone muted, and `isletctl help` lists `--wait` under `hook`.
- Hook snippets in Advanced wrap at spaces. Local builds use the hardened runtime, with the entitlements macOS needs for calendars, the camera, location and Automation. Islet also builds with the macOS 26 SDK.

### Measured on an M3 Pro MacBook Pro, macOS 27.0.1

The median of three 10-second runs of `make perf` per state, each measured once the change has settled.

| State | CPU | Budget |
| --- | --- | --- |
| Idle | 0.0% | 0.5% |
| Closed, live countdown | 0.3% | 1.5% |
| Closed, static progress | 0.0% | 1.5% |
| Closed, spinner | 0.0% | 1.5% |
| Closed, music playing | 0.5% | 1.5% |
| Open, Now Playing | 0.6% | 3% |
| Idle again | 0.0% | 0.5% |

Memory: about 100 MB. Over two minutes of everyday use on the same Mac, Islet averaged 0.06% CPU. End-to-end suite: 66 passed, 1 skipped (the media test, which never runs while something is playing).

### Known issues
- Tested on macOS 27 only; mirroring Live Activities on macOS 26 is untested.
- How much text a Live Activity exposes varies by app.
- On a very crowded menu bar the icon-only wings can still cover the nearest menu bar item.
- Apple Intelligence features need the on-device model to be downloaded.
- Siri can't call Islet directly yet: Islet is built without full Xcode, and Siri only finds an app's actions through a file Xcode makes. A shortcut can reach Islet through `islet://` links or `isletctl`, and Siri runs shortcuts by name ([docs/SHORTCUTS.md](docs/SHORTCUTS.md)).
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

- When something is showing in the closed island, its sides can cover menu bar icons that sit close to the notch. Mostly fixed in 0.2.0.
- Notification mirroring depends on Notification Center's accessibility tree and hasn't been tested against every app.
- Apple Intelligence features only switch on when the on-device model is downloaded. Otherwise Islet falls back to its own icon rules.
- The build is ad-hoc signed, so macOS will ask you to confirm the first launch.
