#!/usr/bin/env bash
# JSON report generation for go-public.
# AUDIT_EXIT_CODE is consumed by audit.sh (run_audit_phases / run_preflight_phases).
# shellcheck disable=SC2034

REPORT_SCHEMA_VERSION="0.1"
declare -A PHASE_STATUS=()
declare -A PHASE_BLOCKERS=()
declare -A PHASE_WARNINGS=()
GLOBAL_BLOCKERS=()
GLOBAL_WARNINGS=()
AUDIT_EXIT_CODE=0

phase_init() {
  local n="$1"
  PHASE_STATUS["$n"]="pass"
  PHASE_BLOCKERS["$n"]=""
  PHASE_WARNINGS["$n"]=""
}

phase_set_status() {
  local n="$1"
  local status="$2"
  PHASE_STATUS["$n"]="$status"
}

phase_add_blocker() {
  local n="$1"
  local msg="$2"
  PHASE_BLOCKERS["$n"]+="${msg}|"
  PHASE_STATUS["$n"]="block"
  GLOBAL_BLOCKERS+=("$msg")
  AUDIT_EXIT_CODE=1
}

phase_add_warning() {
  local n="$1"
  local msg="$2"
  PHASE_WARNINGS["$n"]+="${msg}|"
  if [[ "${PHASE_STATUS[$n]:-pass}" == "pass" ]]; then
    PHASE_STATUS["$n"]="warn"
  fi
  GLOBAL_WARNINGS+=("$msg")
}

phase_mark_skip() {
  local n="$1"
  PHASE_STATUS["$n"]="skip"
}

phase_mark_manual() {
  local n="$1"
  PHASE_STATUS["$n"]="manual"
}

json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/}"
  printf '%s' "$s"
}

write_report_stub() {
  phase_status_dir
  : > "$PROJECT_ROOT/.go-public/phase-data.tmp"
  for i in $(seq 0 9); do
    phase_init "$i"
  done
  REPORT_DETECTED_STACKS="$(detect_stacks | tr '\n' ',' | sed 's/,$//')"
}

