# AI in Islet

Islet uses AI in two places:

1. **The Ask box**: a question field in the expanded island that streams a short answer from Apple's on-device model, Claude, ChatGPT, or the Claude Code and Codex command-line tools you already use.
2. **Apple Intelligence helpers**: smart icons for activities and one-line summaries of long notifications. These only ever use the on-device model.

Everything is off the network until you ask a question with a cloud provider. Settings for both live in **Settings → AI**.

---

## The Ask box

Open the island and click the **sparkles** button in the top row, next to the pin. You can also open it from anywhere with a URL (see [below](#islet-ask)).

| Action | How |
|---|---|
| Type a question | Click the field. The island takes the keyboard only while you use it |
| Send | Return, or the arrow button |
| Stop an answer | Esc, or the stop button |
| Hand the keyboard back | Esc, which also closes the island when nothing is streaming, or click in another app |
| Copy the answer | The copy button next to the field |
| Change provider for this session | The chip on the left. The default is set in Settings → AI |
| Start a new conversation | The pencil button (shown when follow-ups are on) |

What to expect:

- **Answers are short.** Every provider is asked for at most about 120 words of plain text, because the panel is small. Ask for more and you get more; the answer scrolls.
- **A cloud glyph** on the chip means the question leaves your Mac.
- **Closing the island cancels** a question that is still being answered.
- **Follow-ups** are off by default. With *Keep follow-ups in memory* on, the last 6 turns go with your next question so you can say "and in Python?". They are kept in memory only: New, or quitting Islet, forgets them.
- **Nothing is saved.** No history on disk, and no question or answer in any log.
- The island shows the first 8 KB of an answer; Copy gives you all of it (up to 256 KB).
- The answer redraws at most 20 times a second, and nothing runs while the island is closed.

### <a name="islet-ask"></a>`islet://ask`

```text
islet://ask
islet://ask?q=What%20is%20a%20monad
islet://ask?q=Explain%20this%20error&provider=claude
```

It opens the island on the Ask box with the question filled in and the field focused. **It never sends.** You read the question and press Return. `provider` accepts `on-device`, `claude`, `chatgpt`, `claude-code` and `codex`.

To get a global shortcut, make a Shortcuts, Raycast or Alfred command that opens `islet://ask` and give it a hotkey.

---

## Providers

| Provider | Needs | Runs where | Cost |
|---|---|---|---|
| **On-device** (default) | macOS 26 or later with Apple Intelligence on and downloaded | On your Mac | Free |
| **Claude** | An Anthropic API key | `api.anthropic.com` | Billed to your Anthropic account per token |
| **ChatGPT** | An OpenAI API key | `api.openai.com` | Billed to your OpenAI account per token |
| **Claude Code** | The `claude` CLI, signed in | The CLI calls Anthropic | Counts towards your Claude plan |
| **Codex** | The `codex` CLI, signed in | The CLI calls OpenAI | Counts towards your ChatGPT plan |

If the provider you picked can't answer (no key, CLI not found, Apple Intelligence not ready), the Ask box says why and lets you pick another. Islet never switches you to a cloud provider on its own.

### Claude (Anthropic API)

- `POST https://api.anthropic.com/v1/messages`, streamed, with headers `x-api-key`, `anthropic-version: 2023-06-01` and `anthropic-beta: server-side-fallback-2026-07-01`.
- Model: `claude-opus-5-5` by default; `claude-sonnet-5-5` and `claude-haiku-4-5` are offered too, and **Refresh List** in Settings loads every model your key can use (`GET /v1/models`).
- `max_tokens` 4096 and `output_config.effort` from Settings (Low by default, for quick answers). Opus 5.5 always thinks before answering; Islet doesn't show the thinking.
- `fallbacks: "default"` is on. If Claude declines a request, Anthropic re-runs it on its recommended fallback model and the answer continues in the same stream. If every model declines, the Ask box says so and shows no partial text.
- Errors: a rejected key (401) asks you to enter it again; a rate limit (429) says how long to wait; an overloaded API (529) is retried once after about a second.

### ChatGPT (OpenAI API)

- `POST https://api.openai.com/v1/responses`, streamed, with `store: false`, so OpenAI doesn't keep the response (it keeps them for 30 days by default). Follow-ups re-send the earlier turns rather than chaining stored responses.
- Model: `gpt-6-astra` by default; `gpt-6.1-sol` and `gpt-6-luna` are cheaper. **Refresh List** loads the chat models your key can use.
- `reasoning.effort` from Settings and `max_output_tokens` 2048. If a model doesn't take a reasoning effort, Islet asks again without it.

### Claude Code and Codex

Islet looks for the binaries in `~/.local/bin`, `/opt/homebrew/bin` and `/usr/local/bin` (and `~/.claude/local` for Claude Code), and runs them like this:

```bash
claude -p "<question>" --output-format stream-json --verbose --include-partial-messages \
       --tools "" --max-turns 1 --no-session-persistence --settings '{"disableAllHooks": true}'

codex exec --json --ephemeral --skip-git-repo-check --sandbox read-only "<question>"
```

- **No tools, one turn, nothing saved.** Claude Code gets no tools at all and no hooks run (so Islet's own agent hooks don't fire for your question). Codex runs in its read-only sandbox and doesn't save the session.
- **An empty folder** as the working directory (`~/Library/Application Support/Islet/ask`), so no project settings, `CLAUDE.md` or MCP config load.
- **A minimal environment**: `HOME`, `USER`, `LOGNAME`, `TMPDIR`, `LANG`, `PATH`, `TERM=dumb` and `NO_COLOR=1`. No API keys and no Islet token are passed, so Claude Code uses your subscription login, not API billing.
- **Arguments, not a shell**: the question is passed as one argument and never interpreted by a shell. Standard input is closed.
- **Limits**: output is capped at 256 KB, and an answer that takes more than 2 minutes is stopped. Stop or closing the island sends SIGTERM, then SIGKILL after 2 seconds.
- **Model**: blank uses the CLI's default. You can set one per CLI in Settings → AI (`sonnet`, `opus`, `gpt-6-luna`…).

If a CLI isn't signed in, the Ask box says so; run `claude` or `codex` once in Terminal to sign in. If it is too old for one of the flags above, the Ask box shows the flag it rejected.

---

## API keys

- Keys are stored in your **login keychain** as generic passwords: service `dev.islet.Islet.ai`, accounts `anthropic` and `openai`, readable only while your Mac is unlocked. By default only the app that created the item can read it without asking.
- When you paste a key, Islet checks its shape (`sk-ant-…` for Anthropic, `sk-…` for OpenAI), then calls `GET /v1/models` once to make sure it works, and only then stores it.
- Afterwards Settings shows only its last four characters. **Remove** deletes the Keychain item.
- A key is never written to `config.json`, never logged, never put in a URL, and never passed to a child process. Requests only go to `api.anthropic.com` and `api.openai.com` over HTTPS, redirects are refused (so the key header can't follow one), and the connection keeps no cache, cookies or credentials.
- Builds signed with a Developer ID tie Keychain access to the signing team. Ad-hoc builds are protected by your login keychain only.

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
| You press Return with Claude or ChatGPT | Your question, earlier turns if follow-ups are on, and a short instruction to keep the answer brief | Anthropic or OpenAI, with your key |
| You press Return with Claude Code or Codex | The same, as the CLI's prompt | The CLI's vendor, with your login |
| You save a key, or press Refresh List | A request for the model list | The key's provider |

- Nothing is sent at launch or in the background.
- Notification, calendar and clipboard text is never sent to a cloud provider. Smart icons and notification summaries use the on-device model or nothing.
- `islet://ask` only fills in the question. The local HTTP API and `isletctl` have no way to ask a question, so no script, web page or other app can spend money on your keys.

---

## Costs

Cloud answers are billed by the provider, per million tokens (input / output), at the prices published in September 2026:

| Model | Input | Output |
|---|---|---|
| `claude-opus-5-5` | $4 | $20 |
| `claude-sonnet-5-5` | $2 | $10 |
| `claude-haiku-4-5` | $1 | $5 |
| `gpt-6-astra` | $10 | $50 |
| `gpt-6.1-sol` | $2 | $10 |
| `gpt-6-luna` | $0.10 | $0.50 |

A typical Ask question is under 200 input tokens, and a short answer with Low effort a few hundred output tokens including the model's thinking, so with the default models an answer costs about one to two cents. Smaller models cost less; higher effort and follow-ups cost more. The footer under each answer shows the output tokens (and, for Claude Code, the cost it reports). Check your provider's pricing page for current prices.

---

## Apple Intelligence

Settings → AI shows the on-device model's status:

| Status | What Islet does |
|---|---|
| Ready | On-device answers in the Ask box; smart icons and notification summaries when *On-device AI for icons and summaries* is on |
| Not eligible (Intel Mac or older hardware) | Rules only; the Ask box offers the other providers |
| Apple Intelligence is off | Same; turn it on in System Settings → Apple Intelligence & Siri |
| Still downloading | Same, until the download finishes |
| macOS 14 or 15 | No on-device model; the other providers work |

The on-device model has a small context (about 4,000 tokens), so on-device follow-ups keep only the last two turns.

---

## `config.json`

The Ask settings are stored under `"ask"` (keys are not):

```json
{
  "aiAssist": true,
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

A missing or invalid value falls back to its default. Anything else under `"ask"`, such as a key pasted in by mistake, is dropped the next time Islet saves the file.
