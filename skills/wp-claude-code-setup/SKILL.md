---
name: wp-claude-code-setup
description: "Install wp-claude-code on a VPS or local machine. Use this skill from your LOCAL machine to deploy WordPress + Data Machine + Claude Code on a remote server, or to set up a local agent on your own machine."
compatibility: "For VPS: requires SSH access, Ubuntu/Debian recommended. For local: requires an existing WordPress install (WordPress Studio, MAMP, manual, etc.) and Node.js. Claude Code CLI must be installed."
---

# WP-Claude-Code Setup Skill

**Purpose:** Help a user install wp-claude-code on a remote VPS or their local machine.

This skill is for the **local agent** (Claude Code) assisting with installation. Once Claude Code is running on the VPS with a chat bridge (cc-connect), this skill is no longer needed — the VPS agent takes over. For local installs, the agent runs directly on the user's machine.

---

## FIRST: Interview the User

**Do NOT proceed with installation until you have asked these questions and gotten answers.**
Ask one question at a time. Skip any question whose answer is already clear from context.

### Question 1: Installation Type

> "Are you setting up a **fresh WordPress site on a VPS**, adding to an **existing WordPress site on a VPS**, running **locally on your own machine**, or using a **WordPress Studio** site?"

**Options:**
- **Fresh VPS install** — New VPS, new WordPress site (installs nginx, PHP, MySQL, SSL, etc.)
- **Existing WordPress (VPS)** — Site already running on a server, just add Claude Code
- **Local install** — Use an existing WordPress on your own machine (MAMP, manual, etc.)
- **Studio site** — WordPress Studio site (auto-detects Studio environment, uses `studio wp`)

### Question 2: Data Machine

> "Do you want **Data Machine** installed? This gives your agent persistent memory, self-scheduling, and autonomous operation capabilities.
>
> - **Yes (recommended)** — Full memory system, agent files (SOUL.md, MEMORY.md, etc.), self-scheduling
> - **No** — Agent responds when asked, no persistent memory or scheduling"

Default: **Yes**

### Question 3: Agent Slug

> "What slug should the Data Machine agent use? This determines the agent's identity and file paths."

Default: derived from the site domain (e.g., `testing-grounds` from `testing-grounds.local`). Skip this question if the user is fine with the default.

### Question 4: Chat Bridge

> "Do you want a **chat bridge** for remote interaction with your agent?
>
> - **cc-connect** — Multi-platform chat bridge (installed via npm, runs as a service)
> - **None** — Use Claude Code terminal only"

Default: **None** for local/Studio installs. For VPS installs, ask explicitly.

### Question 5: Skills

> "Should we install **WordPress agent skills**? These are `.claude/skills/` files that teach the agent WordPress development patterns (plugin dev, block themes, REST API, WP-CLI, etc.)."

Default: **Yes**

### Question 6: Multisite

> "Is this a **WordPress Multisite** network?
>
> - **No** — Standard single-site WordPress
> - **Yes (subdirectory)** — Multisite with subdirectory structure (example.com/site2)
> - **Yes (subdomain)** — Multisite with subdomains (site2.example.com) — requires wildcard DNS"

Default: **No**

### Question 7: Server / Path Details

**For Fresh VPS:**

> "I need some details about your server:
> 1. What **domain** will this site use?
> 2. What is the **server IP address**?
> 3. Do you have **SSH access**? (key or password)"

**For Existing WordPress (VPS):**

> "What is the **full path** to the WordPress installation on the server? (e.g., `/var/www/mysite`)"

**For Local install:**

> "Where is WordPress installed on your machine? (e.g., `~/Developer/LocalWP/mysite/app`)"

**For Studio site:**

> "Where is the Studio site on your machine? (e.g., `~/Studio/my-wordpress-website`)"

---

## Build the Command

Based on the user's answers, construct the appropriate command from this table:

| Scenario | Command |
|----------|---------|
| Fresh VPS | `SITE_DOMAIN=example.com ./setup.sh` |
| Fresh VPS, no DM | `SITE_DOMAIN=example.com ./setup.sh --no-data-machine` |
| Fresh VPS, no chat | `SITE_DOMAIN=example.com ./setup.sh --no-chat` |
| Existing VPS | `EXISTING_WP=/var/www/mysite ./setup.sh --existing` |
| Existing VPS, custom slug | `EXISTING_WP=/var/www/mysite ./setup.sh --existing --agent-slug myagent` |
| Local + DM | `EXISTING_WP=~/path ./setup.sh --local` |
| Local + DM, no chat | `EXISTING_WP=~/path ./setup.sh --local --no-chat` |
| Local, no DM | `EXISTING_WP=~/path ./setup.sh --local --no-data-machine --no-chat` |
| Studio site | `./setup.sh --wp-path ~/Studio/my-site` |
| Studio, no DM | `./setup.sh --wp-path ~/Studio/my-site --no-data-machine` |
| Multisite (subdirectory) | Add `--multisite` to any command above |
| Multisite (subdomain) | Add `--multisite --subdomain` to any command above |
| No skills | Add `--no-skills` to any command above |
| Skills only (existing site) | `./setup.sh --wp-path ~/path --skills-only` |
| Dry run | Add `--dry-run` to any command above |

**Additional flags:**
- `--skip-deps` — Skip apt package installation (nginx, PHP, MySQL already present)
- `--skip-ssl` — Skip Let's Encrypt SSL configuration
- `--root` — Run agent as root (default for VPS)
- `--non-root` — Run agent as dedicated service user (`claudecode`)
- `--agent-slug <slug>` — Override auto-derived agent slug

**Environment variables:**
- `SITE_DOMAIN` — Domain for fresh install (required)
- `SITE_PATH` — WordPress path override (default: `/var/www/$SITE_DOMAIN`)
- `EXISTING_WP` — Path to existing WordPress (required with `--existing`)
- `CC_CONNECT_TOKEN` — cc-connect bot token (skip interactive setup)
- `MCP_SERVERS` — JSON object merged into `.mcp.json` mcpServers key (requires `jq`)
- `EXTRA_PLUGINS` — Space-separated `slug:url` pairs for additional plugins

---

## Confirm Before Proceeding

Before running anything, summarize the plan and get explicit confirmation:

> "Here's the plan:
> - **Type:** Fresh VPS install
> - **Domain:** example.com
> - **Server:** 123.45.67.89
> - **Data Machine:** Yes
> - **Agent slug:** example-com (auto-derived)
> - **Chat bridge:** cc-connect
> - **Skills:** Yes
> - **Multisite:** No
> - **Command:** `SITE_DOMAIN=example.com ./setup.sh`
>
> Does this look right?"

Only continue after explicit confirmation.

---

## Dry-Run First

Recommend running with `--dry-run` before the actual install. This prints every command without executing, so the user can review:

```bash
# Append --dry-run to the constructed command
SITE_DOMAIN=example.com ./setup.sh --dry-run
```

Review the dry-run output with the user. If it looks correct, proceed to the actual run.

---

## Run the Setup

### Local / Studio Install

Run directly on your machine — no SSH needed:

```bash
cd /path/to/wp-claude-code
<constructed command>
```

For Studio sites, `--wp-path` auto-detects the Studio environment and uses `studio wp` for all WP-CLI operations.

### VPS Install via SSH

```bash
ssh root@<server-ip>
git clone https://github.com/Extra-Chill/wp-claude-code.git
cd wp-claude-code
<constructed command>
```

For **existing WordPress on VPS**, make sure you know the exact WordPress root path before running:

```bash
ssh root@<server-ip>
# Verify WordPress is at the expected path
ls /var/www/mysite/wp-config.php
git clone https://github.com/Extra-Chill/wp-claude-code.git
cd wp-claude-code
EXISTING_WP=/var/www/mysite ./setup.sh --existing
```

---

## Post-Setup Verification

After setup.sh completes, verify each component. Use the appropriate WP-CLI prefix for the environment.

### VPS Verification

