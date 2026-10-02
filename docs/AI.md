# AI in Islet

Islet uses AI in two places:

1. **The Ask box**: a question field in the expanded island that streams a short answer from Apple's on-device model, Claude, ChatGPT, or the Claude Code and Codex command-line tools you already use.
2. **Apple Intelligence helpers**: smart icons for activities and one-line summaries of long notifications. These only ever use the on-device model.

Nothing goes over the network until you ask a cloud provider a question, save an API key or choose **Check for new models** in a model menu. Settings for both live in **Settings → Ask & AI**.

---

## The Ask box

Open it in any of three ways:

- Press the Ask shortcut, **⌃⌥A** by default, from any app (see [Keyboard shortcut](#keyboard-shortcut)).
- Open the island and click **Ask**, the disc on the right of the page switcher under it.
- Open an `islet://ask` link (see [below](#islet-ask)).

| Action | How |
|---|---|
| Type a question | Click the field. The island takes the keyboard only while you use it |
| Send | Return, or the arrow button |
| Stop an answer | Esc, or the stop button |
| Hand the keyboard back | Esc, which also closes the island when nothing is streaming, or click in another app |
| Copy the answer | The copy button next to the field |
| Change provider | The chip on the left. It's the same setting as Settings → Ask & AI → Answer with, so a change in either shows in both and is kept |
| Start a new conversation | The pencil button (shown after an answer when follow-ups are on) |

What to expect:

- **Answers are short.** Every provider is asked for at most 120 words of plain text, because the panel is small. Ask for more and you get more; the answer scrolls. Bold, italics, code and links are rendered, and links only open web pages.
- **A cloud glyph** on the chip means the question leaves your Mac.
- **Closing the island cancels** a question that is still being answered.
- **Follow-ups** are off by default. With *Keep follow-ups in memory* on, up to 6 earlier turns (three questions and their answers) go with your next question, so you can say "and in Python?". They go to whichever provider answers next. They are kept in memory only: the pencil button, or quitting Islet, forgets them.
- **Nothing is saved.** No history on disk, and no question or answer in any log.
- A question is cut to 4,000 characters.
- The island shows the first 8 KB of an answer; Copy gives you all of it (up to 256 KB).
- Islet stops waiting for an answer that isn't complete within 2 minutes, whatever the provider.
- The answer redraws at most 20 times a second, and nothing runs while the island is closed.

### Keyboard shortcut

The Ask shortcut is `ctrl+option+a` (⌃⌥A) by default. From any app, it opens the island on the Ask box, pinned, with the field focused. Press it again, or Esc in the field, to close it. Change it in Settings → Keyboard shortcuts or on the Ask & AI page: click the shortcut and press the new keys, or press Delete to turn it off.

Write it as modifiers and a key joined by `+`. Modifiers are `ctrl`, `option` (or `opt`, `alt`), `shift` and `cmd`, or the symbols ⌃⌥⇧⌘. The key is a letter, digit or punctuation key, `space`, `return`, `tab`, `escape`, an arrow (`up`, `down`, `left`, `right`) or `f1` to `f12`. It needs a modifier other than Shift unless the key is a function key. Text Islet can't read leaves the shortcut off.

### <a name="islet-ask"></a>`islet://ask`

```text
islet://ask
islet://ask?q=What%20is%20a%20monad
islet://ask?q=Explain%20this%20error&provider=claude
```

It opens the Ask box like the shortcut does, with the question filled in. **It never sends.** You read the question and press Return.

- `q` (or `text`) is the question, cut to 4,000 characters.
- `provider` picks the provider until the island closes, without changing the one in Settings: `on-device`, `claude` (or `anthropic`), `chatgpt` (or `openai`), `claude-code` or `codex`. An unknown name makes the link do nothing.

Shortcuts, Raycast or Alfred can open `islet://ask?q=…` to pass in text you typed there.

---

## Providers

| Provider | Needs | Runs where | Cost |
|---|---|---|---|
| **On-device** (default) | macOS 26 or later with Apple Intelligence on and downloaded | On your Mac | Free |
| **Claude** | An Anthropic API key | `api.anthropic.com` | Billed to your Anthropic account per token |
| **ChatGPT** | An OpenAI API key | `api.openai.com` | Billed to your OpenAI account per token |
| **Claude Code** | The `claude` CLI, signed in | The CLI calls Anthropic | Counts towards the plan the CLI is signed in with |
| **Codex** | The `codex` CLI, signed in | The CLI calls OpenAI | Counts towards the plan the CLI is signed in with |

If the provider you picked can't answer (no key, CLI not found, Apple Intelligence not ready), the Ask box says why and the chip's menu lets you pick another. Islet never switches you to a cloud provider on its own.

### Claude (Anthropic API)

- `POST https://api.anthropic.com/v1/messages`, streamed, with headers `x-api-key`, `anthropic-version: 2023-06-01` and `anthropic-beta: server-side-fallback-2026-07-01`.
- Model: `claude-opus-5-5` by default; `claude-sonnet-5-5` and `claude-haiku-4-5` are offered too, and **Check for new models** in the model menu loads the Claude models your key can use (`GET /v1/models`). Settings names models as people say them ("Claude Opus 5.5", "GPT-6 Astra"), with the id in the menu's help.
- `max_tokens` 4096 and `output_config.effort` from Settings (Low by default). Thinking can't be turned off on Opus 5.5, so effort is what keeps it short. Islet doesn't show the thinking.
- `fallbacks: "default"` is on. If Claude declines a request, Anthropic re-runs it on its recommended fallback model and the answer continues in the same stream. If the answer still ends in a refusal, the Ask box says the model declined and drops any partial text.
- Errors: a rejected key (401) asks you to enter it again; a rate limit (429) says how many seconds to wait when the API sends `retry-after`; an unknown model (404) asks you to pick another; an overloaded API (529) is retried once after about a second. A request fails if the API sends nothing for 30 seconds.

### ChatGPT (OpenAI API)

- `POST https://api.openai.com/v1/responses`, streamed, with `store: false`, which asks OpenAI not to store the response (by default it would). Follow-ups re-send the earlier turns rather than chaining stored responses.
- Model: `gpt-6-astra` by default; `gpt-6.1-sol` and `gpt-6-luna` are offered too. **Check for new models** loads the chat models your key can use.
- `reasoning.effort` from Settings and `max_output_tokens` 2048. If a model doesn't take a reasoning effort, Islet asks again without it.
- Errors are handled as for Claude. An account out of credit (429 `insufficient_quota`) says so.

### Claude Code and Codex

Islet looks for the binaries in `~/.local/bin`, `/opt/homebrew/bin` and `/usr/local/bin` (and `~/.claude/local` for Claude Code). If a tool isn't in any of them, the Ask box says it isn't installed, and Settings → Advanced → Diagnostics shows where each one was found or where Islet looked. Islet runs them like this:

```bash
claude -p "<prompt>" --output-format stream-json --verbose --include-partial-messages \
       --tools "" --max-turns 1 --no-session-persistence --settings '{"disableAllHooks": true}' \
       [--model <model>]

codex exec --json --ephemeral --skip-git-repo-check --sandbox read-only [--model <model>] "<prompt>"
```

`<prompt>` is a short instruction (answer briefly, in plain text, without tools or reading files), then any earlier turns, then your question.

- **One turn, nothing saved.** Claude Code gets no tools at all and no hooks run (so Islet's own agent hooks don't fire for your question). Codex runs in its read-only sandbox and doesn't save the session.
- **An empty folder** as the working directory (`~/Library/Application Support/Islet/ask`), so no project's settings, `CLAUDE.md` or MCP config load. The CLI's user-level config in your home folder still applies.
- **A minimal environment**: `HOME`, `USER`, `LOGNAME`, `TMPDIR`, `LANG`, `PATH`, `TERM=dumb` and `NO_COLOR=1`. No API keys and no Islet token are passed, so Claude Code uses its own login rather than an `ANTHROPIC_API_KEY`, which would switch it to API billing.
- **Arguments, not a shell**: the prompt is passed as one argument and never interpreted by a shell. Standard input is `/dev/null`.
- **Limits**: output is capped at 256 KB. Stop, or closing the island, sends SIGTERM, then SIGKILL after 2 seconds.
- **Model**: blank uses the CLI's default. You can set one per CLI in Settings → Ask & AI (`sonnet`, `opus`, `gpt-6-luna`…). Names with spaces or a leading `-` are refused, so the setting can't add options to the command.

If a CLI isn't signed in, the Ask box says so; run `claude` or `codex` once in Terminal to sign in. If a CLI is too old for one of the options above, the Ask box shows the one it rejected and asks you to update it.

---

## API keys

- Create a key at platform.claude.com or platform.openai.com and paste it into Settings → Ask & AI.
- Islet checks its shape (`sk-ant-…` for Anthropic, `sk-…` for OpenAI), then calls `GET /v1/models` once to make sure it works, and only then stores it.
- Keys are stored in your **login keychain** as generic passwords: service `dev.islet.Islet.ai`, accounts `anthropic` and `openai`, readable only while your Mac is unlocked. By default only the app that created the item can read it without asking.
- Afterwards Settings shows only the key's last four characters. **Replace** swaps it for a new one; **Remove** deletes the Keychain item.
- A key is never written to `config.json`, never logged, never put in a URL, and never passed to a child process. Requests only go to `api.anthropic.com` and `api.openai.com` over HTTPS, redirects are refused (so the key header can't follow one), and the connection keeps no cache, cookies or credentials.
- Builds signed with a Developer ID add a code-identity check. Ad-hoc builds rely on the login keychain alone.

To look at or delete the items yourself:

```bash
security find-generic-password -s dev.islet.Islet.ai -a anthropic
security delete-generic-password -s dev.islet.Islet.ai -a anthropic
```

---

## What leaves your Mac

| When | What is sent | To |
|---|---|---|
| Never, with the on-device model | Nothing | |
| You press Return with Claude or ChatGPT | Your question, earlier turns if follow-ups are on (including ones the on-device model answered), and a short instruction to keep the answer brief | Anthropic or OpenAI, with your key |
| You press Return with Claude Code or Codex | The same, as the CLI's prompt, plus whatever the CLI adds itself (such as its own system prompt) | The CLI's vendor, with your login |
| You save a key, or choose **Check for new models** | A request for the model list | The key's provider |

- Nothing is sent at launch or in the background.
- Notification, calendar and clipboard text is never sent to a cloud provider. Smart icons and notification summaries use the on-device model or nothing.
- The shortcut only opens the Ask box, and `islet://ask` only fills in the question. The local HTTP API and `isletctl` have no way to ask a question, so nothing outside the Ask box can spend money on your keys.

---

## Costs

Claude and ChatGPT answers are billed per token by the provider, at the prices on its pricing page. Islet doesn't know the prices. What an answer costs depends on:

- **The model** you pick.
- **Effort**: higher effort means more thinking, which counts as output. Low costs least.
- **Follow-ups**: earlier turns are sent again as input with every new question.
- **Answer length**, capped at 4096 output tokens for Claude and 2048 for ChatGPT, thinking included.

The footer under each answer shows the model, the output tokens when the provider reports them, and for Claude Code the cost the CLI reports. It also says when an answer was cut short at the length limit. Claude Code and Codex answers count towards the plan the CLI is signed in with.

---

## Apple Intelligence

Settings → Ask & AI → Apple Intelligence says in a few words whether the on-device model is ready, and Settings → Advanced → Diagnostics shows the exact status:

| Status | What Islet does |
|---|---|
| Ready (on-device) | On-device answers in the Ask box; smart icons and notification summaries when *Smart icons and short summaries* is on |
| Unavailable: deviceNotEligible | This Mac can't run Apple Intelligence. Icons come from Islet's keyword rules, notifications aren't summarised, and the Ask box offers the other providers |
| Unavailable: appleIntelligenceNotEnabled | Same; turn it on in System Settings → Apple Intelligence & Siri |
| Unavailable: modelNotReady | Same, until the model finishes downloading |
| Needs macOS 26 or later | On macOS 14 or 15 there is no on-device model; the other providers work |

- **Smart icons**: when an activity arrives with no icon and the keyword rules can't place it, the model picks one of Islet's icon categories from the activity's title and source, once per activity. *Smart icons and colours for activities* (Settings → Appearance) must be on too.
- **Summaries**: when a mirrored notification's text is longer than 90 characters, the model is asked to condense it to at most 12 words. The result, cut to 90 characters, replaces the notification's subtitle.

The on-device model has a small context window, so on-device follow-ups keep only the last two earlier turns.

---

## `config.json`

The Ask settings are stored under `"ask"` in `~/.config/islet/config.json` (keys are not). `aiAssist` (the *Smart icons and short summaries* switch under Apple Intelligence) and `askHotkey` (the Ask shortcut, `""` for off) are top level:

```json
{
  "aiAssist": true,
  "askHotkey": "ctrl+option+a",
  "ask": {
    "provider": "onDevice",
    "models": { "anthropic": "claude-sonnet-5-5", "claudeCode": "sonnet" },
    "effort": "low",
    "followUps": false
  }
}
```

| Key | Values |
|---|---|
| `provider` | `onDevice`, `anthropic`, `openai`, `claudeCode`, `codex` |
| `models` | Model id per provider; a missing entry uses the default |
| `effort` | `low`, `medium`, `high` |
| `followUps` | `true` keeps up to 6 turns in memory |

A missing or invalid value falls back to its default, and a model id that looks like a key or an option is dropped. Anything else under `"ask"`, such as a key pasted in by mistake, is dropped the next time Islet saves the file.
