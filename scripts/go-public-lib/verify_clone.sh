#!/usr/bin/env bash
# Fresh-clone verification (Phase 8).

run_verify_clone() {
  cd "$PROJECT_ROOT" || die "cannot cd to $PROJECT_ROOT"
  local tmp origin
  tmp="$(mktemp -d)"
  origin="$PROJECT_ROOT"
  log "Fresh-clone verification in $tmp"

  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git clone "$origin" "$tmp/repo" >/dev/null 2>&1 || git clone --no-hardlinks "$origin" "$tmp/repo" >/dev/null
  else
    die "verify-clone requires a git repository"
  fi

  cd "$tmp/repo" || die "cannot cd to clone at $tmp/repo"
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

  log "Scanning public branch history for high-confidence secret patterns"
  local patterns='ghp_[A-Za-z0-9_]{20,}|github_pat_[A-Za-z0-9_]{20,}|sk-[A-Za-z0-9_-]{20,}|AKIA[0-9A-Z]{16}|BEGIN (RSA |EC |OPENSSH |)?PRIVATE KEY|eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}'
  local grep_out revs=()
  grep_out="$(mktemp)"
  mapfile -t revs < <(git rev-list --all 2>/dev/null || true)
  if [[ "${#revs[@]}" -gt 0 ]] && git grep -I -n -E "$patterns" "${revs[@]}" -- . ':(exclude).git' >"$grep_out" 2>/dev/null; then
    local blocked=0 line
    while IFS= read -r line; do
      if is_allowlisted_secret "$line"; then
        warn "Allowlisted test sentinel in verify-clone history: $line"
      else
        printf '%s\n' "$line" >&2
        blocked=1
      fi
    done < "$grep_out"
    if [[ "$blocked" -eq 1 ]]; then
      rm -f "$grep_out"
      rm -rf "$tmp"
      die "High-confidence secret-like patterns found in fresh-clone history"
    fi
  fi
  rm -f "$grep_out"

  PROJECT_ROOT="$saved_root"
  export PROJECT_ROOT
  rm -rf "$tmp"
  log "Fresh-clone verification passed"
  phase_init "8"
  phase_set_status "8" "pass"
}