```bash
# CLAUDE.md generated
cat /var/www/mysite/CLAUDE.md | head -20

# WordPress responsive
wp --allow-root option get siteurl

# Data Machine plugin active (if installed)
wp --allow-root plugin list --status=active | grep data-machine

# Skills installed
ls /var/www/mysite/.claude/skills/

# Claude Code installed
claude --version

# Chat bridge running (if installed)
systemctl status cc-connect
```

### Local Verification

```bash
# CLAUDE.md generated
cat ~/path/to/wordpress/CLAUDE.md | head -20

# Data Machine plugin active (if installed)
wp plugin list --status=active | grep data-machine

# Skills installed
ls ~/path/to/wordpress/.claude/skills/

# Claude Code installed
claude --version
```

### Studio Verification

```bash
# CLAUDE.md generated
cat ~/Studio/my-site/CLAUDE.md | head -20

# Data Machine plugin active (if installed)
studio wp plugin list --status=active --format=csv | grep data-machine

# Skills installed
ls ~/Studio/my-site/.claude/skills/

# Claude Code installed
claude --version
```

### Chat Bridge Verification (if installed)

**VPS (systemd):**
```bash
systemctl status cc-connect
journalctl -u cc-connect --no-pager -n 20
```

**macOS (launchd):**
```bash
launchctl print gui/$(id -u)/com.extrachill.cc-connect
tail -f ~/Library/Application\ Support/cc-connect/cc-connect.log
```

---

## When to Use This Skill

Use when the user says things like:
- "Help me install wp-claude-code on my server"
- "Set up Claude Code on this VPS"
- "Add Claude Code to my existing WordPress site"
- "Set up a local WordPress AI agent"
- "Install wp-claude-code with WordPress Studio"
- "Set up Data Machine and Claude Code together"

**Do NOT use** for ongoing WordPress management — that is the agent's job after installation.

---

## Troubleshooting

### Studio not detected

`--wp-path` auto-detects Studio by checking for the Studio CLI. If detection fails:
- Verify `studio` CLI is installed: `which studio`
- Verify the path points to a valid Studio site: `studio site status`
- Fall back to `--local` mode with `EXISTING_WP` if Studio CLI is unavailable

### WP-CLI not found

- macOS: `brew install wp-cli`
- Linux: `curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar && chmod +x wp-cli.phar && mv wp-cli.phar /usr/local/bin/wp`
- Studio sites do not need standalone WP-CLI — `studio wp` handles everything

### Data Machine plugin activation fails

- Check PHP version: Data Machine requires PHP 8.2+
- Run `composer install` in the DM plugin directory if dependencies are missing
- Check `wp-content/debug.log` for PHP fatal errors
- Studio: enable debug logging with `studio site set --debug-log`

### Skills clone fails

- Verify GitHub access: `ssh -T git@github.com` or check HTTPS connectivity
- Check network connectivity: `curl -I https://github.com`
- Run skills installation separately: `./setup.sh --wp-path /path --skills-only`

### Claude Code not installed

- Install Claude Code CLI: `npm install -g @anthropic-ai/claude-code`
- Verify: `claude --version`
- Ensure Node.js 18+ is installed: `node --version`

### CLAUDE.md @ includes pointing to missing files

The `@` includes in CLAUDE.md reference Data Machine agent files. If they point to missing files:
- Run `wp datamachine agent paths` (or `studio wp datamachine agent paths`) to check current paths
- The agent files are created when DM initializes — activate the plugin and visit the admin to trigger setup
- Delete `CLAUDE.md` and re-run setup to regenerate with correct paths

### cc-connect won't start

**VPS:**
- Check systemd logs: `journalctl -u cc-connect --no-pager -n 50`
- Verify token: `systemctl show cc-connect -p Environment`
- Restart: `systemctl restart cc-connect`

**macOS:**
- Check logs: `tail -50 ~/Library/Application\ Support/cc-connect/cc-connect.log`
- Reload service: `launchctl bootout gui/$(id -u)/com.extrachill.cc-connect && launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.extrachill.cc-connect.plist`
