#!/usr/bin/env bash
# shellcheck disable=SC2034
# Shared utilities for go-public.

VERSION="0.1.0"
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOL_ROOT="$(cd "$LIB_DIR/../.." && pwd)"

# Target repository under audit (override with GO_PUBLIC_ROOT)
if [[ -n "${GO_PUBLIC_ROOT:-}" ]]; then
  ROOT="$(cd "$GO_PUBLIC_ROOT" && pwd)"
else
  ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
fi
PROJECT_ROOT="$ROOT"
ADAPTERS_DIR="${GO_PUBLIC_ADAPTERS_DIR:-$TOOL_ROOT/adapters}"
CONFIG_FILE="${GO_PUBLIC_CONFIG:-$TOOL_ROOT/.go-public.yaml}"

# Defaults (overridden by config and CLI flags)
DRY_RUN=1
APPLY=0
APPLY_HISTORY=0
PUBLISH=0
CONFIRM=0
INTERACTIVE=0
SKIP_LIVE_E2E=0
ALLOW_DIRTY=0
HISTORY_STRATEGY="orphan"
HISTORY_COMMITS="1"
PUBLIC_BRANCH="public-main"
TARGET_BRANCH="main"
REPORT_PATH="go-public-report.json"
PHASE=""
FROM_PHASE=""
ONLY=""
COMMAND="audit"

log()  { printf '[go-public] %s\n' "$*" >&2; }
warn() { printf '[go-public][warn] %s\n' "$*" >&2; }
die()  { printf '[go-public][blocker] %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<'USAGE'
Usage:
  scripts/go-public <command> [options]

Commands:
  audit           Run read-only assessment across phases
  fix             Apply safe auto-remediations when --apply is set
  preflight       Run Phase 0 + Phase 1 gates
  history         Preview or create local public history
  verify-clone    Fresh-clone verification
  report          Regenerate report
  publish         Push backup tag and public branch only with --confirm

Options:
  --dry-run                 Default: read-only mode
  --apply                   Safe file mutations only
  --apply-history           Create local public branch (separate from --apply)
  --publish                 Enable publish path (requires --confirm)
  --confirm                 Confirm destructive publish push
  --interactive             Interactive prompts where supported
  --allow-dirty             Allow dirty tree with warning
  --phase N                 Run only phase N (0-9)
  --from-phase N            Run from phase N through 9
  --only LIST               Comma list: security,docs,history,...
  --history-strategy STR    orphan|squash|keep
  --history-commits N       Commits for squash strategy
  --public-branch NAME      Local public branch name
  --target-branch NAME      Remote target branch
  --new-repo                Flag for new-repo workflow
  --skip-live-e2e           Skip maintainer live e2e scripts
  --report PATH             Report output path
  -h, --help                Show help
USAGE
}

load_config() {
  [[ -f "$CONFIG_FILE" ]] || return 0
  local key val
  while IFS=': ' read -r key val; do
    key="$(echo "$key" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    val="$(echo "$val" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | sed 's/^"//;s/"$//')"
    case "$key" in
      strategy) HISTORY_STRATEGY="$val" ;;
      public_branch) PUBLIC_BRANCH="$val" ;;
      target_branch) TARGET_BRANCH="$val" ;;
    esac
  done < <(grep -E '^(strategy|public_branch|target_branch):' "$CONFIG_FILE" 2>/dev/null || true)
}

parse_args() {
  COMMAND="${1:-audit}"
  [[ $# -gt 0 ]] && shift

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dry-run) DRY_RUN=1; APPLY=0 ;;
      --apply) DRY_RUN=0; APPLY=1 ;;
      --apply-history) APPLY_HISTORY=1 ;;
      --publish) PUBLISH=1 ;;
      --confirm) CONFIRM=1 ;;
      --interactive) INTERACTIVE=1 ;;
      --allow-dirty) ALLOW_DIRTY=1 ;;
      --skip-live-e2e) SKIP_LIVE_E2E=1 ;;
      --new-repo) NEW_REPO=1 ;;
      --phase) PHASE="${2:?missing phase}"; shift ;;
      --from-phase) FROM_PHASE="${2:?missing phase}"; shift ;;
      --only) ONLY="${2:?missing list}"; shift ;;
      --history-strategy) HISTORY_STRATEGY="${2:?missing strategy}"; shift ;;
      --history-commits) HISTORY_COMMITS="${2:?missing count}"; shift ;;
      --public-branch) PUBLIC_BRANCH="${2:?missing branch}"; shift ;;
      --target-branch) TARGET_BRANCH="${2:?missing branch}"; shift ;;
      --report) REPORT_PATH="${2:?missing path}"; shift ;;
      -h|--help) usage; exit 0 ;;
      *) die "Unknown option: $1" ;;
    esac
    shift
  done
  load_config
}

phase_status_dir() {
  mkdir -p "$PROJECT_ROOT/.go-public"
}

append_markdown_note() {
  phase_status_dir
  printf '%s\n' "$*" >> "$PROJECT_ROOT/.go-public/notes.md"
}

detect_stacks() {
  local stacks=()
  cd "$PROJECT_ROOT" || die "cannot cd to $PROJECT_ROOT"
  [[ -f go.mod ]] && stacks+=("go")
  [[ -f package.json ]] && stacks+=("node")
  [[ -f pyproject.toml || -f requirements.txt || -f setup.py ]] && stacks+=("python")
  [[ -f Cargo.toml ]] && stacks+=("rust")
  if [[ ${#stacks[@]} -eq 0 ]]; then
    stacks+=("generic")
  fi
  printf '%s\n' "${stacks[@]}"
}

run_adapter_func() {
  local stack="$1"
  local func="$2"
  local adapter="$ADAPTERS_DIR/${stack}.sh"
  if [[ ! -f "$adapter" ]]; then
    adapter="$ADAPTERS_DIR/generic.sh"
  fi
  # shellcheck source=/dev/null
  source "$adapter"
  if declare -F "$func" >/dev/null 2>&1; then
    "$func"
  else
    warn "Adapter $adapter does not implement $func"
    return 0
  fi
}

check_tools() {
  command -v git >/dev/null || die "git is required"
}

should_run_phase() {
  local n="$1"
  if [[ -n "$PHASE" && "$PHASE" != "$n" ]]; then
    return 1
  fi
  if [[ -n "$FROM_PHASE" && "$n" -lt "$FROM_PHASE" ]]; then
    return 1
  fi
  if [[ -n "$ONLY" ]]; then
    case "$ONLY" in
      *security*) [[ "$n" == "1" ]] && return 0 ;;
      *docs*) [[ "$n" == "4" ]] && return 0 ;;
      *history*) [[ "$n" == "7" ]] && return 0 ;;
    esac
    return 1
  fi
  return 0
}

require_git_repo() {
  cd "$PROJECT_ROOT" || die "cannot cd to $PROJECT_ROOT"
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "Not inside a git repository"
}
