#!/usr/bin/env bash
# Public history creation (Phase 7).

run_history() {
  cd "$PROJECT_ROOT"
  load_audit_policy
  audit_phase_0 || true
  if [[ "${PHASE_STATUS[1]:-}" != "pass" ]]; then
    audit_phase_1 || true
  fi
  if [[ "${PHASE_STATUS[1]:-pass}" == "block" ]]; then
    die "Phase 1 security audit must pass before history operations"
  fi

  local backup_tag
  backup_tag="$(backup_tag_name)"

  if [[ "$APPLY_HISTORY" -ne 1 ]]; then
    log "Dry-run history preview"
    log "Would create backup tag: $backup_tag"
    log "Would create public branch: $PUBLIC_BRANCH"
    log "Would use strategy: $HISTORY_STRATEGY"
    git status --short
    git ls-files | wc -l | awk '{print "Tracked file count:", $1}'
    return 0
  fi

  if is_dirty && [[ "${ALLOW_DIRTY:-0}" -ne 1 ]]; then
    die "Refusing to create public history with dirty working tree (use --allow-dirty to override)"
  fi

  log "Creating backup tag: $backup_tag"
  git tag "$backup_tag"

  case "$HISTORY_STRATEGY" in
    orphan)
      log "Creating orphan branch: $PUBLIC_BRANCH"
      git switch --orphan "$PUBLIC_BRANCH"
      git add -A
      git commit -m "Initial public release"
      ;;
    keep)
      log "Creating branch $PUBLIC_BRANCH from current HEAD"
      git switch -c "$PUBLIC_BRANCH"
      ;;
    squash)
      die "squash strategy not implemented in v1; use orphan or keep"
      ;;
  esac

  local count
  count="$(git rev-list --count HEAD)"
  if [[ "$HISTORY_STRATEGY" == "orphan" && "$count" != "1" ]]; then
    die "Expected exactly one commit on orphan branch, found $count"
  fi
  log "Public history created locally"
  log "Backup tag: $backup_tag"
  log "Public branch: $PUBLIC_BRANCH"
  log "No push was performed"
}

run_publish() {
  [[ "$PUBLISH" -eq 1 && "$CONFIRM" -eq 1 ]] || die "publish requires --publish --confirm"
  cd "$PROJECT_ROOT"
  load_audit_policy
  [[ "$(git branch --show-current)" == "$PUBLIC_BRANCH" ]] || die "Checkout $PUBLIC_BRANCH before publishing"

  audit_phase_1 || true
  if [[ "${PHASE_STATUS[1]:-pass}" == "block" ]]; then
    die "Phase 1 security audit must pass before publish"
  fi

  local count
  count="$(git rev-list --count HEAD)"
  if [[ "$HISTORY_STRATEGY" == "orphan" && "$count" != "1" ]]; then
    die "Refusing publish: orphan strategy requires exactly one commit"
  fi

  log "About to publish:"
  git log --oneline --decorate -5
  git diff --stat "$TARGET_BRANCH..$PUBLIC_BRANCH" 2>/dev/null || true

  local latest_backup
  latest_backup="$(latest_backup_tag)"
  [[ -n "$latest_backup" ]] || die "No private-archive backup tag found"

  log "Pushing backup tag first: $latest_backup"
  git push origin "$latest_backup"
  log "Force pushing $PUBLIC_BRANCH to origin/$TARGET_BRANCH"
  git push origin "$PUBLIC_BRANCH:$TARGET_BRANCH" --force-with-lease
  log "Publish push complete. Repository visibility was not changed."
}