report_output_path() {
  if [[ "$REPORT_PATH" == /* ]]; then
    printf '%s' "$REPORT_PATH"
  else
    printf '%s/%s' "$PROJECT_ROOT" "$REPORT_PATH"
  fi
}

finalize_report() {
  local ready="false"
  local has_blocker=0
  for i in $(seq 0 8); do
    if [[ "${PHASE_STATUS[$i]:-pass}" == "block" ]]; then
      has_blocker=1
      break
    fi
  done
  if [[ "$has_blocker" -eq 0 && "${PHASE_STATUS[1]:-block}" != "block" ]]; then
    # Manual steps always remain; ready only when phases 0-8 pass/warn/manual without blockers
    local all_clear=1
    for i in $(seq 0 8); do
      case "${PHASE_STATUS[$i]:-pass}" in
        block) all_clear=0 ;;
      esac
    done
    [[ "$all_clear" -eq 1 ]] && ready="true"
  fi

  local repo_name remote
  remote="$(remote_url)"
  repo_name="$(basename -s .git "$remote" 2>/dev/null || basename "$PROJECT_ROOT")"

  {
    printf '{\n'
    printf '  "schema_version": "%s",\n' "$REPORT_SCHEMA_VERSION"
    printf '  "tool": "go-public",\n'
    printf '  "version": "%s",\n' "$VERSION"
    printf '  "repo": "%s",\n' "$(json_escape "$repo_name")"
    printf '  "remote_url": "%s",\n' "$(json_escape "$remote")"
    printf '  "timestamp": "%s",\n' "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    printf '  "strategy": "%s",\n' "$HISTORY_STRATEGY"
    printf '  "public_branch": "%s",\n' "$PUBLIC_BRANCH"
    printf '  "target_branch": "%s",\n' "$TARGET_BRANCH"
    local dirty_json="false"
    [[ "${REPORT_DIRTY_TREE:-0}" -eq 1 ]] && dirty_json="true"
    printf '  "dirty_tree": %s,\n' "$dirty_json"
    printf '  "detected_stacks": [%s],\n' "$(echo "$REPORT_DETECTED_STACKS" | sed 's/,/", "/g; s/^/"/; s/$/"/')"
    printf '  "phases": {\n'
    local first=1
    for i in $(seq 0 9); do
      [[ $first -eq 1 ]] || printf ',\n'
      first=0
      write_phase_json "$i"
    done
    printf '\n  },\n'
    write_string_array "blockers" "${GLOBAL_BLOCKERS[@]}"
    printf ',\n'
    write_string_array "warnings" "${GLOBAL_WARNINGS[@]}"
    printf ',\n'
    write_manual_steps
    printf ',\n'
    printf '  "ready_to_publish": %s,\n' "$ready"
    printf '  "publish_commands": [\n'
    printf '    "git push origin private-archive/YYYYMMDD-HHMMSS",\n'
    printf '    "scripts/go-public publish --confirm --public-branch %s --target-branch %s"\n' "$PUBLIC_BRANCH" "$TARGET_BRANCH"
    printf '  ]\n'
    printf '}\n'
  } > "$(report_output_path)"
  log "Report written: $REPORT_PATH"
}

write_phase_json() {
  local n="$1"
  local names=("release_strategy" "security_secrets" "legal_licensing" "repository_hygiene" "public_documentation" "ci_readiness" "github_settings" "public_history" "fresh_clone_verification" "post_public")
  printf '    "%s": {\n' "$n"
  printf '      "name": "%s",\n' "${names[$n]}"
  printf '      "status": "%s",\n' "${PHASE_STATUS[$n]:-pass}"
  printf '      "blockers": [%s],\n' "$(phase_blockers_json "$n")"
  printf '      "warnings": [%s],\n' "$(phase_warnings_json "$n")"
  write_phase_manual_steps "$n"
  write_phase_evidence "$n"
  printf '    }'
}

write_phase_manual_steps() {
  local n="$1"
  printf '      "manual_steps": ['
  case "$n" in
    0)
      printf '\n        "Confirm orphan strategy.",\n        "Confirm existing repo rewrite versus new public repo."\n      ]'
      ;;
    1)
      printf '\n        "Rotate all credentials that ever touched the repo."\n      ]'
      ;;
    6|9)
      printf '\n        "Complete emitted checklist in .go-public/notes.md."\n      ]'
      ;;
    8)
      printf '\n        "Run scripts/go-public verify-clone to complete this gate."\n      ]'
      ;;
    *)
      printf ']'
      ;;
  esac
  printf ',\n'
}

write_phase_evidence() {
  local n="$1"
  printf '      "evidence": {'
  case "$n" in
    0)
      printf '\n        "commit_count": %s,\n        "author_count": %s,\n        "tag_count": %s\n      }' \
        "$(commit_count)" "$(author_count)" "$(git tag -l 2>/dev/null | wc -l | tr -d ' ')"
      ;;
    1)
      local gitleaks_ran="false"
      command -v gitleaks >/dev/null 2>&1 && gitleaks_ran="true"
      printf '\n        "gitleaks_ran": %s,\n        "history_scan_ran": true,\n        "tracked_sensitive_file_audit_ran": true,\n        "gitignore_coverage_audit_ran": true\n      }' \
        "$gitleaks_ran"
      ;;
    *)
      printf '}'
      ;;
  esac
}

phase_blockers_json() {
  local n="$1"
  local data="${PHASE_BLOCKERS[$n]:-}"
  [[ -z "$data" ]] && return
  local IFS='|'
  local items=()
  read -ra items <<< "$data"
  local out=""
  for item in "${items[@]}"; do
    [[ -z "$item" ]] && continue
    [[ -n "$out" ]] && out+=", "
    out+="\"$(json_escape "$item")\""
  done
  printf '%s' "$out"
}

phase_warnings_json() {
  local n="$1"
  local data="${PHASE_WARNINGS[$n]:-}"
  [[ -z "$data" ]] && return
  local IFS='|'
  local items=()
  read -ra items <<< "$data"
  local out=""
  for item in "${items[@]}"; do
    [[ -z "$item" ]] && continue
    [[ -n "$out" ]] && out+=", "
    out+="\"$(json_escape "$item")\""
  done
  printf '%s' "$out"
}

write_string_array() {
  local key="$1"
  shift
  printf '  "%s": [' "$key"
  local first=1
  for item in "$@"; do
    [[ $first -eq 1 ]] || printf ','
    first=0
    printf '\n    "%s"' "$(json_escape "$item")"
  done
  if [[ $# -gt 0 ]]; then
    printf '\n  ]'
  else
    printf ']'
  fi
}

write_manual_steps() {
  printf '  "manual_steps": [\n'
  printf '    "Rotate all credentials that ever touched this repository.",\n'
  printf '    "Review LICENSE, NOTICE, and dependency license findings.",\n'
  printf '    "Manually configure GitHub repository settings before or after visibility change.",\n'
  printf '    "Manually flip repository visibility only after final confirmation."\n'
  printf '  ]'
}
