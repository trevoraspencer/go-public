#!/usr/bin/env bash
# Documentation and safe fix helpers.

ensure_public_release_doc() {
  local dest="$PROJECT_ROOT/docs/PUBLIC_RELEASE.md"
  if [[ -f "$dest" ]]; then
    return 0
  fi
  mkdir -p "$PROJECT_ROOT/docs"
  cat >"$dest" <<EOF
# Public Release Plan

## Strategy

Selected strategy: $HISTORY_STRATEGY

This repository is being prepared for public release.

## Manual decisions

- [ ] Rewrite existing repository
- [ ] Publish to new repository
- [ ] Tag initial release
- [ ] Rotate credentials

## Gates

- [ ] Full-history secret audit
- [ ] Legal/license audit
- [ ] Artifact cleanup
- [ ] Docs audit
- [ ] CI/test pass
- [ ] Fresh-clone verification
EOF
  log "Created docs/PUBLIC_RELEASE.md"
}

apply_gitignore_rules() {
  touch "$PROJECT_ROOT/.gitignore"
  local rules=(
    ".env"
    ".env.*"
    "!.env.example"
    "!.env.*.example"
    "secrets.env"
    "*.pem"
    "*.key"
    "*.p12"
    "*.pfx"
    "*.log"
    ".factory/"
    ".cursor/plans/"
    "notes/"
    "scratch/"
    "tmp/"
  )
  local rule
  for rule in "${rules[@]}"; do
    grep -Fxq "$rule" "$PROJECT_ROOT/.gitignore" || printf '%s\n' "$rule" >> "$PROJECT_ROOT/.gitignore"
  done
  log "Updated .gitignore with public-release safety rules"
}

run_fix() {
  [[ "$APPLY" -eq 1 ]] || die "fix requires --apply"
  log "Applying safe remediations"
  ensure_public_release_doc
  apply_gitignore_rules
}
