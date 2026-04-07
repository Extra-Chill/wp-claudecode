#!/bin/bash
#
# wp-claudecode setup script
# Bootstrap WordPress + Data Machine + Claude Code on a VPS or local machine
# with a pluggable chat interface layer.
#
# Usage:
#   Fresh VPS:        SITE_DOMAIN=example.com ./setup.sh
#   Existing WP:      EXISTING_WP=/var/www/mysite ./setup.sh --existing
#   Local (macOS):    EXISTING_WP=/path/to/wordpress ./setup.sh --local
#   Without chat:     ./setup.sh --no-chat
#   Without DM:       ./setup.sh --no-data-machine
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

# Run a WP-CLI command with the correct flags for the current platform.
wp_cmd() {
  if [ "$IS_STUDIO" = true ]; then
    # shellcheck disable=SC2086
    run_cmd studio wp "$@"
  else
    # shellcheck disable=SC2086
    run_cmd wp "$@" $WP_ROOT_FLAG --path="$SITE_PATH"
  fi
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
  local plugin_dir="$SITE_PATH/wp-content/plugins/$slug"

  if [ ! -d "$plugin_dir" ] || [ "$DRY_RUN" = true ]; then
    run_cmd git clone "$repo_url" "$plugin_dir"
    if [ -f "$plugin_dir/composer.json" ] || [ "$DRY_RUN" = true ]; then
      run_cmd env COMPOSER_ALLOW_SUPERUSER=1 composer install \
        --no-dev --no-interaction --working-dir="$plugin_dir" || \
        warn "Composer failed, some $slug features may not work"
    fi
  fi

  activate_plugin "$slug"
  fix_ownership "$plugin_dir"
}

# Set file ownership to www-data (no-op in local mode).
fix_ownership() {
  if [ "$LOCAL_MODE" = false ]; then
    run_cmd chown -R www-data:www-data "$1"
  fi
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
    log "$label installed ($count skills)"
  else
    warn "Could not clone $label from $repo_url"
    rm -rf "$tmp_dir"
  fi
}

# ============================================================================
# Parse arguments
# ============================================================================

MODE="fresh"
LOCAL_MODE=false
SKIP_DEPS=false
SKIP_SSL=false
INSTALL_DATA_MACHINE=true
INSTALL_CHAT=true
SHOW_HELP=false
DRY_RUN=false
RUN_AS_ROOT=true
MULTISITE=false
MULTISITE_TYPE="subdirectory"
INSTALL_SKILLS=true
SKILLS_ONLY=false
IS_STUDIO=false

while [[ $# -gt 0 ]]; do
  case $1 in
    --skills-only)
      SKILLS_ONLY=true
      shift
      ;;
    --existing)
      MODE="existing"
      shift
      ;;
    --local)
      LOCAL_MODE=true
      MODE="existing"
      SKIP_DEPS=true
      SKIP_SSL=true
      RUN_AS_ROOT=false
      shift
      ;;
    --wp-path)
      EXISTING_WP="$2"
      MODE="existing"
      shift 2
      ;;
    --skip-deps)
      SKIP_DEPS=true
      shift
      ;;
    --no-data-machine)
      INSTALL_DATA_MACHINE=false
      shift
      ;;
    --no-chat)
      INSTALL_CHAT=false
      shift
      ;;
    --skip-ssl)
      SKIP_SSL=true
      shift
      ;;
    --root)
      RUN_AS_ROOT=true
      shift
      ;;
    --non-root)
      RUN_AS_ROOT=false
      shift
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --multisite)
      MULTISITE=true
      shift
      ;;
    --subdomain)
      MULTISITE_TYPE="subdomain"
      shift
      ;;
    --no-skills)
      INSTALL_SKILLS=false
      shift
      ;;
    --agent-slug)
      AGENT_SLUG="$2"
      shift 2
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

Bootstrap WordPress + Data Machine + Claude Code on a VPS or local machine,
with a pluggable chat bridge for talking to your agent.

USAGE:
  Fresh VPS:           SITE_DOMAIN=example.com ./setup.sh
  Existing WordPress:  EXISTING_WP=/var/www/mysite ./setup.sh --existing
  Local (macOS/Linux): EXISTING_WP=/path/to/wordpress ./setup.sh --local
  Studio site:         ./setup.sh --wp-path ~/Studio/my-site

OPTIONS:
  --existing         Add Claude Code to existing WordPress (skip WP install)
  --local            Local machine mode (skip infrastructure: no apt, nginx,
                     systemd, SSL, service users). Works with any local
                     WordPress install (Studio, MAMP, manual, etc.)
  --wp-path <path>   Path to WordPress root (implies --existing; or set EXISTING_WP)
  --agent-slug <s>   Override DM agent slug (default: derived from domain)
  --no-data-machine  Skip Data Machine plugin (no persistent memory/scheduling)
  --no-chat          Skip chat bridge (cc-connect); use Claude Code terminal only
  --skip-deps        Skip apt package installation
  --multisite        Convert to WordPress Multisite (subdirectory by default)
  --subdomain        Use subdomain multisite (requires wildcard DNS; use with --multisite)
  --no-skills        Skip WordPress agent skills installation
  --skills-only      Only run skills installation on existing site
  --skip-ssl         Skip SSL/HTTPS configuration
  --root             Run agent as root (default)
  --non-root         Run agent as dedicated service user (claudecode)
  --dry-run          Print commands without executing
  --help, -h         Show this help

ENVIRONMENT VARIABLES:
  SITE_DOMAIN        Domain for fresh install (required)
  SITE_PATH          WordPress path (default: /var/www/$SITE_DOMAIN)
  EXISTING_WP        Path to existing WordPress (required with --existing)
  DB_NAME            Database name (fresh install only)
  DB_USER            Database user (fresh install only)
  DB_PASS            Database password (auto-generated if not set)
  AGENT_SLUG         Override agent slug (default: derived from domain)
  CC_CONNECT_TOKEN   cc-connect bot token (skip interactive setup)

EXAMPLES:
  # Fresh VPS
  SITE_DOMAIN=example.com ./setup.sh

  # Existing WordPress on VPS
  EXISTING_WP=/var/www/mysite ./setup.sh --existing

  # Local WordPress Studio site
  ./setup.sh --wp-path ~/Studio/my-wordpress-website

  # Local without Data Machine or chat
  EXISTING_WP=~/Developer/LocalWP/mysite/app ./setup.sh --local --no-data-machine --no-chat

  # Dry run
  SITE_DOMAIN=example.com ./setup.sh --dry-run
