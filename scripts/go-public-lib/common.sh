#!/usr/bin/env bash
# shellcheck disable=SC2034
# Shared utilities for go-public.

VERSION="0.1.0"
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOL_ROOT="$(cd "$LIB_DIR/../.." && pwd)"

# Target repository under audit (override with GO_PUBLIC_ROOT)
if [[ -n "${GO_PUBLIC_ROOT:-}" ]]; then
  PROJECT_ROOT="$(cd "$GO_PUBLIC_ROOT" && pwd)"
else
  PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
fi
ADAPTERS_DIR="${GO_PUBLIC_ADAPTERS_DIR:-$TOOL_ROOT/adapters}"
CONFIG_FILE="${GO_PUBLIC_CONFIG:-$TOOL_ROOT/.go-public.yaml}"

# High-confidence secret patterns and allowlist. These defaults are overridden
# by .go-public.yaml (secret_patterns / secret_allowlist) via load_secret_policy.
SECRET_PATTERN_REGEX='ghp_[A-Za-z0-9_]{20,}|github_pat_[A-Za-z0-9_]{20,}|sk-[A-Za-z0-9_-]{20,}|AKIA[0-9A-Z]{16}|BEGIN (RSA |EC |OPENSSH |)?PRIVATE KEY|eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}'
SECRET_ALLOWLIST_PATTERNS=("sk-TEST-SENTINEL")

# Defaults (overridden by config and CLI flags)
DRY_RUN=1
APPLY=0
APPLY_HISTORY=0
PUBLISH=0
CONFIRM=0
ALLOW_DIRTY=0
HISTORY_STRATEGY="orphan"
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
  --allow-dirty             Allow dirty tree with warning
  --phase N                 Run only phase N (0-9)
  --from-phase N            Run from phase N through 9
  --only LIST               Comma list of phase names: strategy,security,
                            legal,hygiene,docs,ci,github,history,verify,post
  --history-strategy STR    orphan|keep (squash deferred)
  --public-branch NAME      Local public branch name
  --target-branch NAME      Remote target branch
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

  # Load repository policy before parsing flags so explicit CLI options always
  # take precedence over defaults from .go-public.yaml.
  load_config

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dry-run) DRY_RUN=1; APPLY=0 ;;
      --apply) DRY_RUN=0; APPLY=1 ;;
      --apply-history) APPLY_HISTORY=1 ;;
      --publish) PUBLISH=1 ;;
      --confirm) CONFIRM=1 ;;
      --allow-dirty) ALLOW_DIRTY=1 ;;
      --phase) PHASE="${2:?missing phase}"; shift ;;
      --from-phase) FROM_PHASE="${2:?missing phase}"; shift ;;
      --only) ONLY="${2:?missing list}"; shift ;;
      --history-strategy) HISTORY_STRATEGY="${2:?missing strategy}"; shift ;;
      --public-branch) PUBLIC_BRANCH="${2:?missing branch}"; shift ;;
      --target-branch) TARGET_BRANCH="${2:?missing branch}"; shift ;;
      --report) REPORT_PATH="${2:?missing path}"; shift ;;
      -h|--help) usage; exit 0 ;;
      *) die "Unknown option: $1" ;;
    esac
    shift
  done
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
  (
    # Source adapters in a subshell so function definitions from one stack do
    # not leak into later adapter invocations.
    # shellcheck source=/dev/null
    source "$adapter"
    if declare -F "$func" >/dev/null 2>&1; then
      "$func"
    else
      warn "Adapter $adapter does not implement $func"
      return 0
    fi
  )
}

check_tools() {
  command -v git >/dev/null || die "git is required"
}

phase_name_for() {
  case "$1" in
    0) printf 'strategy' ;;
    1) printf 'security' ;;
    2) printf 'legal' ;;
    3) printf 'hygiene' ;;
    4) printf 'docs' ;;
    5) printf 'ci' ;;
    6) printf 'github' ;;
    7) printf 'history' ;;
    8) printf 'verify' ;;
    9) printf 'post' ;;
  esac
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
    case ",$ONLY," in
      *",$(phase_name_for "$n"),"*) return 0 ;;
      *) return 1 ;;
    esac
  fi
  return 0
}

require_git_repo() {
  cd "$PROJECT_ROOT" || die "cannot cd to $PROJECT_ROOT"
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "Not inside a git repository"
}
