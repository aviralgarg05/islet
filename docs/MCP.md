# Casement as an MCP server

`casementctl mcp` runs a small [Model Context Protocol](https://modelcontextprotocol.io) server over stdio. An agent or chat app that supports MCP can then put things in the notch by calling tools, with no hooks to install. The server forwards each call to Casement's local API using the same token as `casementctl`, so Casement has to be running. If it isn't, the tool call fails and tells the model nothing was shown.

## Tools

| Tool | What it does |
|---|---|
| `notify` | Shows a short message (`title`, optional `subtitle`, `icon` as an SF Symbol name, and `seconds` on screen: 6 by default, at most 60). |
| `show_progress` | Creates or updates a live activity for a longer task (`id`, `title`, optional `subtitle`, and `progress` from 0 to 1 or `step` and `steps`). With neither `progress` nor `steps` it shows a spinner. Call it again with the same `id` to update it. |
| `finish` | Marks that task done or failed (`id`, `success`, optional `subtitle`). A success stays for 12 seconds, a failure for a minute. |
| `dismiss` | Removes an activity made through MCP (`id`). |
| `start_timer` | Starts a countdown of up to 24 hours (`duration`, optional `title`). `duration` can be `90s`, `1h 30m`, `half an hour`, `tea 4m` or `at 18:30`; a bare number means minutes. Without a `title`, the words around the duration become the title. |
| `list_activities` | Lists the activities in the notch (id, title and state), including ones Casement or other apps made. Live Activities and notifications mirrored by Casement are left out unless **Let scripts read Live Activities and notifications** is on (Settings → Advanced → Local API). |

The server adds `mcp-` to the front of every id, so a tool call can't replace an activity made by Casement itself or another app. An id that already starts with `mcp-`, as `list_activities` shows it, is used as it is, so `finish` and `dismiss` take either form. Ids keep only ASCII letters, digits and `._:-`; when anything else had to go, a short hash of the original is added, so the same id always finds the same task. A task stays until it's finished or dismissed; one that gets no update for 15 minutes dims.

## Setting it up

Use the full path to `casementctl` inside the app. It's only on your `PATH` if you linked it (see [API.md](API.md#casementctl)), and apps opened from the Dock may not see your shell's `PATH`. If Casement isn't in `/Applications`, change the path to match.

```text
/Applications/Casement.app/Contents/MacOS/casementctl
```

**Claude Code** (`--scope user` makes it available in every project):

```bash
claude mcp add --scope user casement -- /Applications/Casement.app/Contents/MacOS/casementctl mcp
```

**Claude Desktop**: add this to `~/Library/Application Support/Claude/claude_desktop_config.json`, then restart Claude Desktop.

```json
{
  "mcpServers": {
    "casement": { "command": "/Applications/Casement.app/Contents/MacOS/casementctl", "args": ["mcp"] }
  }
}
```

**Codex**: in `~/.codex/config.toml`:

```toml
[mcp_servers.casement]
command = "/Applications/Casement.app/Contents/MacOS/casementctl"
args = ["mcp"]
```

**Cursor**: in `~/.cursor/mcp.json` (or a project's `.cursor/mcp.json`), the same `mcpServers` block as Claude Desktop.

Then ask for it in plain words, for example "show your progress in the notch as you go" or "start a 20 minute timer in the notch".

## Hooks or MCP?

The two work together. Hooks (see [INTEGRATIONS.md](INTEGRATIONS.md)) report what an agent is doing without the model's involvement, and they're how approvals reach the notch. MCP tools are for things the model decides to show: a plan with steps, a note when it's done, a timer the user asked for.
