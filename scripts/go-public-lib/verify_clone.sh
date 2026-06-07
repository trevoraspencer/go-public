#!/usr/bin/env bash
# Fresh-clone verification (Phase 8).

run_verify_clone() {
  cd "$PROJECT_ROOT"
  local tmp origin
  tmp="$(mktemp -d)"
  origin="$PROJECT_ROOT"
  log "Fresh-clone verification in $tmp"

  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git clone "$origin" "$tmp/repo" >/dev/null 2>&1 || git clone --no-hardlinks "$origin" "$tmp/repo" >/dev/null
  else
    die "verify-clone requires a git repository"
  fi

  cd "$tmp/repo"
  local saved_root="$PROJECT_ROOT"
  PROJECT_ROOT="$tmp/repo"
  export PROJECT_ROOT

  if git show-ref --verify --quiet "refs/heads/$PUBLIC_BRANCH"; then
    git checkout "$PUBLIC_BRANCH" >/dev/null 2>&1
  else
    warn "Public branch $PUBLIC_BRANCH not found; verifying current HEAD"
  fi

  local stack
  for stack in $(detect_stacks); do
    if ! run_adapter_func "$stack" test; then
      rm -rf "$tmp"
      die "Fresh clone test failed for $stack"
    fi
  done

  if command -v gitleaks >/dev/null 2>&1; then
    if [[ -f .gitleaks.toml ]]; then
      gitleaks detect --source . --config .gitleaks.toml --redact || {
        rm -rf "$tmp"
        die "gitleaks failed on fresh clone"
      }
    else
      gitleaks detect --source . --redact || {
        rm -rf "$tmp"
        die "gitleaks failed on fresh clone"
      }
    fi
  else
    warn "gitleaks not available during fresh-clone verification"
  fi

  PROJECT_ROOT="$saved_root"
  export PROJECT_ROOT
  rm -rf "$tmp"
  log "Fresh-clone verification passed"
  phase_init "8"
  phase_set_status "8" "pass"
}