HELP
  exit 0
fi

# Detect OS and platform
PLATFORM="linux"
case "$(uname -s)" in
  Darwin) PLATFORM="mac"; OS="macos" ;;
  Linux)
    if [ -f /etc/os-release ]; then
      . /etc/os-release
      OS=$ID
    else
      if [ "$DRY_RUN" = true ]; then
        OS="ubuntu"
        warn "Cannot detect OS (dry-run mode), assuming Ubuntu"
      else
        error "Cannot detect OS. This script supports Ubuntu/Debian."
      fi
    fi
    ;;
  *) error "Unsupported OS: $(uname -s)" ;;
esac

# Auto-enable local mode on macOS
if [ "$PLATFORM" = "mac" ] && [ "$LOCAL_MODE" = false ]; then
  LOCAL_MODE=true
  MODE="existing"
  SKIP_DEPS=true
  SKIP_SSL=true
  RUN_AS_ROOT=false
  log "macOS detected — enabling local mode automatically"
fi

# Validate Linux distro (only matters for fresh/VPS installs)
if [ "$PLATFORM" = "linux" ] && [ "$LOCAL_MODE" = false ]; then
  if [[ "$OS" != "ubuntu" && "$OS" != "debian" ]]; then
    if [ "$DRY_RUN" = true ]; then
      warn "Unsupported OS: $OS (continuing in dry-run mode)"
      OS="ubuntu"
    else
      error "VPS mode supports Ubuntu/Debian only. Detected: $OS. Use --local for local installs."
    fi
  fi
fi

# Check root (not required in local mode)
if [ "$DRY_RUN" = false ] && [ "$LOCAL_MODE" = false ] && [ "$EUID" -ne 0 ]; then
  error "Please run as root (sudo ./setup.sh). Use --local for local installs."
fi

# WP-CLI flag: --allow-root on VPS, omit on local
if [ "$LOCAL_MODE" = true ]; then
  WP_ROOT_FLAG=""
else
  WP_ROOT_FLAG="--allow-root"
fi

log "Detected OS: $OS (platform: $PLATFORM, local: $LOCAL_MODE)"
log "Mode: $MODE"
log "Chat bridge: $([ "$INSTALL_CHAT" = true ] && echo "cc-connect" || echo "none")"
log "Data Machine: $INSTALL_DATA_MACHINE"
log "Multisite: $MULTISITE ($MULTISITE_TYPE)"
if [ "$DRY_RUN" = true ]; then
  log "Dry-run mode: commands will be printed, not executed"
fi

# ============================================================================
# Detect PHP Version
# ============================================================================

detect_php_version() {
  if command -v php &> /dev/null; then
    PHP_VERSION=$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;')
    log "Detected existing PHP version: $PHP_VERSION"
    return
  fi

  if [ "$DRY_RUN" = true ]; then
    PHP_VERSION="8.3"
    log "PHP version (dry-run assumed): $PHP_VERSION"
    return
  fi

  # apt-based detection only on Linux
  if [ "$PLATFORM" != "mac" ]; then
    apt update -qq 2>/dev/null
    PHP_VERSION=$(apt-cache search '^php[0-9]+\.[0-9]+-fpm$' 2>/dev/null | \
      sed -E 's/^php([0-9]+\.[0-9]+)-fpm.*/\1/' | \
      sort -t. -k1,1nr -k2,2nr | \
      head -1)
  fi

  if [ -n "$PHP_VERSION" ]; then
    log "Best available PHP version: $PHP_VERSION"
  else
    PHP_VERSION=""
    warn "Could not detect PHP version, will use system default"
  fi
}

detect_php_version

# ============================================================================
# Configuration
# ============================================================================

if [ "$MODE" = "existing" ]; then
  if [ -z "$EXISTING_WP" ]; then
    error "EXISTING_WP must be set when using --existing mode or --wp-path"
  fi
  if [ "$DRY_RUN" = false ] && [ ! -f "$EXISTING_WP/wp-config.php" ] && [ ! -f "$EXISTING_WP/wp-load.php" ]; then
    error "No WordPress found at $EXISTING_WP (missing wp-config.php and wp-load.php)"
  fi
  SITE_PATH="$EXISTING_WP"
  # Normalize to absolute path
  if [ "$DRY_RUN" = false ]; then
    SITE_PATH=$(cd "$SITE_PATH" 2>/dev/null && pwd || echo "$SITE_PATH")
  fi

  # Detect WordPress Studio
  if command -v studio &> /dev/null && [ -f "$SITE_PATH/STUDIO.md" ]; then
    IS_STUDIO=true
    log "Detected WordPress Studio environment"
  fi

  if [ "$DRY_RUN" = true ]; then
    SITE_DOMAIN="${SITE_DOMAIN:-$(basename "$SITE_PATH")}"
  elif [ "$IS_STUDIO" = true ]; then
    SITE_DOMAIN=$(studio wp option get siteurl 2>/dev/null | sed 's|https\?://||' || basename "$SITE_PATH")
  else
    SITE_DOMAIN=$(cd "$SITE_PATH" && wp option get siteurl $WP_ROOT_FLAG 2>/dev/null | sed 's|https\?://||' || basename "$SITE_PATH")
  fi
  log "Existing WordPress at: $SITE_PATH ($SITE_DOMAIN)"

  # Detect if existing WP is multisite
  if [ "$DRY_RUN" = false ]; then
    if [ "$IS_STUDIO" = true ]; then
      IS_EXISTING_MULTISITE=$(studio wp eval 'echo is_multisite() ? "yes" : "no";' 2>/dev/null || echo "no")
    else
      IS_EXISTING_MULTISITE=$(cd "$SITE_PATH" && wp eval 'echo is_multisite() ? "yes" : "no";' $WP_ROOT_FLAG 2>/dev/null || echo "no")
    fi
    if [ "$IS_EXISTING_MULTISITE" = "yes" ]; then
      MULTISITE=true
      if [ "$IS_STUDIO" = true ]; then
        IS_SUBDOMAIN=$(studio wp eval 'echo is_subdomain_install() ? "yes" : "no";' 2>/dev/null || echo "no")
      else
        IS_SUBDOMAIN=$(cd "$SITE_PATH" && wp eval 'echo is_subdomain_install() ? "yes" : "no";' $WP_ROOT_FLAG 2>/dev/null || echo "no")
      fi
      if [ "$IS_SUBDOMAIN" = "yes" ]; then
        MULTISITE_TYPE="subdomain"
      fi
      log "Detected existing multisite ($MULTISITE_TYPE)"
    fi
  fi
