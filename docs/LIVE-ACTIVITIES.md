# iPhone Live Activities in the island

On macOS 26 and later, the Mac shows your iPhone's Live Activities (a ride on its way, a delivery, a game score, a flight) in the menu bar. It shows some of its own too, such as a running shortcut. Islet puts them in the island, next to everything else it shows, with the app's symbol, colour and layout when it knows the app.

## Turning it on

1. Give Islet Accessibility access: press *Allow…* in *Settings → Live Activities* (it shows while access is missing), or use *System Settings → Privacy & Security → Accessibility*. If nothing appears after you grant it, quit and reopen Islet.
2. Leave *Show Live Activities* on, at the top of the same page.
3. Make sure macOS shows them. Your iPhone and Mac need the same Apple Account, iPhone Mirroring set up, and *Allow Live Activities from iPhone* on in *System Settings → Notifications*; Apple's guide is [support.apple.com/120684](https://support.apple.com/en-us/120684). If that last setting is off, Islet's Live Activities page says so, and only the Mac's own activities appear.

Nothing else is needed, and nothing is installed on the iPhone.

## How it works

There's no API for this. ActivityKit is unavailable on macOS, so Islet reads what the menu bar draws, through Accessibility:

- It reads only MenuBarAgent, the part of macOS that draws the system menu bar items, and the processes that render Live Activity content. Other apps' menu bar items are noted by position and bundle ID; their contents are never read.
- It recognises an activity mainly by MenuBarAgent's own label for it ("Live Activity", in any language MenuBarAgent is translated into), its *End Live Activity* menu command or the process that drew it. It ignores the built-in items: everything with a `com.apple.menuextra` identifier (battery, Wi-Fi, Now Playing, the Clock app's timer) and the camera and microphone controls.
- It also finds activities that macOS has collapsed into the menu bar's overflow because there's no room beside the notch. On a MacBook with a notch that happens often, and the island is then the only place you see them.
- It wakes when macOS reports that an activity changed. While the menu bar holds at least one activity, it also rescans every 15 seconds in case a change wasn't announced. With none, nothing polls.
- When an activity's text ends in a running time ("4:59", "1:02:03"), Islet works out from two readings whether it counts down or up and animates it itself, so the menu bar isn't read every second. A time that doesn't change, such as a boarding time, stays as text.
- Clicking the activity in the island clicks the original, which opens what the menu bar would: Apple's expanded view, or the app through iPhone Mirroring. If the activity is in the overflow, Islet opens the overflow first. Nothing outside Islet can trigger that click: there's no URL or API for it.

## Keeping the menu bar clean

**Hide the menu bar's own** doesn't take the pill away. macOS offers no action for that, and Islet reads the pill to mirror it, so the pill stays and Islet covers it: one borderless black panel per visible pill, exactly over it, in the menu bar row and nowhere else. Nothing is drawn inside, and clicks pass through to macOS's pill underneath, so Apple's own view still opens from the menu bar.

