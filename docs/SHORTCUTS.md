# Siri and Shortcuts

Islet doesn't have Siri commands of its own yet. You can still use Siri with it: build a shortcut in the Shortcuts app, give it a name, and say "Hey Siri, *name*". Siri on the Mac runs any shortcut by its name, and the shortcut talks to Islet through the `islet://` URL scheme or `isletctl`.

This page has step-by-step recipes for timers, the Pomodoro, and asking Apple Intelligence a question with the answer shown in the notch.

---

## Why there are no built-in Siri commands yet

Apps offer actions to Siri, Spotlight and Shortcuts through App Intents. Writing them is ordinary Swift, and Islet's build tools compile that code. But the system only finds an app's intents through a metadata file inside the app (`Metadata.appintents`), and the tool that writes that file ships with Xcode, not with the command-line tools Islet is built with. Without the file, the intents exist in the app but never appear in Shortcuts or Siri.

The fix is to run that one step on a build machine that has Xcode and ship the file with each release. That isn't done yet, so there is no date for built-in commands. Until then, the recipes below do the same job, and they keep working afterwards.

---

## Before you start

- Islet must be running. The `islet://` links need no setup.
- To talk to a shortcut, turn Siri on in System Settings.
- For the recipes that use **Run Shell Script**, open Shortcuts → Settings → Advanced and tick **Allow Running Scripts**. Use the full path to the command, because shortcuts don't read your shell profile: `/Applications/Islet.app/Contents/MacOS/isletctl`.

To make a shortcut: open Shortcuts, choose File → New Shortcut, click the name at the top to rename it, then search for each action in the panel on the right and drag it in.

---

## Timers

### "Hey Siri, notch timer"

Asks how long, then starts a timer. You can answer with a length and a name in one go.

1. New shortcut, named **Notch Timer**.
2. Add **Ask for Input**. Input type: Text. Prompt: *How long?*
3. Add **URL Encode**, set to Encode, with *Provided Input* as its input.
4. Add **Open URLs**. Type `islet://timer?in=` and then insert the *URL Encoded Text* variable after the `=`.

Say "Hey Siri, notch timer", then answer:

| You say | Timer |
|---|---|
| "20 minutes" | 20:00 |
| "tea 4 minutes" | Tea, 4:00 |
| "in 20 minutes to take the pizza out" | Take the pizza out, 20:00 |
| "half an hour" | 30:00 |
| "an hour and a half" | 1:30:00 |
| "at 6 pm" | until the next 18:00 |
| "25" | 25:00 (a number on its own means minutes) |

The words that aren't part of the length become the timer's name. Clock times always mean the next time that clock shows, so "at 6 pm" at 19:00 means tomorrow. Timers run for up to 24 hours.

### A fixed timer

For something you time often, skip the question.

1. New shortcut, named **Tea Timer**.
2. Add **Open URLs** with `islet://timer?in=4m&title=Tea`.

Say "Hey Siri, tea timer".

### Stop, snooze, pause

Each of these is one **Open URLs** action. Without an `id`, the command goes to the timer that is ringing, or else the one started most recently.

| Shortcut name (suggestion) | URL |
|---|---|
| Stop Notch Timer | `islet://timer?action=stop` |
| Snooze Notch Timer | `islet://timer?action=snooze` (5 more minutes) |
| Pause Notch Timer | `islet://timer?action=pause` |
| Resume Notch Timer | `islet://timer?action=resume` |
| Add a Minute | `islet://timer?action=add&in=1m` |

### Pomodoro

1. New shortcut, named **Pomodoro**.
2. Add **Open URLs** with `islet://pomodoro?action=toggle`.

"Hey Siri, Pomodoro" starts 25 minutes of focus, and saying it again stops it. Islet moves on to a 5-minute break, then the next round, with a 15-minute break after every fourth. Change the lengths in Settings → Modules → Timers.

---

## Ask Apple Intelligence, answer in the notch

Shortcuts' **Use Model** action (macOS 26 and later) sends a prompt to the on-device model, to Private Cloud Compute, or to ChatGPT if you have turned that on. Islet only shows the answer; it has no part in choosing the model or sending the question.

1. New shortcut, named **Ask the Notch**.
2. Add **Ask for Input**. Input type: Text. Prompt: *What's your question?*
3. Add **Use Model**. Pick a model, and put *Provided Input* in the prompt. Add something like "Answer in one short sentence." so the answer fits.
4. Add **URL Encode**, set to Encode, with the model's *Response* as its input.
5. Add **Open URLs** with `islet://notify?icon=sf:sparkles&ttl=20&title=` and then insert the *URL Encoded Text* variable after the last `=`.

Say "Hey Siri, ask the notch". The answer pops out of the notch, then stays on the island's Home tab for 20 seconds. The island has room for about one short sentence, so for longer answers add **Show Result** as well.

**Use Model** needs Apple Intelligence turned on, and the on-device model needs to have finished downloading. If the model you picked isn't available, the shortcut stops at that step and nothing reaches Islet.

---

## Using `isletctl` instead of links

**Run Shell Script** reports errors back to Shortcuts, which an `islet://` link can't do: if Islet can't read the length, Shortcuts shows the reason.

1. New shortcut, named **Notch Timer**.
2. Add **Ask for Input** as above.
3. Add **Run Shell Script**. Shell: zsh. Input: *Provided Input*. Pass input: as arguments. Script:

   ```sh
   /Applications/Islet.app/Contents/MacOS/isletctl timer "$*"
   ```

Other commands work the same way:

```sh
/Applications/Islet.app/Contents/MacOS/isletctl timer stop
/Applications/Islet.app/Contents/MacOS/isletctl timer add 5m
/Applications/Islet.app/Contents/MacOS/isletctl pomodoro toggle
```

`isletctl timer` prints the new timer's id (`timer-1`, `timer-2`, …), which `pause`, `resume`, `stop` and `add` accept. A bare number means seconds here (`isletctl timer 300`), as it always has; write `5m` for minutes.

---

## Tips

- **Your own phrases.** The shortcut's name is the phrase. Rename it to whatever you like saying.
- **A key instead of your voice.** In a shortcut's details, **Add Keyboard Shortcut** runs it from anywhere.
- **From the iPhone.** Shortcuts sync, but `islet://` links only work on the Mac. On the iPhone, use **Get Contents of URL** against Islet's local-network bridge: POST to `/v1/timer` with `{"in": "20m", "title": "Pizza"}`. See [iPhone → Mac](INTEGRATIONS.md#iphone).
- **What a link can do.** `islet://` links can start and stop timers, show notifications, open or close the island and control playback. They can't approve anything, spend money or read anything back.
