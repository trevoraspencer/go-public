#!/usr/bin/env bash
# Phase audit implementations for go-public.

AUDIT_EXCLUDE_PATHS=()
SECRET_GREP_EXCLUDE_PATHS=()
PLACEHOLDER_EXCLUDE_PATHS=()
PERSONAL_PATH_EXCLUDE_PATHS=()

yaml_list_values() {
  local key="$1"
  [[ -f "$CONFIG_FILE" ]] || return 0
  awk -v key="$key" '
    $0 ~ "^" key ":" { found=1; next }
    found && /^[^[:space:]#-]/ { exit }
    found && /^[[:space:]]+- / {
      gsub(/^[[:space:]]+-[[:space:]]*/, "")
      gsub(/"/, "")
      print
    }
  ' "$CONFIG_FILE"
}

load_audit_policy() {
  local item
  AUDIT_EXCLUDE_PATHS=()
  SECRET_GREP_EXCLUDE_PATHS=()
  PLACEHOLDER_EXCLUDE_PATHS=()
  PERSONAL_PATH_EXCLUDE_PATHS=()

  while IFS= read -r item; do
    [[ -n "$item" ]] && AUDIT_EXCLUDE_PATHS+=("$item")
  done < <(yaml_list_values audit_exclude_paths)
  while IFS= read -r item; do
    [[ -n "$item" ]] && SECRET_GREP_EXCLUDE_PATHS+=("$item")
  done < <(yaml_list_values secret_grep_exclude_paths)
  while IFS= read -r item; do
    [[ -n "$item" ]] && PLACEHOLDER_EXCLUDE_PATHS+=("$item")
  done < <(yaml_list_values placeholder_exclude_paths)
  while IFS= read -r item; do
    [[ -n "$item" ]] && PERSONAL_PATH_EXCLUDE_PATHS+=("$item")
  done < <(yaml_list_values personal_path_exclude_paths)
}

is_excluded_path() {
  local file="$1"
  shift
  local prefix
  for prefix in "$@"; do
    [[ "$file" == "$prefix" || "$file" == "$prefix"* ]] && return 0
  done
  return 1
}

filtered_ls_files() {
  local file
  while IFS= read -r file; do
    is_excluded_path "$file" "${AUDIT_EXCLUDE_PATHS[@]}" || printf '%s\n' "$file"
  done < <(git ls-files)
}

git_grep_exclude_specs() {
  local prefix
  for prefix in "$@"; do
    printf ':(exclude)%s\n' "${prefix%/}/**"
  done
}

is_allowlisted_secret() {
  local match="$1"
  if [[ "$match" =~ sk-TEST-SENTINEL ]]; then
    return 0
  fi
  return 1
}

run_gitleaks() {
  if command -v gitleaks >/dev/null 2>&1; then
    if [[ -f "$PROJECT_ROOT/.gitleaks.toml" ]]; then
      gitleaks detect --source "$PROJECT_ROOT" --config "$PROJECT_ROOT/.gitleaks.toml" --redact
    else
      gitleaks detect --source "$PROJECT_ROOT" --redact
    fi
  else
    warn "gitleaks not installed; supplementary grep will run, but install gitleaks for final publish"
    return 0
  fi
}

audit_phase_0() {
  log "Phase 0: release strategy audit"
  phase_init "0"
  local commits authors remote
  commits="$(commit_count)"
  authors="$(author_count)"
  remote="$(remote_url)"
  log "Commits: $commits"
  log "Authors: $authors"
  log "Remote: ${remote:-none}"
  check_dirty_tree
  cd "$PROJECT_ROOT"
  if [[ -d .factory || -d .cursor/plans || -d notes || -d scratch ]]; then
    phase_add_warning "0" "Potential internal directories detected in working tree"
  fi
  log "Recommended strategy: $HISTORY_STRATEGY"
  phase_set_status "0" "pass"
}

audit_phase_1() {
  log "Phase 1: security and secrets audit"
  phase_init "1"
  cd "$PROJECT_ROOT"
  local phase_failed=0

  if ! run_gitleaks; then
    phase_add_blocker "1" "gitleaks found one or more findings"
    phase_failed=1
  fi

  log "Scanning full git history for high-confidence secret patterns"
  local patterns='ghp_[A-Za-z0-9_]{20,}|github_pat_[A-Za-z0-9_]{20,}|sk-[A-Za-z0-9_-]{20,}|AKIA[0-9A-Z]{16}|BEGIN (RSA |EC |OPENSSH |)?PRIVATE KEY|eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}'
  local grep_out="/tmp/go-public-secret-grep.txt"
  local exclude_specs=()
  mapfile -t exclude_specs < <(git_grep_exclude_specs "${SECRET_GREP_EXCLUDE_PATHS[@]}")
  : > "$grep_out"
  if git grep -I -n -E "$patterns" $(git rev-list --all) -- . \
      ':(exclude).git' \
      "${exclude_specs[@]}" >"$grep_out" 2>/dev/null; then
    local blocked=0
    while IFS= read -r line; do
      if is_allowlisted_secret "$line"; then
        warn "Allowlisted test sentinel in history: $line"
      else
        printf '%s\n' "$line" >&2
        blocked=1
      fi
    done < "$grep_out"
    if [[ "$blocked" -eq 1 ]]; then
      phase_add_blocker "1" "High-confidence secret-like patterns found in git history"
      phase_failed=1
    fi
  fi

  log "Auditing tracked sensitive filenames"
  local sensitive_out="/tmp/go-public-sensitive-files.txt"
  if filtered_ls_files | grep -Ei '(^|/)(\.env|secrets\.env|id_rsa|id_ed25519|.*\.pem|.*\.key|.*\.p12|.*\.pfx|.*\.log)$' >"$sensitive_out"; then
    cat "$sensitive_out" >&2
    phase_add_blocker "1" "Sensitive-looking files are tracked"
    phase_failed=1
  fi

  if [[ "$phase_failed" -eq 0 ]]; then
    log "Phase 1 passed"
    phase_set_status "1" "pass"
  fi
  return "$phase_failed"
}

audit_phase_2() {
  log "Phase 2: legal and licensing audit"
  phase_init "2"
  cd "$PROJECT_ROOT"
  if [[ ! -f LICENSE && ! -f LICENSE.md ]]; then
    phase_add_blocker "2" "Missing LICENSE"
    return 1
  fi
  local stack
  for stack in $(detect_stacks); do
    if ! run_adapter_func "$stack" license_audit; then
      phase_add_blocker "2" "License audit failed for stack: $stack"
    fi
  done
  if [[ ! -f SECURITY.md ]]; then
    phase_add_warning "2" "SECURITY.md missing; recommended for public repo"
  fi
  [[ "${PHASE_STATUS[2]:-pass}" != "block" ]] && phase_set_status "2" "pass"
}

audit_phase_3() {
  log "Phase 3: repository hygiene audit"
  phase_init "3"
  cd "$PROJECT_ROOT"
  local internal_regex='(^|/)(\.factory|\.cursor/plans|notes|scratch|tmp|TODO_private\.md|IMPLEMENTATION_PLAN\.md|LIVE_E2E_PLAN\.md)(/|$)'
  local internal_out="/tmp/go-public-internal-files.txt"
  if filtered_ls_files | grep -E "$internal_regex" >"$internal_out"; then
    cat "$internal_out" >&2
    phase_add_blocker "3" "Internal artifacts remain tracked"
    return 1
  fi
  local paths_out="/tmp/go-public-personal-paths.txt"
  : > "$paths_out"
  if git grep -I -n -E '/Users/|/home/[A-Za-z0-9._-]+|C:\\Users\\' -- . >"$paths_out" 2>/dev/null; then
    local blocked=0 line path
    while IFS= read -r line; do
      path="${line%%:*}"
      if is_excluded_path "$path" "${PERSONAL_PATH_EXCLUDE_PATHS[@]}"; then
        continue
      fi
      printf '%s\n' "$line" >&2
      blocked=1
    done < "$paths_out"
    if [[ "$blocked" -eq 1 ]]; then
      phase_add_blocker "3" "Personal or machine-specific paths found"
      return 1
    fi
  fi
  log "Large blobs in history, top 20:"
  git rev-list --objects --all 2>/dev/null |
    git cat-file --batch-check='%(objecttype) %(objectname) %(objectsize) %(rest)' 2>/dev/null |
    awk '$1 == "blob" {print $3, $4}' |
    sort -nr |
    head -20 || true
  phase_set_status "3" "pass"
}

audit_phase_4() {
  log "Phase 4: public documentation audit"
  phase_init "4"
  cd "$PROJECT_ROOT"
  if [[ ! -f README.md ]]; then
    phase_add_blocker "4" "Missing README.md"
    return 1
  fi
  if ! grep -Eiq '^# ' README.md; then
    phase_add_blocker "4" "README.md missing top-level heading"
    return 1
  fi
  local required_terms=(
    "install"
    "configuration|config"
    "usage|run"
    "license"
  )
  local term
  for term in "${required_terms[@]}"; do
    if ! grep -Eiq "$term" README.md; then
      phase_add_warning "4" "README.md may be missing section matching: $term"
    fi
  done
  local placeholder_out="/tmp/go-public-placeholders.txt"
  : > "$placeholder_out"
  if git grep -I -n -E '<this-repo>|YOUR_ORG|TODO_PUBLIC|INSERT_|CHANGE_ME' -- \
      '*.md' '*.yaml' '*.yml' '*.json' >"$placeholder_out" 2>/dev/null; then
    local blocked=0 line path
    while IFS= read -r line; do
      path="${line%%:*}"
      if is_excluded_path "$path" "${PLACEHOLDER_EXCLUDE_PATHS[@]}"; then
        continue
      fi
      printf '%s\n' "$line" >&2
      blocked=1
    done < "$placeholder_out"
    if [[ "$blocked" -eq 1 ]]; then
      phase_add_blocker "4" "Public documentation contains unresolved placeholders"
      return 1
    fi
  fi
  # Broken relative markdown links
  local link
  while IFS= read -r link; do
    local target="${link#*(}"
    target="${target%)*}"
    target="${target%%#*}"
    [[ -z "$target" || "$target" =~ ^https?:// ]] && continue
    if [[ ! -f "$target" && ! -f "${target%.md}.md" ]]; then
      phase_add_warning "4" "Possible broken relative link: $link -> $target"
    fi
  done < <(grep -oE '\[[^]]+\]\([^)]+\)' README.md 2>/dev/null || true)
  [[ "${PHASE_STATUS[4]:-pass}" != "block" ]] && phase_set_status "4" "pass"
}

audit_phase_5() {
  log "Phase 5: code, module, and CI readiness"
  phase_init "5"
  cd "$PROJECT_ROOT"
  local stack
  for stack in $(detect_stacks); do
    if ! run_adapter_func "$stack" module_metadata_check; then
      phase_add_blocker "5" "Module metadata check failed for stack: $stack"
    fi
    if ! run_adapter_func "$stack" lint; then
      phase_add_warning "5" "Lint check failed or unavailable for stack: $stack"
    fi
    if ! run_adapter_func "$stack" test; then
      phase_add_blocker "5" "Tests failed for stack: $stack"
    fi
  done
  if [[ ! -d .github/workflows ]]; then
    phase_add_warning "5" "No GitHub Actions workflow found"
  fi
  [[ "${PHASE_STATUS[5]:-pass}" != "block" ]] && phase_set_status "5" "pass"
}

audit_phase_6() {
  log "Phase 6: GitHub repository settings checklist"
  phase_init "6"
  append_markdown_note "## GitHub settings checklist"
  append_markdown_note "- [ ] Description and topics"
  append_markdown_note "- [ ] Secret scanning"
  append_markdown_note "- [ ] Dependabot alerts"
  append_markdown_note "- [ ] Private vulnerability reporting"
  append_markdown_note "- [ ] Branch protection on main"
  append_markdown_note "- [ ] Required CI checks"
  append_markdown_note "- [ ] Issue and PR templates"
  append_markdown_note "- [ ] Disable unused wiki/projects"
  phase_mark_manual "6"
}

audit_phase_7() {
  log "Phase 7: public history preview"
  phase_init "7"
  case "$HISTORY_STRATEGY" in
    orphan|squash|keep) ;;
    *)
      phase_add_blocker "7" "Invalid history strategy: $HISTORY_STRATEGY"
      return 1
      ;;
  esac
  local backup_tag
  backup_tag="$(backup_tag_name)"
  log "Strategy: $HISTORY_STRATEGY"
  log "Public branch: $PUBLIC_BRANCH"
  log "Backup tag would be: $backup_tag"
  log "Apply requires: scripts/go-public history --apply-history"
  log "Publish requires: scripts/go-public publish --confirm"
  if git show-ref --verify --quiet "refs/heads/$PUBLIC_BRANCH"; then
    phase_add_warning "7" "Public branch $PUBLIC_BRANCH already exists locally"
  fi
  phase_set_status "7" "pass"
}

audit_phase_8() {
  log "Phase 8: fresh-clone verification"
  phase_init "8"
  phase_add_warning "8" "Run scripts/go-public verify-clone to complete fresh-clone verification"
  phase_mark_manual "8"
}

audit_phase_9() {
  log "Phase 9: post-public checklist"
  phase_init "9"
  append_markdown_note "## Post-public checklist"
  append_markdown_note "- [ ] Tag initial release"
  append_markdown_note "- [ ] Write release notes"
  append_markdown_note "- [ ] Monitor issues"
  append_markdown_note "- [ ] Triage security reports"
  phase_mark_manual "9"
}

run_audit_phases() {
  load_audit_policy
  write_report_stub
  local phases=(audit_phase_0 audit_phase_1 audit_phase_2 audit_phase_3 audit_phase_4 audit_phase_5 audit_phase_6 audit_phase_7 audit_phase_8 audit_phase_9)
  local i=0
  for fn in "${phases[@]}"; do
    if should_run_phase "$i"; then
      "$fn" || true
    else
      phase_mark_skip "$i"
    fi
    ((i++)) || true
  done
  finalize_report
  return "$AUDIT_EXIT_CODE"
}

run_preflight_phases() {
  load_audit_policy
  write_report_stub
  audit_phase_0 || true
  audit_phase_1 || true
  finalize_report
  return "$AUDIT_EXIT_CODE"
}
