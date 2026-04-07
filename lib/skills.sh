#!/bin/bash
# Skills: agent skill installation from git repos

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

install_skills() {
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
}

print_skills_summary() {
  echo ""
  log "Skills installed to $SKILLS_DIR/"
  if [ "$DRY_RUN" = false ]; then
    ls -1 "$SKILLS_DIR" 2>/dev/null | while read -r skill; do
      log "  - $skill"
    done
  fi
}