else
  SITE_DOMAIN="${SITE_DOMAIN:-example.com}"
  SITE_PATH="${SITE_PATH:-/var/www/$SITE_DOMAIN}"
fi

DB_NAME="${DB_NAME:-wordpress}"
DB_USER="${DB_USER:-wordpress}"
DB_PASS="${DB_PASS:-$(openssl rand -base64 16)}"
WP_ADMIN_USER="${WP_ADMIN_USER:-admin}"
WP_ADMIN_PASS="${WP_ADMIN_PASS:-$(openssl rand -base64 16)}"
WP_ADMIN_EMAIL="${WP_ADMIN_EMAIL:-admin@$SITE_DOMAIN}"

# Service user configuration
if [ "$LOCAL_MODE" = true ]; then
  SERVICE_USER="$(whoami)"
  SERVICE_HOME="$HOME"
  CC_DATA_DIR="$HOME/.cc-connect"
  DM_WORKSPACE_DIR="${DATAMACHINE_WORKSPACE_PATH:-$HOME/.datamachine/workspace}"
elif [ "$RUN_AS_ROOT" = true ]; then
  SERVICE_USER="root"
  SERVICE_HOME="/root"
  CC_DATA_DIR="/root/.cc-connect"
  DM_WORKSPACE_DIR="${DATAMACHINE_WORKSPACE_PATH:-/var/lib/datamachine/workspace}"
else
  SERVICE_USER="claudecode"
  SERVICE_HOME="/home/claudecode"
  CC_DATA_DIR="/home/claudecode/.cc-connect"
  DM_WORKSPACE_DIR="${DATAMACHINE_WORKSPACE_PATH:-/var/lib/datamachine/workspace}"
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ============================================================================
# --skills-only: skip everything except skills phase
# ============================================================================

if [ "$SKILLS_ONLY" = true ]; then
  if [ -z "$SITE_PATH" ] && [ -z "$EXISTING_WP" ]; then
    error "SITE_PATH or EXISTING_WP must be set with --skills-only"
  fi
  SITE_PATH="${SITE_PATH:-$EXISTING_WP}"
  if [ "$DRY_RUN" = false ] && [ ! -d "$SITE_PATH" ]; then
    error "Directory not found: $SITE_PATH"
  fi
  if [ -d "$SITE_PATH/wp-content/plugins/data-machine" ]; then
    INSTALL_DATA_MACHINE=true
  fi
  log "Installing skills to $SITE_PATH/.claude/skills/ ..."
fi

# ============================================================================
# Phases 1-8 (skipped by --skills-only)
# ============================================================================

if [ "$SKILLS_ONLY" != true ]; then

# ============================================================================
# Phase 1: System Dependencies
# ============================================================================

if [ "$SKIP_DEPS" = false ]; then
  log "Phase 1: Installing system dependencies..."
  run_cmd apt update
  run_cmd apt upgrade -y

  if [ -n "$PHP_VERSION" ]; then
    PHP_PACKAGES="php${PHP_VERSION}-fpm php${PHP_VERSION}-mysql php${PHP_VERSION}-xml php${PHP_VERSION}-curl php${PHP_VERSION}-mbstring php${PHP_VERSION}-zip php${PHP_VERSION}-gd php${PHP_VERSION}-intl php${PHP_VERSION}-imagick"
  else
    PHP_PACKAGES="php-fpm php-mysql php-xml php-curl php-mbstring php-zip php-gd php-intl php-imagick"
  fi

  run_cmd apt install -y nginx $PHP_PACKAGES mariadb-server git unzip curl wget composer

  if [ -z "$PHP_VERSION" ] && command -v php &> /dev/null; then
    PHP_VERSION=$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;')
    log "PHP version after install: $PHP_VERSION"
  fi

  # Node.js (required for cc-connect chat bridge)
  if ! command -v node &> /dev/null || [ "$DRY_RUN" = true ]; then
    log "Installing Node.js..."
    if [ -z "$NODE_VERSION" ]; then
      NODE_VERSION=$(curl -fsSL https://nodejs.org/dist/index.json 2>/dev/null | \
        grep -o '"version":"v[0-9]*' | head -1 | sed 's/"version":"v//')
      NODE_VERSION="${NODE_VERSION:-22}"
    fi
    log "Installing Node.js $NODE_VERSION..."
    if [ "$DRY_RUN" = true ]; then
      echo -e "${BLUE}[dry-run]${NC} curl -fsSL https://deb.nodesource.com/setup_${NODE_VERSION}.x | bash -"
      echo -e "${BLUE}[dry-run]${NC} apt install -y nodejs"
    else
      curl -fsSL "https://deb.nodesource.com/setup_${NODE_VERSION}.x" | bash -
      apt install -y nodejs
    fi
  else
    log "Node.js already installed: $(node --version)"
  fi

  # WP-CLI
  if ! command -v wp &> /dev/null || [ "$DRY_RUN" = true ]; then
    log "Installing WP-CLI..."
    run_cmd curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
    run_cmd chmod +x wp-cli.phar
    run_cmd mv wp-cli.phar /usr/local/bin/wp
  fi

  # Claude Code
  if ! command -v claude &> /dev/null || [ "$DRY_RUN" = true ]; then
    log "Installing Claude Code..."
    run_cmd npm install -g @anthropic-ai/claude-code
  else
    log "Claude Code already installed: $(claude --version 2>/dev/null || echo 'unknown')"
  fi
else
  log "Skipping system dependencies (--skip-deps or --local)"

  # Verify Claude Code is available in local mode
  if ! command -v claude &> /dev/null; then
    if [ "$DRY_RUN" = true ]; then
      warn "Claude Code not installed (continuing in dry-run mode)"
    else
      error "Claude Code not installed. Install from https://docs.anthropic.com/en/docs/claude-code"
    fi
  else
    log "Claude Code available: $(claude --version 2>/dev/null || echo 'installed')"
  fi
fi

# ============================================================================
# Phase 2: Database (fresh install only)
# ============================================================================

if [ "$MODE" = "fresh" ]; then
  log "Phase 2: Configuring database..."
  run_cmd mysql -e "CREATE DATABASE IF NOT EXISTS $DB_NAME;"
  run_cmd mysql -e "CREATE USER IF NOT EXISTS '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';"
  run_cmd mysql -e "GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'localhost';"
  run_cmd mysql -e "FLUSH PRIVILEGES;"
