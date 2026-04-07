# WP-ClaudeCode

**A lean, composable AI agent on WordPress — VPS or local.**

wp-claudecode puts an AI agent on any WordPress install with WordPress as its operating layer. Each component does one thing: [Claude Code](https://docs.anthropic.com/en/docs/claude-code) handles code, [Data Machine](https://github.com/Extra-Chill/data-machine) handles memory and scheduling, and [cc-connect](https://npmjs.com/package/cc-connect) handles communication (Discord, Telegram, Slack, or none). The agent's context window stays clean — no overhead for systems it's not using.

Runs on a dedicated VPS for always-on autonomous operation, or locally on your Mac/Linux machine for development and personal use.

Sibling project to [wp-opencode](https://github.com/Extra-Chill/wp-opencode), which does the same thing with OpenCode as the agent runtime.

## How It Works

```
 You (Discord / Telegram / SSH)
   │
   ▼
 Chat bridge (cc-connect or direct)
   │
   ▼
 Claude Code (coding agent)
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
   └── Data Machine ───── self-scheduling + AI tools
```

Data Machine creates three memory files on activation. They're injected into every session via `@` includes in CLAUDE.md — the agent wakes up knowing who it is, who you are, and what it's been working on. No memory management overhead in the context window.

## Standalone or Fleet

wp-claudecode works in two modes with the same setup:

**Standalone** — Data Machine handles autonomy. The agent self-schedules flows, queues tasks, runs on cron. No orchestrator needed.

**Fleet member** — An orchestrator routes tasks via Agent Ping webhooks and chat mentions. The agent executes on its own site, reports back. Multiple agents, each focused on their own WordPress site.

## Quick Start

### Local (macOS / Linux Desktop)

Works with any existing WordPress install — [WordPress Studio](https://developer.wordpress.com/studio/), MAMP, manual, etc.

```bash
git clone https://github.com/Extra-Chill/wp-claudecode.git
cd wp-claudecode
EXISTING_WP=~/Studio/my-wordpress-website ./setup.sh --local
```

On macOS, `--local` is auto-detected. The script installs Data Machine, agent skills, and optionally cc-connect — no infrastructure, no root, no systemd.

Start your agent:

```bash
cd ~/Studio/my-wordpress-website && cc-connect  # Chat bridge
cd ~/Studio/my-wordpress-website && claude       # Terminal only
```

#### WordPress Studio

```bash
./setup.sh --wp-path ~/Studio/my-wordpress-website
```

Studio is auto-detected. The generated CLAUDE.md includes `@STUDIO.md` and uses `studio wp` as the CLI prefix.

### VPS

#### Let Your Agent Do It

Add the `wp-claudecode-setup` skill to your local Claude Code:

```bash
cp -r skills/wp-claudecode-setup ~/.claude/skills/
```

Then: "Help me set up wp-claudecode on my VPS"

Your local agent SSHs into the server, runs the setup, and your VPS agent wakes up.

#### Manual

```bash
ssh root@your-server-ip
git clone https://github.com/Extra-Chill/wp-claudecode.git
cd wp-claudecode
SITE_DOMAIN=yourdomain.com ./setup.sh
systemctl start cc-connect
```

## Setup Options

| Flag | Description |
|------|-------------|
| `--local` | Local machine mode — skip infrastructure (no apt, nginx, systemd, SSL). Auto-detected on macOS. |
| `--existing` | Add to existing WordPress (skip WP install) |
| `--wp-path <path>` | Path to WordPress root (implies --existing; or set `EXISTING_WP`) |
| `--agent-slug <slug>` | DM agent slug (default: derived from domain) |
| `--no-data-machine` | Skip Data Machine (no persistent memory/scheduling) |
| `--no-chat` | Skip cc-connect; use Claude Code terminal only |
| `--skip-deps` | Skip apt package installation |
| `--multisite` | Convert to WordPress Multisite (subdirectory by default) |
| `--subdomain` | Use subdomain multisite (requires wildcard DNS) |
| `--no-skills` | Skip agent skills installation |
| `--skills-only` | Only install skills on existing site |
| `--skip-ssl` | Skip SSL/HTTPS configuration |
| `--root` | Run agent as root (default on VPS) |
| `--non-root` | Run agent as dedicated service user |
| `--dry-run` | Print commands without executing |

## What It Creates

**On the WordPress site:**

| File | Purpose |
|------|---------|
| `CLAUDE.md` | Claude Code config with DM memory `@` includes |
| `.claude/skills/` | WordPress and DM agent skills |

**On VPS (fresh install):**

| Component | Purpose |
|-----------|---------|
| nginx | Web server with PHP-FPM |
| SSL | Let's Encrypt certificate |
| systemd | Chat bridge service |
| Credentials | `~/.wp-claudecode-credentials` |

## Chat Bridge

cc-connect is installed by default — multi-platform bridge supporting Discord, Telegram, Slack, and more.

- **macOS**: Creates launchd plist for auto-start
- **VPS**: Creates systemd service
- **Config**: `~/.cc-connect/config.toml`

Use `--no-chat` to skip cc-connect and run Claude Code directly in the terminal.

## Comparison with wp-opencode

| Aspect | wp-opencode | wp-claudecode |
|--------|-------------|---------------|
| Agent runtime | OpenCode | Claude Code |
| Config format | `opencode.json` `{file:}` | `CLAUDE.md` `@` includes |
| Skills location | `.opencode/skills/` | `.claude/skills/` |
| Chat bridge | Kimaki (Discord) | cc-connect (multi-platform) |
| Memory system | Data Machine | Data Machine |
| Infrastructure | Same | Same |

Same memory system, same WordPress foundation, same VPS infrastructure, different agent runtime.

## Requirements

**Local:**
- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) installed (`claude` in PATH)
- WordPress installation with WP-CLI (`wp`) or [WordPress Studio](https://developer.wordpress.com/studio/) (`studio wp`)
- PHP 8.2+ and Composer (for Data Machine)
- Git, Node.js (for cc-connect)

**VPS (fresh install):**
- Ubuntu/Debian
- Root access
- Domain pointed at the server

The setup script installs all other dependencies (PHP, nginx, Node.js, WP-CLI, Claude Code, etc.).

## License

MIT
