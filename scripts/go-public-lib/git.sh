#!/usr/bin/env bash
# Git helpers for go-public.
# REPORT_DIRTY_TREE is consumed by report.sh (finalize_report).
# shellcheck disable=SC2034

is_dirty() {
  [[ -n "$(git status --porcelain)" ]]
}

check_dirty_tree() {
  if is_dirty; then
    if [[ "${ALLOW_DIRTY:-0}" -eq 1 ]]; then
      warn "Working tree has uncommitted changes (--allow-dirty set)"
      REPORT_DIRTY_TREE=1
    else
      warn "Working tree has uncommitted changes"
      REPORT_DIRTY_TREE=1
      phase_add_warning "0" "Working tree has uncommitted changes"
    fi
  else
    REPORT_DIRTY_TREE=0
  fi
}

backup_tag_name() {
  printf 'private-archive/%s' "$(date -u +%Y%m%d-%H%M%S)"
}

latest_backup_tag() {
  git tag --list 'private-archive/*' --sort=-creatordate | head -1 || true
}

remote_url() {
  git config --get remote.origin.url || true
}

commit_count() {
  git rev-list --count HEAD 2>/dev/null || echo "0"
}

author_count() {
  git shortlog -sne HEAD 2>/dev/null | wc -l | tr -d ' '
}