else
  log "Phase 2: Using existing database"
fi

# ============================================================================
# Phase 3: WordPress (fresh install only)
# ============================================================================

if [ "$MODE" = "fresh" ]; then
  log "Phase 3: Installing WordPress..."
  run_cmd mkdir -p "$SITE_PATH"
  if [ "$DRY_RUN" = false ]; then
    cd "$SITE_PATH"
  fi

  if [ ! -f wp-config.php ] || [ "$DRY_RUN" = true ]; then
    run_cmd wp core download --allow-root
    run_cmd wp config create --allow-root \
      --dbname="$DB_NAME" --dbuser="$DB_USER" --dbpass="$DB_PASS" --dbhost="localhost"
    run_cmd wp core install --allow-root \
      --url="https://$SITE_DOMAIN" --title="My Site" \
      --admin_user="$WP_ADMIN_USER" --admin_password="$WP_ADMIN_PASS" \
      --admin_email="$WP_ADMIN_EMAIL"
  fi
  run_cmd chown -R www-data:www-data "$SITE_PATH"
else
  log "Phase 3: Using existing WordPress at $SITE_PATH"
  if [ "$DRY_RUN" = false ]; then
    cd "$SITE_PATH"
  fi
fi

# ============================================================================
# Phase 3.5: WordPress Multisite (optional)
# ============================================================================

if [ "$MULTISITE" = true ] && [ "$MODE" = "fresh" ]; then
  log "Phase 3.5: Converting to WordPress Multisite ($MULTISITE_TYPE)..."

  if [ "$MULTISITE_TYPE" = "subdomain" ]; then
    run_cmd wp core multisite-convert --subdomains --allow-root --path="$SITE_PATH"
  else
    run_cmd wp core multisite-convert --allow-root --path="$SITE_PATH"
  fi

  log "Multisite conversion complete"
elif [ "$MULTISITE" = true ] && [ "$MODE" = "existing" ]; then
  log "Phase 3.5: Existing multisite detected — skipping conversion"
fi

# ============================================================================
# Phase 3.9: Service User (early creation)
# ============================================================================

if [ "$LOCAL_MODE" = false ] && [ "$RUN_AS_ROOT" = false ]; then
  if ! id -u "$SERVICE_USER" &>/dev/null || [ "$DRY_RUN" = true ]; then
    log "Phase 3.9: Creating service user '$SERVICE_USER'..."
    run_cmd useradd -m -s /bin/bash -G www-data "$SERVICE_USER"
  fi
fi

# ============================================================================
# Phase 4: Data Machine Plugin (optional)
# ============================================================================

if [ "$INSTALL_DATA_MACHINE" = true ]; then
  log "Phase 4: Installing Data Machine..."
  install_plugin data-machine https://github.com/Extra-Chill/data-machine.git

  if [ "$MULTISITE" = true ]; then
    log "Data Machine activated on main site. Activate on subsites with:"
    log "  wp plugin activate data-machine --url=subsite.$SITE_DOMAIN $WP_ROOT_FLAG"
  fi

  log "Installing Data Machine Code (developer tools)..."
  install_plugin data-machine-code https://github.com/Extra-Chill/data-machine-code.git

  # Set workspace path in wp-config.php if not already defined
  if [ "$DRY_RUN" = false ] && [ -f "$SITE_PATH/wp-config.php" ] && [ "$IS_STUDIO" = false ]; then
    if ! grep -q 'DATAMACHINE_WORKSPACE_PATH' "$SITE_PATH/wp-config.php"; then
      wp_cmd config set DATAMACHINE_WORKSPACE_PATH "$DM_WORKSPACE_DIR" --type=constant
      log "Set DATAMACHINE_WORKSPACE_PATH to $DM_WORKSPACE_DIR"
    else
      log "DATAMACHINE_WORKSPACE_PATH already defined in wp-config.php"
    fi
  elif [ "$DRY_RUN" = true ]; then
    echo -e "${BLUE}[dry-run]${NC} wp config set DATAMACHINE_WORKSPACE_PATH $DM_WORKSPACE_DIR --type=constant"
  fi
else
  log "Phase 4: Skipping Data Machine (--no-data-machine)"
fi

# ============================================================================
# Phase 4.5: Create Data Machine Agent
# ============================================================================

if [ "$INSTALL_DATA_MACHINE" = true ]; then
  log "Phase 4.5: Creating Data Machine agent..."

  # Derive agent slug from domain
  if [ -z "${AGENT_SLUG:-}" ]; then
    AGENT_SLUG=$(echo "$SITE_DOMAIN" | sed 's/\..*//' | tr '[:upper:]' '[:lower:]' | tr '_' '-')
  fi

  if [ "$DRY_RUN" = false ] && [ -f "$SITE_PATH/wp-config.php" ]; then
    AGENT_NAME=$(wp_cmd option get blogname 2>/dev/null || echo "$AGENT_SLUG")

    # Check if agent already exists (idempotent for re-runs)
    EXISTING_AGENT=$(wp_cmd datamachine agents show "$AGENT_SLUG" --format=json 2>/dev/null || echo "")

    if [ -z "$EXISTING_AGENT" ]; then
      log "Creating agent: $AGENT_SLUG ($AGENT_NAME)"
      wp_cmd datamachine agents create "$AGENT_SLUG" \
        --name="$AGENT_NAME" \
        --owner=1

      # Scaffold SOUL.md
      log "Scaffolding SOUL.md..."
      SOUL_CONTENT="# Agent Soul — ${AGENT_SLUG}

## Identity
I am ${AGENT_SLUG} — an AI agent managing ${AGENT_NAME} (${SITE_DOMAIN}). I operate on this WordPress site via WP-CLI and Data Machine, powered by Claude Code.

## Voice & Tone
Be genuinely helpful. Skip filler. Be resourceful — read the file, check the context, search for it, then ask if stuck.

## Rules
- Private things stay private
- When in doubt, ask before acting externally
- Git for everything — no uncommitted work
- Root cause over symptoms — fix the real problem
- Stop when stuck — pause after 2-3 failures, ask for guidance
- NEVER deploy without being told to

## Context
I manage ${SITE_DOMAIN} — a WordPress site with Data Machine for persistent memory, scheduling, and AI tools."

      echo "$SOUL_CONTENT" | wp_cmd datamachine agent files write SOUL.md \
        --agent="$AGENT_SLUG"

      # Scaffold MEMORY.md
      log "Scaffolding MEMORY.md..."
      MEMORY_CONTENT="# Agent Memory — ${AGENT_SLUG}

