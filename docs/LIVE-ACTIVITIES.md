# iPhone Live Activities in the island

On macOS 26 and later, the Mac shows your iPhone's Live Activities (a ride on its way, a delivery, a game score, a flight) in the menu bar. It shows some of its own too, such as a running shortcut. Islet puts them in the island, next to everything else it shows, with the app's icon and colour.

## Turning it on

1. Give Islet Accessibility access: *Settings → General → Allow…*, or *System Settings → Privacy & Security → Accessibility*. Islet never asks for it on its own.
2. Leave *Show Live Activities from the menu bar* on (*Settings → Modules → Live Activities*).
3. Make sure macOS shows them. Your iPhone and Mac need the same Apple Account and iPhone Mirroring set up; Apple's guide is [support.apple.com/120684](https://support.apple.com/en-us/120684).

Nothing else is needed, and nothing is installed on the iPhone.

## How it works

There's no API for this. ActivityKit is unavailable on macOS, so Islet reads what the menu bar draws, through Accessibility:

- It looks only at MenuBarAgent, the part of macOS that draws the system menu bar items, and at the process that renders Live Activities. It never reads other apps' menu bar items.
- It recognises an activity by the label macOS gives it ("Live Activity", in whichever of the 41 languages your Mac uses), and ignores the built-in items (battery, Wi-Fi, Now Playing, the Clock timer, camera and microphone controls).
- It also finds activities that macOS has collapsed into the menu bar's overflow because there's no room beside the notch. On a MacBook with a notch that happens often, and the island is then the only place you see them.
- It wakes when macOS reports an activity changing, not on a timer. While at least one activity is showing it also checks every 15 seconds in case a change wasn't announced.
- A countdown or stopwatch shown by an activity is animated by Islet itself once it has seen two readings, so the menu bar isn't read every second.
- Clicking the activity in the island clicks the original, which opens Apple's expanded view (and from there the app on your iPhone, through iPhone Mirroring). Nothing else can trigger that click: there's no URL or API for it.

## Settings

| Setting | Default | What it does |
|---|---|---|
| Show Live Activities from the menu bar | On (needs Accessibility) | Mirror them into the island. |
| Only when hidden by the notch | Off | Mirror only the activities macOS has collapsed into the overflow, so nothing shows twice. |
| Share mirrored activities with scripts | Off | Include them in `GET /v1/activities` and `/v1/state`. They often hold addresses, names and scores, so they're left out unless you allow it. |

The text Islet reads stays in memory. It isn't written to disk or logs.

## Limits

- **macOS 27 is what it's built and tested on.** macOS 26 draws the menu bar differently and hasn't been tested.
- **How much text an activity exposes varies by app.** Some expose their full compact text, some only a label. When there's no text, the island shows "Live Activity" with the app's icon where it can tell which app it is, and clicking still opens it.
- **iPhone timers and stopwatches don't reach the Mac**; that's macOS, not Islet.
- **Hiding an activity in macOS 27.2** ("Hide Live Activity") may also hide it from Islet.

## Checking what Islet sees

```bash
isletctl debug menubar            # what Islet sees now, as JSON
isletctl debug menubar --watch    # print each change until Ctrl-C
```

Each item shows its position, whether it's hidden in the overflow, what Islet thinks it is (`liveActivity`, `systemItem`, `overflowButton`, `thirdParty`) and its text. Other apps' items are listed by position only.

To try it without an iPhone: make a shortcut with one action, *Wait* 30 seconds, and run it from the Shortcuts menu bar item; or start a timer in the Mac's Clock app. From the iPhone, a food delivery, a ride, a flight in Flighty or a live game in Apple Sports all show up. If one doesn't look right, run `--watch` while it's live and include the output in an issue.
