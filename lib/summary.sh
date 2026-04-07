#!/bin/bash
# Summary: output, credentials, next steps

print_summary() {
  echo ""
  echo "=============================================="
  if [ "$DRY_RUN" = true ]; then
    echo -e "${YELLOW}wp-claude-code dry-run complete!${NC}"
    echo "(No changes were made)"
  else
    echo -e "${GREEN}wp-claude-code installation complete!${NC}"
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
    CREDENTIALS_CONTENT="# wp-claude-code credentials (keep this secure!)
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

    CREDENTIALS_FILE="$SERVICE_HOME/.wp-claude-code-credentials"
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
}