## Operational Notes
- Agent created during wp-claudecode setup on $(date +%Y-%m-%d)"

      echo "$MEMORY_CONTENT" | wp_cmd datamachine agent files write MEMORY.md \
        --agent="$AGENT_SLUG"

      log "Agent '$AGENT_SLUG' created with SOUL.md and MEMORY.md"
    else
      log "Agent '$AGENT_SLUG' already exists — skipping creation"
    fi
  else
    log "Dry-run: would create agent '$AGENT_SLUG' with SOUL.md and MEMORY.md"
  fi
else
  AGENT_SLUG=""
fi

# ============================================================================
# Phase 5: Nginx (fresh install only)
# ============================================================================

if [ "$MODE" = "fresh" ]; then
  log "Phase 5: Configuring nginx..."

  if [ -n "$PHP_VERSION" ]; then
    PHP_FPM_SOCK="/var/run/php/php${PHP_VERSION}-fpm.sock"
  else
    if [ "$DRY_RUN" = false ]; then
      PHP_FPM_SOCK=$(find /var/run/php -name "php*-fpm.sock" 2>/dev/null | head -1)
    fi
    PHP_FPM_SOCK="${PHP_FPM_SOCK:-/var/run/php/php-fpm.sock}"
  fi

  if [ "$MULTISITE" = true ] && [ "$MULTISITE_TYPE" = "subdomain" ]; then
    NGINX_CONFIG="server {
    listen 80;
    server_name $SITE_DOMAIN *.$SITE_DOMAIN;
    root $SITE_PATH;
    index index.php index.html;

    location / {
        try_files \$uri \$uri/ /index.php?\$args;
    }

    location ~ \\.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:$PHP_FPM_SOCK;
    }

    location ~ /\\.ht {
        deny all;
    }

    location ~ ^/files/(.*)$ {
        try_files /wp-includes/ms-files.php?\$args =404;
        access_log off;
        log_not_found off;
        expires max;
    }
}"
  elif [ "$MULTISITE" = true ] && [ "$MULTISITE_TYPE" = "subdirectory" ]; then
    NGINX_CONFIG="server {
    listen 80;
    server_name $SITE_DOMAIN www.$SITE_DOMAIN;
    root $SITE_PATH;
    index index.php index.html;

    if (!-e \$request_filename) {
        rewrite /wp-admin\$ \$scheme://\$host\$request_uri/ permanent;
        rewrite ^(/[^/]+)?(/wp-.*) \$2 last;
        rewrite ^(/[^/]+)?(/.*\\.php) \$2 last;
    }

    location / {
        try_files \$uri \$uri/ /index.php?\$args;
    }

    location ~ \\.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:$PHP_FPM_SOCK;
    }

    location ~ /\\.ht {
        deny all;
    }

    location ~ ^/[_0-9a-zA-Z-]+/files/(.*)$ {
        try_files /wp-includes/ms-files.php?\$args =404;
        access_log off;
        log_not_found off;
        expires max;
    }
}"
  else
    NGINX_CONFIG="server {
    listen 80;
    server_name $SITE_DOMAIN www.$SITE_DOMAIN;
    root $SITE_PATH;
    index index.php index.html;

    location / {
        try_files \$uri \$uri/ /index.php?\$args;
    }

    location ~ \\.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:$PHP_FPM_SOCK;
    }

    location ~ /\\.ht {
        deny all;
    }
}"
  fi

  write_file "/etc/nginx/sites-available/$SITE_DOMAIN" "$NGINX_CONFIG"
  run_cmd ln -sf "/etc/nginx/sites-available/$SITE_DOMAIN" /etc/nginx/sites-enabled/

  if [ "$DRY_RUN" = false ]; then
    nginx -t && systemctl reload nginx
  fi
  run_cmd systemctl enable nginx
  if [ -n "$PHP_VERSION" ]; then
    run_cmd systemctl enable "php${PHP_VERSION}-fpm"
  fi
else
  log "Phase 5: Using existing web server configuration"
fi

# ============================================================================
# Phase 5.5: SSL (Let's Encrypt)
# ============================================================================

if [ "$SKIP_SSL" = true ]; then
  log "Skipping SSL (--skip-ssl)"
else
  log "Phase 5.5: Configuring SSL..."

  if ! command -v certbot &> /dev/null || [ "$DRY_RUN" = true ]; then
    run_cmd apt install -y certbot python3-certbot-nginx
  fi

  if [ "$DRY_RUN" = false ]; then
    SERVER_IP=$(curl -s -4 ifconfig.me 2>/dev/null || curl -s -4 icanhazip.com 2>/dev/null)
    DOMAIN_IP=$(dig +short "$SITE_DOMAIN" A 2>/dev/null | head -1)

    if [ "$SERVER_IP" = "$DOMAIN_IP" ]; then
      log "DNS verified. Running certbot..."

      if [ "$MULTISITE" = true ] && [ "$MULTISITE_TYPE" = "subdomain" ]; then
        warn "Subdomain multisite requires a wildcard SSL certificate (*.$SITE_DOMAIN)"
        warn "Wildcard certs require DNS validation. Install a certbot DNS plugin:"
        warn "  apt install python3-certbot-dns-cloudflare  # (or your DNS provider)"
        warn "Then run: certbot certonly --dns-cloudflare -d $SITE_DOMAIN -d '*.$SITE_DOMAIN'"
        warn "Installing cert for main domain only..."
        if certbot --nginx -d "$SITE_DOMAIN" --non-interactive --agree-tos \
            --email "$WP_ADMIN_EMAIL" --redirect; then
          log "SSL installed for main domain. Wildcard cert needed for subdomain sites."
        else
          warn "Certbot failed. Run manually: certbot --nginx -d $SITE_DOMAIN"
        fi
      else
        if certbot --nginx -d "$SITE_DOMAIN" --non-interactive --agree-tos \
            --email "$WP_ADMIN_EMAIL" --redirect; then
          log "SSL certificate installed!"
        else
          warn "Certbot failed. Run manually: certbot --nginx -d $SITE_DOMAIN"
        fi
      fi
    else
      warn "DNS not pointing here yet (expected $SERVER_IP, got $DOMAIN_IP)"
      if [ "$MULTISITE" = true ] && [ "$MULTISITE_TYPE" = "subdomain" ]; then
        warn "Run later: certbot certonly --dns-<provider> -d $SITE_DOMAIN -d '*.$SITE_DOMAIN'"
      else
        warn "Run later: certbot --nginx -d $SITE_DOMAIN"
      fi
    fi
  fi
