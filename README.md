# claude-statusline

A two-line status line for [Claude Code](https://claude.com/claude-code).

```
Opus 5  ·  you@example.com  ·  high  ·  context ██░░░░ 27%    12% ████░░░░   ↻ 20:20
gojenaya  ·  ⎇ main ✓                    ~/Documents/explorations/my-project
```

**Line 1 — Claude:** model, signed-in Claude account, reasoning effort, active
subagent, context-window usage, 5-hour rate-limit usage, and the time your 5h
window resets.

The account email comes from the status-line payload when Claude Code supplies
one, otherwise from `oauthAccount.emailAddress` in `~/.claude.json` (or
`$CLAUDE_CONFIG_DIR.json`). It's omitted if neither is available.

**Line 2 — Git:** active `gh` account, current branch, working-tree state
(`+staged ~modified ?untracked`), unpushed/unpulled commit counts, and cwd.

Bars are colour-coded: green under 50%, orange 50–79%, red 80%+.

Rate-limit numbers only arrive in API response headers, so a brand-new session
has none until the first message completes. They're cached in
`~/.claude/.statusline-rate-limits` and replayed until the window resets.

## Requirements

- `bash`, `jq`, `git`
- `gh` (optional — the GitHub account name is skipped if it's missing)
- A terminal with truecolor and unicode support

## Install

```sh
git clone https://github.com/gojenaya/claude-statusline.git ~/.claude-statusline
bash ~/.claude-statusline/install.sh
```

Then restart Claude Code.

`install.sh` writes the `statusLine` block into `~/.claude/settings.json`
(backing the file up first). To wire it up by hand instead:

```json
{
  "statusLine": {
    "type": "command",
    "command": "bash \"$HOME/.claude-statusline/statusline.sh\""
  }
}
```

Use an absolute path or `$HOME` — a `~/Documents/...` path breaks on machines
where `Documents` is a cloud-storage folder rather than a real directory.

## Usage-budget subcommands

If you keep spend records under `~/.claude/usage` (with a `.config` holding
`budget=`, `initial_usage=`, and `start_ts=`), the script doubles as a small
editor for them:

| Command | Effect |
| --- | --- |
| `statusline.sh budget <n>` | set the budget figure |
| `statusline.sh usage <n>` | set `initial_usage` |
| `statusline.sh sync <n>` | zero out recorded costs via `_offset` files and reset `initial_usage` / `start_ts` |

Override the location with `CLAUDE_USAGE_DIR`.

## switch-github.sh

Toggles the active `gh` account between two logins, so the name on line 2
follows whichever identity you're committing as:

```sh
bash ~/.claude-statusline/switch-github.sh
```

Edit `ACCOUNT1` / `ACCOUNT2` at the top of the file to match your own logins.
