# WP-ClaudeCode

**Bridge WordPress + Data Machine into Claude Code's native config.**

wp-claudecode connects [Claude Code](https://docs.anthropic.com/en/docs/claude-code) to WordPress using [Data Machine](https://github.com/Extra-Chill/data-machine) for persistent memory and identity. Claude Code already provides the agent runtime — CLAUDE.md, `.claude/skills/`, hooks, settings. This script bridges DM's memory system into that native config and optionally wires up a chat interface.

Sibling project to [wp-opencode](https://github.com/Extra-Chill/wp-opencode), which does the same thing with OpenCode as the agent runtime.

## How It Works

```
 You (Terminal / Discord / Telegram)
   │
   ▼
 Chat bridge (cc-connect, Telegram, or direct)
   │
   ▼
 Claude Code (agent runtime)
   │
   ├── CLAUDE.md ──── @ includes for DM memory files
   │   ├── @SITE.md ──── site-wide context (priority 10)
   │   ├── @RULES.md ─── shared rules (priority 15)
   │   ├── @SOUL.md ──── agent identity (priority 20)
   │   ├── @USER.md ──── human profile (priority 25)
   │   └── @MEMORY.md ── accumulated knowledge (priority 30)
   │
   ├── .claude/skills/ ── WordPress + DM agent skills
   ├── WP-CLI ─────────── WordPress control
   └── Data Machine ───── memory, scheduling, AI tools
```

Data Machine's memory files are injected into every Claude Code session via `@` includes in CLAUDE.md. The agent wakes up knowing who it is, who you are, and what it's been working on.

## Quick Start

```bash
git clone https://github.com/Extra-Chill/wp-claudecode.git
cd wp-claudecode
./setup.sh --wp-path ~/Developer/LocalWP/my-site/app
```

Start your agent:

```bash
cd ~/Developer/LocalWP/my-site/app && claude
```

Claude Code loads CLAUDE.md automatically. First run will prompt you to approve the `@` includes for DM memory files.

### WordPress Studio

```bash
./setup.sh --wp-path ~/Studio/my-wordpress-website
```

Studio is auto-detected. The generated CLAUDE.md includes `@STUDIO.md` and uses `studio wp` as the CLI prefix.

### Let Your Agent Do It

Copy the `wp-claudecode-setup` skill to your Claude Code skills directory:

```bash
cp -r skills/wp-claudecode-setup ~/.claude/skills/
```

Then tell Claude Code: "Help me set up wp-claudecode"

## Setup Options

| Flag | Description |
|------|-------------|
| `--wp-path <path>` | Path to WordPress root (required, or set `EXISTING_WP` env var) |
| `--agent-slug <slug>` | DM agent slug (default: derived from domain) |
| `--no-data-machine` | Skip Data Machine installation |
| `--no-skills` | Skip WordPress agent skill installation |
| `--no-chat` | Skip chat bridge |
| `--chat <bridge>` | Chat bridge: `cc-connect` (default) or `telegram` |
| `--dry-run` | Print what would be done without making changes |

## What It Creates

| File | Location | Purpose |
|------|----------|---------|
| `CLAUDE.md` | WP root | Claude Code config with DM `@` includes |
| `.claude/skills/` | WP root | WordPress and DM agent skills |

That's it. Claude Code's native config system handles everything else.

## Chat Bridges

### cc-connect (default)

Multi-platform bridge supporting Discord, Telegram, Slack, and more.

```bash
./setup.sh --wp-path /path/to/wp --chat cc-connect
```

On macOS, creates a launchd plist for auto-start. Edit `~/.cc-connect/config.toml` for platform credentials.

### claude-code-telegram

Python-based Telegram bridge.

```bash
./setup.sh --wp-path /path/to/wp --chat telegram
```

Generates a `.env` file in the WP root. Add your `TELEGRAM_BOT_TOKEN` and `TELEGRAM_ALLOWED_USER_ID`.

### No bridge

```bash
./setup.sh --wp-path /path/to/wp --no-chat
```

Use Claude Code directly in the terminal.

## Comparison with wp-opencode

| Aspect | wp-opencode | wp-claudecode |
|--------|-------------|---------------|
| Agent runtime | OpenCode | Claude Code |
| Config format | `opencode.json` `{file:}` | `CLAUDE.md` `@` includes |
| Skills location | `.opencode/skills/` | `.claude/skills/` |
| Default chat bridge | Kimaki (Discord) | cc-connect (multi-platform) |
| Alt chat bridge | opencode-telegram | claude-code-telegram |
| Memory system | Data Machine | Data Machine |
| Infrastructure | nginx, systemd, SSL (VPS) | None (local-first) |

Same memory system, same WordPress foundation, different agent runtime.

## Requirements

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) installed (`claude` in PATH)
- WordPress installation with WP-CLI (`wp`) or [WordPress Studio](https://developer.wordpress.com/studio/) (`studio wp`)
- PHP 8.2+ and Composer (for Data Machine)
- Git

## License

MIT
