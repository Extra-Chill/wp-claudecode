#!/bin/bash
#
# wp-claudecode setup script
# Bootstrap WordPress + Data Machine + Claude Code with an optional chat bridge.
#
# Claude Code provides the agent runtime natively — CLAUDE.md, .claude/skills/,
# hooks, and settings. This script bridges Data Machine's memory system into
# Claude Code's config and optionally wires up a chat interface.
#
# Usage:
#   Basic:            ./setup.sh --wp-path /path/to/wordpress
#   Existing env var: EXISTING_WP=/path/to/wordpress ./setup.sh
#   Without DM:       ./setup.sh --wp-path /path/to/wordpress --no-data-machine
#   Without chat:     ./setup.sh --wp-path /path/to/wordpress --no-chat
#   With Telegram:    ./setup.sh --wp-path /path/to/wordpress --chat telegram
#

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${GREEN}[wp-claudecode]${NC} $1"; }
warn() { echo -e "${YELLOW}[wp-claudecode]${NC} $1"; }
error() { echo -e "${RED}[wp-claudecode]${NC} $1"; exit 1; }
info() { echo -e "${BLUE}[wp-claudecode]${NC} $1"; }

run_cmd() {
  if [ "$DRY_RUN" = true ]; then
    echo -e "${BLUE}[dry-run]${NC} $*"
  else
    "$@"
  fi
}

write_file() {
  local file_path="$1"
  local content="$2"
  if [ "$DRY_RUN" = true ]; then
    echo -e "${BLUE}[dry-run]${NC} Would write to $file_path"
  else
    echo "$content" > "$file_path"
  fi
}

# Run a WP-CLI command using the detected prefix (studio wp / wp).
wp_cmd() {
  # shellcheck disable=SC2086
  run_cmd $WP_CLI "$@"
}

# Activate a plugin, handling multisite --url= branching.
activate_plugin() {
  local slug="$1"
  if [ "$MULTISITE" = true ]; then
    wp_cmd plugin activate "$slug" --url="$SITE_DOMAIN" || \
      warn "$slug may already be active"
  else
    wp_cmd plugin activate "$slug" || \
      warn "$slug may already be active"
  fi
}

# Install a WordPress plugin from a git repo.
install_plugin() {
  local slug="$1"
  local repo_url="$2"
  local plugin_dir="$WP_PATH/wp-content/plugins/$slug"

  if [ ! -d "$plugin_dir" ] || [ "$DRY_RUN" = true ]; then
    run_cmd git clone "$repo_url" "$plugin_dir"
    if [ -f "$plugin_dir/composer.json" ] || [ "$DRY_RUN" = true ]; then
      run_cmd composer install \
        --no-dev --no-interaction --working-dir="$plugin_dir" || \
        warn "Composer failed, some $slug features may not work"
    fi
  fi

  activate_plugin "$slug"
}

