#!/bin/bash
#
# wp-claude-code setup script
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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source all modules
for lib in common detect wordpress infrastructure data-machine claude-code skills chat-bridge summary; do
  source "$SCRIPT_DIR/lib/${lib}.sh"
done

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
wp-claude-code setup script

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

# ============================================================================
# Detect environment + resolve variables
# ============================================================================

detect_environment

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
  install_skills
  print_skills_summary
  exit 0
fi

# ============================================================================
# Phases 1-9
# ============================================================================

install_system_deps
setup_database
install_wordpress
setup_multisite
create_service_user
install_data_machine
create_dm_agent
setup_nginx
setup_ssl
setup_service_permissions
discover_dm_paths
generate_claude_md
install_skills
install_chat_bridge
print_summary
