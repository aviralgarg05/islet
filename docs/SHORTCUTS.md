# Siri and Shortcuts

Islet doesn't have Siri commands of its own yet. You can still use Siri with it: build a shortcut in the Shortcuts app, give it a name, and say "Hey Siri, *name*". Siri on the Mac runs any shortcut by its name, and the shortcut talks to Islet through the `islet://` URL scheme or `isletctl`.

This page has step-by-step recipes for timers, the Pomodoro, the microphone's mute display, and asking Apple Intelligence a question with the answer shown in the notch.

---

## Why there are no built-in Siri commands yet

Apps offer actions to Siri, Spotlight and Shortcuts through App Intents. Writing them is ordinary Swift, and Islet's build tools compile that code. But the system only finds an app's intents through a metadata file inside the app (`Metadata.appintents`), and the tool that writes that file ships with Xcode, not with the command-line tools Islet is built with. Without the file, the intents exist in the app but never appear in Shortcuts or Siri.

The fix is to run that one step on a build machine that has Xcode and ship the file with each release. That isn't done yet, so there is no date for built-in commands. Until then, the recipes below do the same job, and they keep working afterwards.

---

## Before you start

- Islet must be running. The `islet://` links need no setup.
- To talk to a shortcut, turn Siri on in System Settings.
- For the recipes that use **Run Shell Script**, open Shortcuts → Settings → Advanced and tick **Allow Running Scripts**. Use the full path to the command, because shortcuts don't read your shell profile: `/Applications/Islet.app/Contents/MacOS/isletctl` (change the start if Islet isn't in Applications).

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
| "remind me to call mum at 6 pm" | Call mum, until the next 18:00 |
| "25" | 25:00 (a number on its own means minutes) |

The words that aren't part of the length become the timer's name, minus openers such as "set a timer" and "remind me to". Clock times always mean the next time that clock shows, so "at 6 pm" said at 19:00 means 18:00 tomorrow, and "at 6" means whichever of 6:00 and 18:00 comes first. Timers run for up to 24 hours. If Islet can't find a length in the answer, the link does nothing; the [`isletctl` version](#using-isletctl-instead-of-links) tells you why.

### A fixed timer

For something you time often, skip the question.

1. New shortcut, named **Tea Timer**.
2. Add **Open URLs** with `islet://timer?in=4m&title=Tea`.

Say "Hey Siri, tea timer".

### Stop, snooze, pause

A timer that ends rings in the island with **Stop**, **Snooze 5 min** and **Restart** buttons. These shortcuts do the same by voice, and each is one **Open URLs** action. Without an `id`, the command goes to the timer that is ringing, or else the one started most recently (which can be the Pomodoro).

| Shortcut name (suggestion) | URL |
|---|---|
| Stop Notch Timer | `islet://timer?action=stop` |
| Snooze Notch Timer | `islet://timer?action=snooze` (5 more minutes; add `&in=10m` for another length) |
| Pause Notch Timer | `islet://timer?action=pause` |
| Resume Notch Timer | `islet://timer?action=resume` |
| Restart Notch Timer | `islet://timer?action=restart` (from its full length) |
| Add a Minute | `islet://timer?action=add&in=1m` |

To aim at one timer, add `&id=` with its id (`timer-1`), its number (`1`) or its title (`Tea`), for example `islet://timer?action=stop&id=Tea`. A title only works while exactly one timer has it.

### Pomodoro

1. New shortcut, named **Pomodoro**.
2. Add **Open URLs** with `islet://pomodoro?action=toggle`.

"Hey Siri, Pomodoro" starts 25 minutes of focus, and saying it again stops it. When the focus ends, Islet moves on to a 5-minute break and then the next round; every fourth break is 15 minutes. Those are the defaults: change them in Settings → Timers. For separate start and stop shortcuts, use `action=start` and `action=stop`.

---

## Show the microphone muted

Islet doesn't mute the microphone itself, but a shortcut that does can show it beside the notch.