fi

# ============================================================================
# Phase 6: Service User Permissions
# ============================================================================

if [ "$LOCAL_MODE" = true ]; then
  log "Phase 6: Local mode — skipping service user setup"
elif [ "$RUN_AS_ROOT" = false ]; then
  log "Phase 6: Configuring service user permissions..."

  if ! id -u "$SERVICE_USER" &>/dev/null || [ "$DRY_RUN" = true ]; then
    run_cmd useradd -m -s /bin/bash -G www-data "$SERVICE_USER"
  else
    log "User '$SERVICE_USER' already exists"
    run_cmd usermod -a -G www-data "$SERVICE_USER"
  fi

  run_cmd chmod -R g+w "$SITE_PATH"
  run_cmd chown -R www-data:www-data "$SITE_PATH"

  run_cmd mkdir -p "$CC_DATA_DIR"
  run_cmd chown -R "$SERVICE_USER:$SERVICE_USER" "$CC_DATA_DIR"
else
  log "Phase 6: Running as root (--root)"
  run_cmd mkdir -p "$CC_DATA_DIR"
fi

# ============================================================================
# Phase 7: Claude Code + CLAUDE.md
# ============================================================================

log "Phase 7: Configuring Claude Code..."

# Verify Claude Code is installed (already installed in Phase 1 on VPS)
if ! command -v claude &> /dev/null && [ "$DRY_RUN" = false ]; then
  error "Claude Code not found after installation. Check PATH."
fi

# Discover DM agent file paths for CLAUDE.md @ includes
DM_FILES=()
if [ "$INSTALL_DATA_MACHINE" = true ]; then
  if [ "$DRY_RUN" = false ] && [ -f "$SITE_PATH/wp-config.php" ]; then
    AGENT_FLAG=""
    if [ -n "$AGENT_SLUG" ]; then
      AGENT_FLAG="--agent=$AGENT_SLUG"
    fi
    DM_PATHS_RAW=$(wp_cmd datamachine agent paths --format=json $AGENT_FLAG 2>/dev/null || echo "")
    # SQLite translation layer may emit HTML error noise — extract only JSON
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
      log "Agent files discovered via 'wp datamachine agent paths${AGENT_FLAG:+ ($AGENT_FLAG)}'"
    fi
  else
    # Dry-run: use placeholder paths
    DM_DRY_SLUG="${AGENT_SLUG:-AGENT_SLUG}"
    DM_FILES=(
      "wp-content/uploads/datamachine-files/shared/SITE.md"
      "wp-content/uploads/datamachine-files/shared/RULES.md"
      "wp-content/uploads/datamachine-files/agents/${DM_DRY_SLUG}/SOUL.md"
      "wp-content/uploads/datamachine-files/users/1/USER.md"
      "wp-content/uploads/datamachine-files/agents/${DM_DRY_SLUG}/MEMORY.md"
    )
    log "Dry-run: using placeholder agent paths (slug: $DM_DRY_SLUG)"
  fi

  # Fallback: check filesystem if CLI discovery failed
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
      if [ -f "$SITE_PATH/$candidate" ]; then
        DM_FILES+=("$candidate")
      fi
    done
    log "Found ${#DM_FILES[@]} memory files on filesystem"
  fi
fi

# Generate CLAUDE.md (skip if already exists — may have been customized)
if [ "$DRY_RUN" = false ] && [ -f "$SITE_PATH/CLAUDE.md" ]; then
  log "CLAUDE.md already exists — skipping (delete to regenerate)"
else
  log "Generating CLAUDE.md..."

  TEMPLATE="$SCRIPT_DIR/workspace/CLAUDE.md.tmpl"
  if [ -f "$TEMPLATE" ]; then
    CLAUDE_MD=$(cat "$TEMPLATE")

    # Substitute placeholders
    CLAUDE_MD=$(echo "$CLAUDE_MD" | sed "s|{{SITE_DOMAIN}}|$SITE_DOMAIN|g")
    WP_CLI_DISPLAY="wp"
    if [ "$IS_STUDIO" = true ]; then
      WP_CLI_DISPLAY="studio wp"
    elif [ "$LOCAL_MODE" = false ]; then
      WP_CLI_DISPLAY="wp $WP_ROOT_FLAG --path=$SITE_PATH"
    fi
    CLAUDE_MD=$(echo "$CLAUDE_MD" | sed "s|{{WP_CLI_CMD}}|$WP_CLI_DISPLAY|g")

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

      # Remove per-file conditionals (we insert actual discovered paths instead)
      CLAUDE_MD=$(echo "$CLAUDE_MD" | sed '/{{IF_SITE_MD}}/,/{{END_IF_SITE_MD}}/d')
      CLAUDE_MD=$(echo "$CLAUDE_MD" | sed '/{{IF_RULES_MD}}/,/{{END_IF_RULES_MD}}/d')
      CLAUDE_MD=$(echo "$CLAUDE_MD" | sed '/{{IF_SOUL_MD}}/,/{{END_IF_SOUL_MD}}/d')
      CLAUDE_MD=$(echo "$CLAUDE_MD" | sed '/{{IF_USER_MD}}/,/{{END_IF_USER_MD}}/d')
      CLAUDE_MD=$(echo "$CLAUDE_MD" | sed '/{{IF_MEMORY_MD}}/,/{{END_IF_MEMORY_MD}}/d')

      # Build @ includes from discovered files
      AT_INCLUDES=""
      for dm_file in "${DM_FILES[@]}"; do
        AT_INCLUDES="${AT_INCLUDES}@${dm_file}\n"
      done

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

    # Clean up stacked empty lines from conditional removal
    CLAUDE_MD=$(echo "$CLAUDE_MD" | sed '/^$/N;/^\n$/d')

    write_file "$SITE_PATH/CLAUDE.md" "$CLAUDE_MD"
    log "Generated CLAUDE.md at $SITE_PATH/CLAUDE.md"
  else
    # Inline generation if template not found
    warn "Template not found at $TEMPLATE — generating inline"

    WP_CLI_DISPLAY="wp"
    if [ "$IS_STUDIO" = true ]; then
      WP_CLI_DISPLAY="studio wp"
    elif [ "$LOCAL_MODE" = false ]; then
      WP_CLI_DISPLAY="wp $WP_ROOT_FLAG --path=$SITE_PATH"
    fi

    CLAUDE_CONTENT="# $SITE_DOMAIN

