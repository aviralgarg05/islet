# Islet as an MCP server

`isletctl mcp` runs a small [Model Context Protocol](https://modelcontextprotocol.io) server over stdio. An agent or chat app that supports MCP can then put things in the notch by calling tools, with no hooks to install. Islet has to be running; the server forwards each call to its local API using the same token as `isletctl`.

## Tools

| Tool | What it does |
|---|---|
| `notify` | A short message for a few seconds (`title`, optional `subtitle`, `icon` as an SF Symbol name, `seconds`). |
| `show_progress` | Creates or updates a live activity for a longer task (`id`, `title`, optional `subtitle`, `progress` 0–1, or `step` and `steps`). Without progress it shows a spinner. |
| `finish` | Marks that task done or failed (`id`, `success`, optional `subtitle`). It stays briefly, then goes. |
| `dismiss` | Removes an activity (`id`). |
| `start_timer` | A countdown (`duration` like `90s`, `5m`, `1h`, optional `title`). |
| `list_activities` | What the notch is showing now. |

Activities made this way get ids starting with `mcp-`, so a tool call can't replace one made by Islet itself or another app. A task that gets no update for 15 minutes is dimmed.

## Setting it up

Use the full path to `isletctl` inside the app, since these apps don't read your shell's `PATH`:

```text
/Applications/Islet.app/Contents/MacOS/isletctl
```

**Claude Code**

```bash
claude mcp add --scope user islet -- /Applications/Islet.app/Contents/MacOS/isletctl mcp
```

**Claude Desktop**: add this to `~/Library/Application Support/Claude/claude_desktop_config.json`, then restart it.

```json
{
  "mcpServers": {
    "islet": { "command": "/Applications/Islet.app/Contents/MacOS/isletctl", "args": ["mcp"] }
  }
}
```

**Codex**: in `~/.codex/config.toml`:

```toml
[mcp_servers.islet]
command = "/Applications/Islet.app/Contents/MacOS/isletctl"
args = ["mcp"]
```

**Cursor**: in `~/.cursor/mcp.json`, the same `mcpServers` block as Claude Desktop.

Then ask for it in plain words, for example "show your progress in the notch as you go" or "start a 20 minute timer in the notch".

## Hooks or MCP?

The two work together. Hooks (see [INTEGRATIONS.md](INTEGRATIONS.md)) report what an agent is doing without the model's involvement, and they're how approvals reach the notch. MCP tools are for things the model decides to show: a plan with steps, a note when it's done, a timer the user asked for.