It covers the display that carries the menu bar, the one Islet reads, and only the Live Activity pills, never another menu bar item. A cover goes the moment it would be wrong: the setting off, **Show Live Activities** off, Accessibility gone, the activity gone, the pill collapsed behind the notch (macOS doesn't draw it there), this login session in the background, an app in full screen over that display, or the island hidden there by a full screen app or an app rule. It follows a pill that moves or changes width, on the same events the mirror reads on, and nothing polls.

## How activities look

Islet looks up the app name in its catalogue of apps with Live Activities, the same one the API uses for templates (see [Templates](API.md#templates)).

- A match gives the activity that app's symbol, brand colour and template: `eta` for Uber, `flight` for Flighty, `score` for Apple Sports. A brand colour too dark to read on the black island is lightened, keeping its hue (black and near-greys become white).
- Without a match, the symbol and colour come from keywords in the text (the rules smart icons use), or else a generic symbol in white. The template is then `timer` when Islet has worked out a running clock, and the generic `progress` otherwise.
- The last part of the text, when it's 8 characters or fewer ("4 min", "2-1"), becomes the activity's `trailing` value for the right-hand wing. When it's longer, the wing is cleared rather than keeping an older value, and when the text is gone the subtitle goes too. While Islet animates a clock, the wing shows the time from that instead, and once the text shows no time the clock stops.
- A new activity gets a sneak peek. Later changes to it don't.

## Settings

| Setting | `config.json` key | Default | What it does |
|---|---|---|---|
| Show Live Activities (Settings → Live Activities) | `mirrorMenuBarActivities` | On (needs Accessibility) | Mirror them into the island. |
| Only when the notch hides them (Settings → Live Activities) | `mirrorOnlyHiddenActivities` | Off | Mirror only the activities macOS has collapsed into the overflow, so nothing shows twice. |
| Hide the menu bar's own (Settings → Live Activities) | `hideMenuBarActivities` | On | Cover each Live Activity macOS draws in the menu bar with black, so it shows in the island only. Mirrors every activity, visible or not, and dims the setting above. |
| Let scripts read Live Activities (Settings → Advanced → Local API) | `shareMirroredActivities` | Off | Include them in `GET /v1/activities` and `GET /v1/state`. They often hold addresses, names and scores, so they're left out unless you allow it. The setting also shows their text in `isletctl debug menubar`. Either way, scripts and links can't change or remove them. |

The middle two are dimmed while the first is off, and **Only when the notch hides them** is dimmed while **Hide the menu bar's own** is on: a covered activity has to be in the island, so covering mirrors them all. Shared activities have a `source` starting with `live-activity`, one per app (for example `"live-activity:uber"`), and an `id` starting with `live-`.

The text Islet reads stays in memory. It isn't written to disk or logs. `GET /v1/debug/menubar` (what `isletctl debug menubar` uses) needs the API token and returns the menu bar's layout even with mirroring off, but leaves out the text of Live Activities unless the sharing setting is on.

## Limits

- **Built and tested on macOS 27.** macOS 26 draws the menu bar differently and hasn't been tested.
- **How much text an activity exposes varies by app.** Some expose their full compact text, some only a label. When Islet can't find an app name, the island titles it "Live Activity"; clicking still opens it.
- **iPhone timers and stopwatches don't reach the Mac.** macOS doesn't send them, so Islet can't show them.
- **Hiding an activity** (*Hide Live Activity*, from macOS 27.2) may also hide it from Islet.
- **Hide the menu bar's own needs an island on the display with the menu bar.** With *Where it shows* set so there is none there, nothing is covered, rather than leaving black over a menu bar Islet isn't on.
- **It stops in full screen.** With *In full screen* set to hide the island, Islet shows the activity nowhere, so it leaves macOS's pill alone: pull the menu bar down over a full screen app and the pills are there as usual.
- **It does nothing while the menu bar hides itself** (*Automatically hide and show the menu bar* in System Settings). The menu bar isn't there to cover, and macOS brings it back without telling Islet.

## Checking what Islet sees

```bash
isletctl debug menubar            # what Islet sees now, as JSON
isletctl debug menubar --watch    # print each change until Ctrl-C
```

Each item shows its position and width, whether it's hidden in the overflow, what Islet thinks it is (`liveActivity`, `systemItem`, `avControls`, `overflowButton`, `thirdParty` or `unknown`) and its text. Other apps' items appear in the JSON with only their bundle ID, position and width; `--watch` leaves them out. An empty list means Islet can't read the menu bar: Accessibility access is missing, or macOS builds the menu bar in a way Islet doesn't read. The text of Live Activities, and of items Islet can't place, is only shown while **Let scripts read Live Activities** (Settings → Advanced → Local API) is on, so turn it on while you capture output for an issue.

To try it without an iPhone, make a shortcut with one action, *Wait* 30 seconds, and run it from the Shortcuts menu bar item. From the iPhone, try a food delivery, a ride, a flight in Flighty or a live game in Apple Sports. If one doesn't look right, run `--watch` while it's live and include the output in an issue, after checking it for addresses and names you'd rather not post.