WP-CLI: \`$WP_CLI_DISPLAY\`"

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

Discover DM paths: \`$WP_CLI_DISPLAY datamachine agent paths\`"
    else
      CLAUDE_CONTENT="$CLAUDE_CONTENT

Data Machine not installed."
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

    write_file "$SITE_PATH/CLAUDE.md" "$CLAUDE_CONTENT"
    log "Generated CLAUDE.md at $SITE_PATH/CLAUDE.md (inline)"
  fi
fi

# End of --skills-only guard (Phases 1-7)
fi

# ============================================================================
# Phase 8: Skills
# ============================================================================

SKILLS_DIR="$SITE_PATH/.claude/skills"

if [ "$INSTALL_SKILLS" = true ]; then
  log "Phase 8: Installing agent skills..."
  run_cmd mkdir -p "$SKILLS_DIR"

  install_skills_from_repo "https://github.com/WordPress/agent-skills.git" "WordPress agent skills"

  if [ "$INSTALL_DATA_MACHINE" = true ]; then
    install_skills_from_repo "https://github.com/Extra-Chill/data-machine-skills.git" "Data Machine skills"
  fi
else
  log "Phase 8: Skipping agent skills (--no-skills)"
fi

# --skills-only: done, exit early
if [ "$SKILLS_ONLY" = true ]; then
  echo ""
  log "Skills installed to $SKILLS_DIR/"
  if [ "$DRY_RUN" = false ]; then
    ls -1 "$SKILLS_DIR" 2>/dev/null | while read -r skill; do
      log "  - $skill"
    done
  fi
  exit 0
fi

# ============================================================================
# Phase 9: Chat Bridge
# ============================================================================

if [ "$INSTALL_CHAT" = true ]; then
  log "Phase 9: Installing chat bridge (cc-connect)..."

  if ! command -v cc-connect &> /dev/null || [ "$DRY_RUN" = true ]; then
    run_cmd npm install -g cc-connect
  else
    log "cc-connect already installed"
  fi

  if [ "$LOCAL_MODE" = true ] && [ "$PLATFORM" = "mac" ]; then
        # macOS: create a launchd plist for persistent service
        CC_PLIST_LABEL="com.extrachill.cc-connect"
        CC_PLIST_DIR="$HOME/Library/LaunchAgents"
        CC_PLIST="$CC_PLIST_DIR/$CC_PLIST_LABEL.plist"

        if [ "$DRY_RUN" = true ]; then
          CC_BIN="/opt/homebrew/bin/cc-connect"
        else
          CC_BIN=$(which cc-connect 2>/dev/null || echo "/opt/homebrew/bin/cc-connect")
        fi

        run_cmd mkdir -p "$CC_DATA_DIR"
        run_cmd mkdir -p "$CC_PLIST_DIR"

        # Generate config
        CC_CONFIG_FILE="$CC_DATA_DIR/config.toml"
        if [ "$DRY_RUN" = false ] && [ -f "$CC_CONFIG_FILE" ]; then
          log "cc-connect config already exists — skipping"
        else
          CC_CONFIG="# cc-connect configuration
# Generated by wp-claudecode setup

[project]
path = \"$SITE_PATH\"
agent = \"claude\"

[claude]
working_directory = \"$SITE_PATH\""

          write_file "$CC_CONFIG_FILE" "$CC_CONFIG"
          log "Generated cc-connect config at $CC_CONFIG_FILE"
        fi

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
    <string>$SITE_PATH</string>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>$CC_DATA_DIR/cc-connect.log</string>
    <key>StandardErrorPath</key>
    <string>$CC_DATA_DIR/cc-connect.error.log</string>
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin</string>
    </dict>
</dict>
</plist>"

        write_file "$CC_PLIST" "$CC_PLIST_CONTENT"

        if [ "$DRY_RUN" = false ]; then
          launchctl bootout "gui/$(id -u)" "$CC_PLIST" 2>/dev/null || true
          launchctl bootstrap "gui/$(id -u)" "$CC_PLIST"
          log "cc-connect launchd service installed and loaded"
        fi

        log "cc-connect service: $CC_PLIST_LABEL"
        log "  Start:  launchctl kickstart gui/$(id -u)/$CC_PLIST_LABEL"
        log "  Stop:   launchctl kill SIGTERM gui/$(id -u)/$CC_PLIST_LABEL"
        log "  Logs:   tail -f $CC_DATA_DIR/cc-connect.log"

      elif [ "$LOCAL_MODE" = true ]; then
        # Non-macOS local mode: no service manager
        run_cmd mkdir -p "$CC_DATA_DIR"
        CC_CONFIG_FILE="$CC_DATA_DIR/config.toml"
        if [ "$DRY_RUN" = false ] && [ ! -f "$CC_CONFIG_FILE" ]; then
          CC_CONFIG="# cc-connect configuration
[project]
path = \"$SITE_PATH\"
agent = \"claude\"

[claude]
working_directory = \"$SITE_PATH\""
          write_file "$CC_CONFIG_FILE" "$CC_CONFIG"
        fi
        log "Local mode: cc-connect installed. Run manually with:"
        log "  cd $SITE_PATH && cc-connect"
      else
        # VPS mode: systemd service
        run_cmd mkdir -p "$CC_DATA_DIR"

        CC_CONFIG_FILE="$CC_DATA_DIR/config.toml"
        if [ "$DRY_RUN" = false ] && [ ! -f "$CC_CONFIG_FILE" ]; then
          CC_CONFIG="# cc-connect configuration
[project]
path = \"$SITE_PATH\"
agent = \"claude\"

[claude]
working_directory = \"$SITE_PATH\""
          write_file "$CC_CONFIG_FILE" "$CC_CONFIG"
        fi

        # Build environment lines for systemd
        ENV_LINES="Environment=HOME=$SERVICE_HOME"
        ENV_LINES="$ENV_LINES\nEnvironment=PATH=/usr/local/bin:/usr/bin:/bin"

        if [ -n "${CC_CONNECT_TOKEN:-}" ]; then
          ENV_LINES="$ENV_LINES\nEnvironment=CC_CONNECT_TOKEN=$CC_CONNECT_TOKEN"
        fi

        if [ "$DRY_RUN" = true ]; then
          CC_BIN="/usr/bin/cc-connect"
        else
          CC_BIN=$(which cc-connect 2>/dev/null || echo "/usr/bin/cc-connect")
        fi

        SYSTEMD_CONFIG="[Unit]
Description=cc-connect Chat Bridge (wp-claudecode)
After=network.target

[Service]
Type=simple
User=$SERVICE_USER
WorkingDirectory=$SITE_PATH
$(echo -e "$ENV_LINES")
ExecStart=$CC_BIN
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target"

        write_file "/etc/systemd/system/cc-connect.service" "$SYSTEMD_CONFIG"
        run_cmd systemctl daemon-reload
        run_cmd systemctl enable cc-connect
      fi
else
  log "Phase 9: Skipping chat bridge (--no-chat)"
fi

# ============================================================================
# Done
# ============================================================================

echo ""
echo "=============================================="
if [ "$DRY_RUN" = true ]; then
  echo -e "${YELLOW}wp-claudecode dry-run complete!${NC}"
  echo "(No changes were made)"
else
  echo -e "${GREEN}wp-claudecode installation complete!${NC}"
fi
echo "=============================================="
echo ""
if [ "$LOCAL_MODE" = true ]; then
  echo "Platform:   Local ($OS)"
fi
echo "WordPress:"
echo "  URL:      https://$SITE_DOMAIN"
echo "  Admin:    https://$SITE_DOMAIN/wp-admin"
echo "  Path:     $SITE_PATH"
if [ "$IS_STUDIO" = true ]; then
  echo "  Runtime:  WordPress Studio"
fi
echo ""
echo "Claude Code:"
echo "  Config:   $SITE_PATH/CLAUDE.md"
echo ""
if [ "$MULTISITE" = true ]; then
  echo "Multisite:"
  echo "  Type:        $MULTISITE_TYPE"
  echo ""
fi
if [ "$INSTALL_DATA_MACHINE" = true ]; then
  echo "Data Machine:"
  if [ -n "$AGENT_SLUG" ]; then
    echo "  Agent:       $AGENT_SLUG"
  fi
  echo "  Files:       ${#DM_FILES[@]} memory files linked"
  echo "  Discover:    wp datamachine agent paths${AGENT_SLUG:+ --agent=$AGENT_SLUG} $WP_ROOT_FLAG"
  echo "  Code tools:  data-machine-code (workspace, GitHub, git)"
  echo "  Workspace:   $DM_WORKSPACE_DIR (created on first use)"
  echo ""
fi
echo "Agent:"
if [ "$LOCAL_MODE" = true ]; then
  echo "  User:     $(whoami) (local)"
elif [ "$RUN_AS_ROOT" = true ]; then
  echo "  User:     root"
else
  echo "  User:     $SERVICE_USER (non-root)"
fi
if [ "$INSTALL_CHAT" = true ]; then
  echo "  Bridge:   cc-connect"
fi
if [ "$INSTALL_SKILLS" = true ]; then
  echo "  Skills:   $SKILLS_DIR"
else
  echo "  Skills:   Skipped (--no-skills)"
fi
echo ""

# Save credentials (VPS only — local installs don't generate credentials)
if [ "$LOCAL_MODE" = false ]; then
  CREDENTIALS_CONTENT="# wp-claudecode credentials (keep this secure!)
# Generated: $(date)

SITE_DOMAIN=$SITE_DOMAIN
SITE_PATH=$SITE_PATH
WP_ADMIN_USER=$WP_ADMIN_USER
WP_ADMIN_PASS=$WP_ADMIN_PASS
DB_NAME=$DB_NAME
DB_USER=$DB_USER
DB_PASS=$DB_PASS
DATA_MACHINE=$INSTALL_DATA_MACHINE
AGENT_SLUG=$AGENT_SLUG
MULTISITE=$MULTISITE
MULTISITE_TYPE=$MULTISITE_TYPE
SERVICE_USER=$SERVICE_USER
CHAT_BRIDGE=cc-connect"

  CREDENTIALS_FILE="$SERVICE_HOME/.wp-claudecode-credentials"
  write_file "$CREDENTIALS_FILE" "$CREDENTIALS_CONTENT"
  run_cmd chmod 600 "$CREDENTIALS_FILE"
  log "Credentials saved to $CREDENTIALS_FILE"
fi

echo "=============================================="
echo "Next steps"
echo "=============================================="
echo ""
if [ "$LOCAL_MODE" = true ]; then
  if [ "$INSTALL_CHAT" = true ] && [ "$PLATFORM" = "mac" ]; then
    echo "  cc-connect (launchd service):"
    echo "    Start:  launchctl kickstart gui/$(id -u)/com.extrachill.cc-connect"
    echo "    Stop:   launchctl kill SIGTERM gui/$(id -u)/com.extrachill.cc-connect"
    echo "    Logs:   tail -f $CC_DATA_DIR/cc-connect.log"
    echo ""
  elif [ "$INSTALL_CHAT" = true ]; then
    echo "  Start your agent:"
    echo "    cd $SITE_PATH && cc-connect"
    echo ""
  fi
  echo "  Start Claude Code directly:"
  echo "    cd $SITE_PATH && claude"
  echo ""
  if [ "$INSTALL_DATA_MACHINE" = true ]; then
    echo "  Configure Data Machine:"
    echo "    - Set AI provider API keys in WP Admin > Data Machine > Settings"
    echo ""
  fi
elif [ "$INSTALL_CHAT" = true ]; then
  if [ -n "${CC_CONNECT_TOKEN:-}" ]; then
    echo "  Bot token configured via CC_CONNECT_TOKEN."
    echo "  Start the agent:  systemctl start cc-connect"
  else
    echo "  1. Configure cc-connect:"
    echo "     Edit $CC_DATA_DIR/config.toml with your chat platform credentials"
    echo ""
    echo "  2. Start the agent:  systemctl start cc-connect"
  fi
  echo ""
else
  echo "  No chat bridge installed. Run Claude Code directly:"
  echo "    cd $SITE_PATH && claude"
fi
echo ""
if [ "$LOCAL_MODE" = false ] && [ "$INSTALL_DATA_MACHINE" = true ]; then
  echo "  Configure Data Machine:"
  echo "    - Set AI provider API keys in WP Admin > Data Machine > Settings"
  echo "    - Or via WP-CLI: wp datamachine settings --allow-root"
  echo ""
fi
echo "  Claude Code will load CLAUDE.md automatically on first run."
if [ "$INSTALL_DATA_MACHINE" = true ] && [ ${#DM_FILES[@]} -gt 0 ]; then
  echo "  You'll be prompted to approve the @ includes for DM memory files."
fi
echo ""