# Install agent skills from a git repo.
# Clones the repo, copies directories containing SKILL.md to the target.
install_skills_from_repo() {
  local repo_url="$1"
  local label="${2:-skills}"

  if [ "$DRY_RUN" = true ]; then
    echo -e "${BLUE}[dry-run]${NC} git clone --depth 1 $repo_url (extract skill dirs to $SKILLS_DIR)"
    return
  fi

  local tmp_dir
  tmp_dir=$(mktemp -d)
  if git clone --depth 1 "$repo_url" "$tmp_dir" 2>/dev/null; then
    local count=0
    for skill_dir in "$tmp_dir"/*/; do
      local skill_name
      skill_name=$(basename "$skill_dir")
      if [ -f "$skill_dir/SKILL.md" ] && [ ! -d "$SKILLS_DIR/$skill_name" ]; then
        cp -r "$skill_dir" "$SKILLS_DIR/$skill_name"
        log "  Installed skill: $skill_name"
        count=$((count + 1))
      elif [ -d "$SKILLS_DIR/$skill_name" ]; then
        log "  Skipped skill: $skill_name (already exists)"
      fi
    done
    rm -rf "$tmp_dir"
    log "$label: $count skills installed"
  else
    warn "Could not clone $label from $repo_url"
    rm -rf "$tmp_dir"
  fi
}

# ============================================================================
# Phase 0: Parse Arguments
# ============================================================================

WP_PATH=""
AGENT_SLUG=""
INSTALL_DATA_MACHINE=true
INSTALL_SKILLS=true
INSTALL_CHAT=true
CHAT_BRIDGE="cc-connect"
DRY_RUN=false
SHOW_HELP=false

while [[ $# -gt 0 ]]; do
  case $1 in
    --wp-path)
      WP_PATH="$2"
      shift 2
      ;;
    --agent-slug)
      AGENT_SLUG="$2"
      shift 2
      ;;
    --no-data-machine)
      INSTALL_DATA_MACHINE=false
      shift
      ;;
    --no-skills)
      INSTALL_SKILLS=false
      shift
      ;;
    --no-chat)
      INSTALL_CHAT=false
      shift
      ;;
    --chat)
      CHAT_BRIDGE="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --help|-h)
      SHOW_HELP=true
      shift
      ;;
    *)
      shift
      ;;
  esac
done

if [ "$SHOW_HELP" = true ]; then
  cat << 'HELP'
wp-claudecode setup script

Bootstrap WordPress + Data Machine + Claude Code with an optional chat bridge.
Claude Code is the agent runtime — this script bridges Data Machine's memory
system into Claude Code's native config (CLAUDE.md with @ includes).

USAGE:
  ./setup.sh --wp-path /path/to/wordpress
  EXISTING_WP=/path/to/wordpress ./setup.sh

OPTIONS:
  --wp-path <path>     Path to WordPress root (or set EXISTING_WP env var)
  --agent-slug <slug>  DM agent slug (default: derived from domain)
  --no-data-machine    Skip Data Machine installation
  --no-skills          Skip WordPress agent skill installation
  --no-chat            Skip chat bridge installation
  --chat <bridge>      Chat bridge: cc-connect (default) or telegram
  --dry-run            Print what would be done without making changes
  --help, -h           Show this help

ENVIRONMENT VARIABLES:
  EXISTING_WP          Path to WordPress root (alternative to --wp-path)
  AGENT_SLUG           Override agent slug (default: derived from domain)

EXAMPLES:
  # WordPress Studio site
  ./setup.sh --wp-path ~/Developer/LocalWP/my-site/app

  # Without Data Machine or chat
  ./setup.sh --wp-path /var/www/mysite --no-data-machine --no-chat

  # With Telegram bridge
  ./setup.sh --wp-path /var/www/mysite --chat telegram

  # Dry run to preview
  ./setup.sh --wp-path /var/www/mysite --dry-run
HELP
  exit 0
fi

# ============================================================================
# Phase 1: Detect Environment
# ============================================================================

log "Phase 1: Detecting environment..."

# Resolve WP path from --wp-path or EXISTING_WP
WP_PATH="${WP_PATH:-${EXISTING_WP:-}}"
if [ -z "$WP_PATH" ]; then
  error "WordPress path required. Use --wp-path <path> or set EXISTING_WP."
fi

# Normalize to absolute path
WP_PATH=$(cd "$WP_PATH" 2>/dev/null && pwd || echo "$WP_PATH")

# Verify WP root
if [ "$DRY_RUN" = false ]; then
  if [ ! -f "$WP_PATH/wp-config.php" ] && [ ! -f "$WP_PATH/wp-load.php" ]; then
    error "No WordPress installation found at $WP_PATH (missing wp-config.php and wp-load.php)"
  fi
fi

# Detect WP environment type
IS_STUDIO=false
WP_CLI=""

if command -v studio &> /dev/null && [ -f "$WP_PATH/STUDIO.md" ]; then
  IS_STUDIO=true
  WP_CLI="studio wp"
  log "Detected WordPress Studio environment"
elif command -v wp &> /dev/null; then
  WP_CLI="wp"
  log "Detected bare WP-CLI environment"
else
  if [ "$DRY_RUN" = true ]; then
    WP_CLI="wp"
    warn "No WP-CLI detected (continuing in dry-run mode)"
  else
    error "No WP-CLI found. Install WP-CLI or use WordPress Studio."
  fi
fi

# Verify Claude Code installed
if ! command -v claude &> /dev/null; then
  if [ "$DRY_RUN" = true ]; then
    warn "Claude Code not installed (continuing in dry-run mode)"
  else
    error "Claude Code not installed. Install from https://docs.anthropic.com/en/docs/claude-code"
  fi
fi

# Check PHP version
if command -v php &> /dev/null; then
  PHP_VERSION=$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;')
  PHP_MAJOR=$(echo "$PHP_VERSION" | cut -d. -f1)
  PHP_MINOR=$(echo "$PHP_VERSION" | cut -d. -f2)
  if [ "$PHP_MAJOR" -lt 8 ] || { [ "$PHP_MAJOR" -eq 8 ] && [ "$PHP_MINOR" -lt 2 ]; }; then
    warn "PHP $PHP_VERSION detected — Data Machine requires PHP 8.2+"
  else
    log "PHP $PHP_VERSION detected"
  fi
elif [ "$DRY_RUN" = false ] && [ "$INSTALL_DATA_MACHINE" = true ]; then
  warn "PHP not found in PATH — Data Machine requires PHP 8.2+"
fi

# Check composer
if ! command -v composer &> /dev/null; then
  if [ "$INSTALL_DATA_MACHINE" = true ] && [ "$DRY_RUN" = false ]; then
    warn "Composer not found — required for Data Machine installation"
  fi
fi

# Detect platform
PLATFORM="linux"
case "$(uname -s)" in
  Darwin) PLATFORM="mac" ;;
esac

# Detect multisite
MULTISITE=false
if [ "$DRY_RUN" = false ] && [ -n "$WP_CLI" ]; then
  IS_MULTISITE=$($WP_CLI eval 'echo is_multisite() ? "yes" : "no";' 2>/dev/null || echo "no")
  if [ "$IS_MULTISITE" = "yes" ]; then
    MULTISITE=true
    log "Detected WordPress Multisite"
  fi
fi

# Detect site domain
if [ "$DRY_RUN" = false ] && [ -n "$WP_CLI" ]; then
  SITE_DOMAIN=$($WP_CLI option get siteurl 2>/dev/null | sed 's|https\?://||' || basename "$WP_PATH")
else
  SITE_DOMAIN=$(basename "$WP_PATH")
fi

log "WordPress path: $WP_PATH"
log "Site domain: $SITE_DOMAIN"
log "WP-CLI: $WP_CLI"
log "Platform: $PLATFORM"

if [ "$DRY_RUN" = true ]; then
  log "Dry-run mode: commands will be printed, not executed"
fi

# ============================================================================
# Phase 2: Install Data Machine (optional)
# ============================================================================

if [ "$INSTALL_DATA_MACHINE" = true ]; then
  log "Phase 2: Installing Data Machine..."

  DM_ACTIVE=false
  if [ "$DRY_RUN" = false ] && [ -n "$WP_CLI" ]; then
    if $WP_CLI plugin list --status=active --format=csv 2>/dev/null | grep -q "data-machine"; then
      DM_ACTIVE=true
      log "Data Machine already active — skipping installation"
    fi
  fi

  if [ "$DM_ACTIVE" = false ]; then
    install_plugin data-machine https://github.com/Extra-Chill/data-machine.git
  fi
else
  log "Phase 2: Skipping Data Machine (--no-data-machine)"
fi

# ============================================================================
# Phase 3: Create DM Agent + Discover Paths
# ============================================================================

DM_FILES=()

if [ "$INSTALL_DATA_MACHINE" = true ]; then
  log "Phase 3: Creating Data Machine agent..."

  # Derive agent slug from domain
  if [ -z "$AGENT_SLUG" ]; then
    AGENT_SLUG=$(echo "$SITE_DOMAIN" | sed 's/\..*//' | tr '[:upper:]' '[:lower:]' | tr '_' '-')
  fi

  log "Agent slug: $AGENT_SLUG"

  if [ "$DRY_RUN" = false ] && [ -n "$WP_CLI" ]; then
    # Try creating the agent (idempotent — fails gracefully if exists)
    AGENT_NAME=$($WP_CLI option get blogname 2>/dev/null || echo "$AGENT_SLUG")
    $WP_CLI datamachine agents create "$AGENT_SLUG" --name="$AGENT_NAME" --owner=1 2>/dev/null || \
      log "Agent '$AGENT_SLUG' already exists"

    # Discover paths via CLI
    DM_PATHS_RAW=$($WP_CLI datamachine agent paths --agent="$AGENT_SLUG" --format=json 2>/dev/null || echo "")
    DM_PATHS_JSON=$(echo "$DM_PATHS_RAW" | sed -n '/^{/,/^}/p')

    if [ -n "$DM_PATHS_JSON" ]; then
      while IFS= read -r rel_path; do
        if [ -n "$rel_path" ]; then
          DM_FILES+=("$rel_path")
        fi
      done < <(echo "$DM_PATHS_JSON" | python3 -c "
import sys, json
data = json.load(sys.stdin)
for f in data.get('relative_files', []):
    print(f)
" 2>/dev/null)
      log "Discovered ${#DM_FILES[@]} memory files via CLI"
    fi
  fi

  # Fallback: check filesystem directly if CLI discovery failed
  if [ ${#DM_FILES[@]} -eq 0 ]; then
    log "Falling back to filesystem discovery..."
    DM_BASE="wp-content/uploads/datamachine-files"
    DM_SLUG="${AGENT_SLUG:-agent}"

    CANDIDATE_FILES=(
      "$DM_BASE/shared/SITE.md"
      "$DM_BASE/shared/RULES.md"
      "$DM_BASE/agents/$DM_SLUG/SOUL.md"
      "$DM_BASE/users/1/USER.md"
      "$DM_BASE/agents/$DM_SLUG/MEMORY.md"
    )

    for candidate in "${CANDIDATE_FILES[@]}"; do
      if [ -f "$WP_PATH/$candidate" ] || [ "$DRY_RUN" = true ]; then
        DM_FILES+=("$candidate")
      fi
    done
    log "Found ${#DM_FILES[@]} memory files on filesystem"
  fi
else
  log "Phase 3: Skipping agent creation (no Data Machine)"
fi

# ============================================================================
# Phase 4: Generate CLAUDE.md
# ============================================================================

log "Phase 4: Generating CLAUDE.md..."

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE="$SCRIPT_DIR/workspace/CLAUDE.md.tmpl"

if [ "$DRY_RUN" = false ] && [ -f "$WP_PATH/CLAUDE.md" ]; then
  log "CLAUDE.md already exists — skipping (delete to regenerate)"
else
  if [ -f "$TEMPLATE" ]; then
    # Read template
    CLAUDE_MD=$(cat "$TEMPLATE")

    # Substitute placeholders
    CLAUDE_MD=$(echo "$CLAUDE_MD" | sed "s|{{SITE_DOMAIN}}|$SITE_DOMAIN|g")
    CLAUDE_MD=$(echo "$CLAUDE_MD" | sed "s|{{WP_CLI_CMD}}|$WP_CLI|g")

    # Process Studio conditional
    if [ "$IS_STUDIO" = true ]; then
      CLAUDE_MD=$(echo "$CLAUDE_MD" | sed '/{{IF_STUDIO}}/d; /{{END_IF_STUDIO}}/d')
    else
      CLAUDE_MD=$(echo "$CLAUDE_MD" | sed '/{{IF_STUDIO}}/,/{{END_IF_STUDIO}}/d')
    fi

    # Process Data Machine conditional
    if [ "$INSTALL_DATA_MACHINE" = true ]; then
      CLAUDE_MD=$(echo "$CLAUDE_MD" | sed '/{{IF_DATA_MACHINE}}/d; /{{END_IF_DATA_MACHINE}}/d')
      CLAUDE_MD=$(echo "$CLAUDE_MD" | sed '/{{IF_NO_DATA_MACHINE}}/,/{{END_IF_NO_DATA_MACHINE}}/d')

      # Build @ includes from discovered files
      AT_INCLUDES=""
      for dm_file in "${DM_FILES[@]}"; do
        AT_INCLUDES="${AT_INCLUDES}@${dm_file}\n"
      done

      # Replace individual file conditionals with the built includes
      # Remove all IF_*_MD conditionals and replace with actual includes
      CLAUDE_MD=$(echo "$CLAUDE_MD" | sed '/{{IF_SITE_MD}}/,/{{END_IF_SITE_MD}}/d')
      CLAUDE_MD=$(echo "$CLAUDE_MD" | sed '/{{IF_RULES_MD}}/,/{{END_IF_RULES_MD}}/d')
      CLAUDE_MD=$(echo "$CLAUDE_MD" | sed '/{{IF_SOUL_MD}}/,/{{END_IF_SOUL_MD}}/d')
      CLAUDE_MD=$(echo "$CLAUDE_MD" | sed '/{{IF_USER_MD}}/,/{{END_IF_USER_MD}}/d')
      CLAUDE_MD=$(echo "$CLAUDE_MD" | sed '/{{IF_MEMORY_MD}}/,/{{END_IF_MEMORY_MD}}/d')

      # Insert @ includes after "## Data Machine Memory" heading
      if [ -n "$AT_INCLUDES" ]; then
        CLAUDE_MD=$(echo "$CLAUDE_MD" | sed "/## Data Machine Memory/a\\
\\
$(echo -e "$AT_INCLUDES")")
      fi
    else
      CLAUDE_MD=$(echo "$CLAUDE_MD" | sed '/{{IF_DATA_MACHINE}}/,/{{END_IF_DATA_MACHINE}}/d')
      CLAUDE_MD=$(echo "$CLAUDE_MD" | sed '/{{IF_NO_DATA_MACHINE}}/d; /{{END_IF_NO_DATA_MACHINE}}/d')
    fi

    # Process Multisite conditional
    if [ "$MULTISITE" = true ]; then
      CLAUDE_MD=$(echo "$CLAUDE_MD" | sed '/{{IF_MULTISITE}}/d; /{{END_IF_MULTISITE}}/d')
    else
      CLAUDE_MD=$(echo "$CLAUDE_MD" | sed '/{{IF_MULTISITE}}/,/{{END_IF_MULTISITE}}/d')
    fi

    # Clean up any remaining empty lines from conditional removal
    CLAUDE_MD=$(echo "$CLAUDE_MD" | sed '/^$/N;/^\n$/d')

    write_file "$WP_PATH/CLAUDE.md" "$CLAUDE_MD"
    log "Generated CLAUDE.md at $WP_PATH/CLAUDE.md"
  else
    # Inline generation if template not found
    warn "Template not found at $TEMPLATE — generating inline"

    CLAUDE_CONTENT="# $SITE_DOMAIN

WP-CLI: \`$WP_CLI\`"

    if [ "$IS_STUDIO" = true ]; then
      CLAUDE_CONTENT="$CLAUDE_CONTENT

@STUDIO.md"
    fi

    CLAUDE_CONTENT="$CLAUDE_CONTENT

## Data Machine Memory"

    if [ "$INSTALL_DATA_MACHINE" = true ]; then
      for dm_file in "${DM_FILES[@]}"; do
        CLAUDE_CONTENT="$CLAUDE_CONTENT
@$dm_file"
      done

      CLAUDE_CONTENT="$CLAUDE_CONTENT

Discover DM paths: \`$WP_CLI datamachine agent paths\`"
    else
      CLAUDE_CONTENT="$CLAUDE_CONTENT

Data Machine not installed. Install with:
\`$WP_CLI plugin install data-machine --activate\`"
    fi

    CLAUDE_CONTENT="$CLAUDE_CONTENT

## WordPress Source

- \`wp-content/plugins/\` — all plugin source
- \`wp-content/themes/\` — all theme source
- \`wp-includes/\` — WordPress core (read-only)"

    if [ "$MULTISITE" = true ]; then
      CLAUDE_CONTENT="$CLAUDE_CONTENT

## Multisite

This is a WordPress Multisite network. Use \`--url=<site>\` with WP-CLI commands to target a specific site."
    fi

    CLAUDE_CONTENT="$CLAUDE_CONTENT

## Memory Protocol

Update MEMORY.md when you learn something persistent — read it first, append.

## Rules

- Discover before memorizing — use \`--help\`
- Don't deploy or version bump without being told
- Never modify wp-includes/ or wp-admin/"

    write_file "$WP_PATH/CLAUDE.md" "$CLAUDE_CONTENT"
    log "Generated CLAUDE.md at $WP_PATH/CLAUDE.md (inline)"
  fi
fi

# ============================================================================
# Phase 5: Install Skills (optional)
# ============================================================================

SKILLS_DIR="$WP_PATH/.claude/skills"

if [ "$INSTALL_SKILLS" = true ]; then
  log "Phase 5: Installing agent skills..."
  run_cmd mkdir -p "$SKILLS_DIR"

  install_skills_from_repo "https://github.com/WordPress/agent-skills.git" "WordPress agent skills"

  if [ "$INSTALL_DATA_MACHINE" = true ]; then
    install_skills_from_repo "https://github.com/Extra-Chill/data-machine-skills.git" "Data Machine skills"
  fi
else
  log "Phase 5: Skipping agent skills (--no-skills)"
fi

# ============================================================================
# Phase 6: Chat Bridge (optional)
# ============================================================================

if [ "$INSTALL_CHAT" = true ]; then
  log "Phase 6: Installing chat bridge ($CHAT_BRIDGE)..."

  case "$CHAT_BRIDGE" in
    cc-connect)
      if ! command -v cc-connect &> /dev/null || [ "$DRY_RUN" = true ]; then
        run_cmd npm install -g cc-connect
      else
        log "cc-connect already installed"
      fi

      CC_CONFIG_DIR="$HOME/.cc-connect"
      CC_CONFIG_FILE="$CC_CONFIG_DIR/config.toml"

      if [ "$DRY_RUN" = false ] && [ -f "$CC_CONFIG_FILE" ]; then
        log "cc-connect config already exists — skipping"
      else
        run_cmd mkdir -p "$CC_CONFIG_DIR"

        CC_CONFIG="# cc-connect configuration
# Generated by wp-claudecode setup

[project]
path = \"$WP_PATH\"
agent = \"claude\"

[claude]
# Claude Code will be invoked in the project directory
working_directory = \"$WP_PATH\""

        write_file "$CC_CONFIG_FILE" "$CC_CONFIG"
        log "Generated cc-connect config at $CC_CONFIG_FILE"
      fi

      # macOS launchd plist for auto-start
      if [ "$PLATFORM" = "mac" ]; then
        CC_PLIST_LABEL="com.extrachill.cc-connect"
        CC_PLIST_DIR="$HOME/Library/LaunchAgents"
        CC_PLIST="$CC_PLIST_DIR/$CC_PLIST_LABEL.plist"

        if [ "$DRY_RUN" = true ]; then
          CC_BIN="/opt/homebrew/bin/cc-connect"
        else
          CC_BIN=$(which cc-connect 2>/dev/null || echo "/opt/homebrew/bin/cc-connect")
        fi

        run_cmd mkdir -p "$CC_PLIST_DIR"

        CC_PLIST_CONTENT="<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">
<plist version=\"1.0\">
<dict>
    <key>Label</key>
    <string>$CC_PLIST_LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>$CC_BIN</string>
    </array>
    <key>WorkingDirectory</key>
    <string>$WP_PATH</string>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>$CC_CONFIG_DIR/cc-connect.log</string>
    <key>StandardErrorPath</key>
    <string>$CC_CONFIG_DIR/cc-connect.error.log</string>
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin</string>
    </dict>
</dict>
</plist>"

        write_file "$CC_PLIST" "$CC_PLIST_CONTENT"
        log "cc-connect launchd plist created at $CC_PLIST"
        log "  Load:  launchctl bootstrap gui/$(id -u) $CC_PLIST"
        log "  Start: launchctl kickstart gui/$(id -u)/$CC_PLIST_LABEL"
      fi
      ;;

    telegram)
      if ! command -v pip &> /dev/null && ! command -v pip3 &> /dev/null; then
        if [ "$DRY_RUN" = false ]; then
          warn "pip/pip3 not found — required for claude-code-telegram"
        fi
      fi

      PIP_CMD="pip3"
      if ! command -v pip3 &> /dev/null && command -v pip &> /dev/null; then
        PIP_CMD="pip"
      fi

      run_cmd $PIP_CMD install "git+https://github.com/RichardAtCT/claude-code-telegram@latest"

      TELEGRAM_ENV="$WP_PATH/.env"
      if [ "$DRY_RUN" = false ] && [ -f "$TELEGRAM_ENV" ]; then
        log ".env already exists — skipping (add APPROVED_DIRECTORY manually)"
      else
        TELEGRAM_ENV_CONTENT="# claude-code-telegram configuration
APPROVED_DIRECTORY=$WP_PATH
# TELEGRAM_BOT_TOKEN=your-token-from-botfather
# TELEGRAM_ALLOWED_USER_ID=your-numeric-user-id"

        write_file "$TELEGRAM_ENV" "$TELEGRAM_ENV_CONTENT"
        log "Generated .env at $TELEGRAM_ENV"
        warn "Edit .env to add your TELEGRAM_BOT_TOKEN and TELEGRAM_ALLOWED_USER_ID"
      fi
      ;;

    *)
      warn "Unknown chat bridge: $CHAT_BRIDGE"
      warn "Supported bridges: cc-connect, telegram"
      warn "Skipping chat bridge installation"
      ;;
  esac
else
  log "Phase 6: Skipping chat bridge (--no-chat)"
fi

# ============================================================================
# Phase 7: Summary
# ============================================================================

echo ""
echo "=============================================="
if [ "$DRY_RUN" = true ]; then
  echo -e "${YELLOW}wp-claudecode dry-run complete!${NC}"
  echo "(No changes were made)"
else
  echo -e "${GREEN}wp-claudecode setup complete!${NC}"
fi
echo "=============================================="
echo ""
echo "WordPress:"
echo "  Domain:   $SITE_DOMAIN"
echo "  Path:     $WP_PATH"
echo "  WP-CLI:   $WP_CLI"
if [ "$IS_STUDIO" = true ]; then
  echo "  Runtime:  WordPress Studio"
fi
if [ "$MULTISITE" = true ]; then
  echo "  Multisite: yes"
fi
echo ""
echo "Claude Code:"
echo "  Config:   $WP_PATH/CLAUDE.md"
if [ "$INSTALL_SKILLS" = true ]; then
  echo "  Skills:   $SKILLS_DIR"
fi
echo ""
if [ "$INSTALL_DATA_MACHINE" = true ]; then
  echo "Data Machine:"
  echo "  Agent:    $AGENT_SLUG"
  echo "  Files:    ${#DM_FILES[@]} memory files linked"
  echo "  Discover: $WP_CLI datamachine agent paths${AGENT_SLUG:+ --agent=$AGENT_SLUG}"
  echo ""
fi
if [ "$INSTALL_CHAT" = true ]; then
  echo "Chat Bridge:"
  echo "  Type:     $CHAT_BRIDGE"
  case "$CHAT_BRIDGE" in
    cc-connect)
      echo "  Config:   $HOME/.cc-connect/config.toml"
      ;;
    telegram)
      echo "  Config:   $WP_PATH/.env"
      ;;
  esac
  echo ""
fi

echo "=============================================="
echo "Next steps"
echo "=============================================="
echo ""
echo "  1. Start Claude Code in your WordPress directory:"
echo "     cd $WP_PATH && claude"
echo ""
if [ "$INSTALL_DATA_MACHINE" = true ]; then
  echo "  2. Configure Data Machine:"
  echo "     Set AI provider API keys in WP Admin > Data Machine > Settings"
  echo ""
fi
if [ "$INSTALL_CHAT" = true ]; then
  case "$CHAT_BRIDGE" in
    cc-connect)
      echo "  Configure cc-connect:"
      echo "     Edit $HOME/.cc-connect/config.toml with your chat platform credentials"
      if [ "$PLATFORM" = "mac" ]; then
        echo "     Start service: launchctl bootstrap gui/$(id -u) $CC_PLIST"
      fi
      ;;
    telegram)
      echo "  Configure Telegram bridge:"
      echo "     1. Get bot token from @BotFather"
      echo "     2. Get your user ID from @userinfobot"
      echo "     3. Edit $WP_PATH/.env with your credentials"
      echo "     4. Run: claude-code-telegram"
      ;;
  esac
  echo ""
fi
echo "  Claude Code will load CLAUDE.md automatically on first run."
if [ "$INSTALL_DATA_MACHINE" = true ] && [ ${#DM_FILES[@]} -gt 0 ]; then
  echo "  You'll be prompted to approve the @ includes for DM memory files."
fi
echo ""
