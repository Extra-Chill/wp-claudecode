# wp-claudecode Setup Assistant

You are helping the user set up wp-claudecode — a bridge between WordPress, Data Machine, and Claude Code.

## Interview

Ask the user these questions one at a time. Skip any that are already answered by context.

1. **WordPress path**: Where is the WordPress installation?
   - Look for `wp-config.php` or `wp-load.php` at the path
   - Common locations: `~/Developer/LocalWP/*/app`, `/var/www/html`, current directory

2. **Data Machine**: Should we install Data Machine?
   - Default: yes
   - If already installed, skip

3. **Agent slug**: What slug should we use for the DM agent?
   - Default: derived from the site domain (e.g., `testing-grounds` from `testing-grounds.local`)

4. **Skills**: Should we install WordPress agent skills?
   - Default: yes

5. **Chat bridge**: Do you want a chat bridge for remote interaction?
   - Options: cc-connect (multi-platform), claude-code-telegram, or none
   - Default: none for local dev

## Execution

Once you have answers, construct the setup command:

```bash
./setup.sh --wp-path <path> [--agent-slug <slug>] [--no-data-machine] [--no-skills] [--no-chat | --chat <bridge>]
```

Show the user the full command and explain what it will do before running it.

## Post-Setup Verification

After setup completes:

1. Confirm CLAUDE.md was generated at the WP root
2. Check that `@` includes point to existing files
3. Verify skills are in `.claude/skills/`
4. If chat bridge was installed, confirm its configuration

## Troubleshooting

- **Studio not detected**: Make sure `studio` CLI is installed and you're in a Studio-managed site
- **WP-CLI not found**: Install with `brew install wp-cli` or check PATH
- **DM plugin activation fails**: Check PHP version (8.2+ required) and composer dependencies
- **Skills clone fails**: Check GitHub access and network connectivity