1. New shortcut, named **Mute Microphone**.
2. Add **Run Shell Script** with `osascript -e 'set volume input volume 0'`.
3. Add **Open URLs** with `islet://hud?kind=microphone&value=0&muted=1`.

For the opposite shortcut, set the input volume back (`set volume input volume 75`) and open `islet://hud?kind=microphone&value=0.75`. In **Run Shell Script** the same is `/Applications/Islet.app/Contents/MacOS/isletctl hud microphone 0 --muted`. The display follows the **Microphone** switch in Islet's Settings → Notifications & Levels.

---

## Ask Apple Intelligence, answer in the notch

Shortcuts' **Use Model** action (macOS 26 and later) sends a prompt to the on-device model, to Private Cloud Compute, or to ChatGPT if you have turned that on. Islet only shows the answer; it has no part in choosing the model or sending the question.

1. New shortcut, named **Ask the Notch**.
2. Add **Ask for Input**. Input type: Text. Prompt: *What's your question?*
3. Add **Use Model**. Pick a model, and put *Provided Input* in the prompt. Add something like "Answer in one short sentence." so the answer fits.
4. Add **URL Encode**, set to Encode, with the model's *Response* as its input.
5. Add **Open URLs** with `islet://notify?icon=sf:sparkles&ttl=20&title=` and then insert the *URL Encoded Text* variable after the last `=`.

Say "Hey Siri, ask the notch". The answer pops out of the notch, then stays on the island's Home tab until 20 seconds after it arrived (`ttl=20`). The island has room for about one short sentence, so for longer answers add **Show Result** as well.

**Use Model** needs Apple Intelligence turned on, and the on-device model needs to have finished downloading. If the model you picked isn't available, the shortcut stops at that step and nothing reaches Islet.

To use Islet's own Ask box instead, skip **Use Model**, URL-encode *Provided Input*, and open `islet://ask?provider=on-device&q=` with the *URL Encoded Text* after the last `=`. The island opens on the Ask box with the question filled in, and you press Return to send it: a link never sends a question by itself. `provider` also takes `claude`, `chatgpt`, `claude-code` and `codex`; leave it out to keep the one the Ask box is using. See [AI.md](AI.md#islet-ask).

---

## Using `isletctl` instead of links

**Run Shell Script** reports errors back to Shortcuts, which an `islet://` link can't do: if Islet can't read the length, or isn't running, Shortcuts shows the reason.

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

`isletctl timer` prints the new timer's id (`timer-1`, `timer-2`, …). `pause`, `resume`, `stop`, `restart`, `snooze` and `add` take that id, its number or the timer's title, and without one they act on the ringing or newest timer. A bare number means seconds here (`isletctl timer 300`), not minutes as in links: write `5m`, or answer "25 minutes" rather than "25".

---

## Tips

- **Run them from the island.** Turn on **Run your shortcuts** in Settings → Tools, and a Shortcuts page appears under More: type part of a name, then click a shortcut or press Return. The Ask box offers a shortcut whose name matches what you type, too.
- **Your own phrases.** The shortcut's name is the phrase. Rename it to whatever you like saying.
- **A key instead of your voice.** In a shortcut's details, **Add Keyboard Shortcut** runs it from anywhere.
- **From the iPhone.** Shortcuts sync, but `islet://` links only work on the Mac. Turn on the iPhone bridge in Islet's Settings → Advanced on the Mac, then on the iPhone use **Get Contents of URL** to POST `{"in": "20m", "title": "Pizza"}` to `/v1/timer` with the bridge's own token (Settings → Advanced → iPhone bridge, or `isletctl token --lan`); the local API's token doesn't work there. See [iPhone → Mac](INTEGRATIONS.md#iphone).
- **What a link can do.** `islet://` links can start and control timers and the Pomodoro, show notifications and activities, open or close the island, control playback, keep the Mac awake and fill in the Ask box. They can't approve anything, send a question, spend money or read anything back. Activities made by links get ids starting with `url-` (the prefix is added for you), `islet://dismiss` only removes those, and any web address attached to an activity must be https. The full list is in [API.md](API.md#islet-url-scheme).
