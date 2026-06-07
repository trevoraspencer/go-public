#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOOL="$ROOT/scripts/go-public"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

copy_fixture() {
  local name="$1"
  cp -R "$ROOT/fixtures/$name" "$TMP/$name"
  cd "$TMP/$name"
  git init -q
  git config user.email "fixture@example.com"
  git config user.name "Fixture"
  git config commit.gpgsign false
  git add -A
  git commit -q -m "fixture initial"
}

test_messy_go_blocks() {
  echo "== test_messy_go_blocks =="
  copy_fixture messy-go-repo
  if GO_PUBLIC_ROOT="$TMP/messy-go-repo" "$TOOL" audit --dry-run --report report.json; then
    echo "Expected messy-go-repo audit to fail" >&2
    exit 1
  fi
  grep -q '"ready_to_publish": false' report.json
  grep -q '"status": "block"' report.json
  echo "PASS"
}

test_clean_go_passes() {
  echo "== test_clean_go_passes =="
  copy_fixture clean-go-repo
  GO_PUBLIC_ROOT="$TMP/clean-go-repo" "$TOOL" audit --dry-run --report report.json
  grep -q '"ready_to_publish"' report.json
  echo "PASS"
}

test_history_secret_blocks() {
  echo "== test_history_secret_blocks =="
  cp -R "$ROOT/fixtures/history-secret-repo" "$TMP/history-secret-repo"
  cd "$TMP/history-secret-repo"
  bash init-history.sh
  if GO_PUBLIC_ROOT="$TMP/history-secret-repo" "$TOOL" audit --dry-run --report report.json; then
    echo "Expected history-secret-repo audit to fail" >&2
    exit 1
  fi
  grep -q '"status": "block"' report.json
  echo "PASS"
}

test_fix_apply_gitignore() {
  echo "== test_fix_apply_gitignore =="
  copy_fixture messy-go-repo
  GO_PUBLIC_ROOT="$TMP/messy-go-repo" "$TOOL" fix --apply
  grep -q '.factory/' .gitignore
  test -f docs/PUBLIC_RELEASE.md
  echo "PASS"
}

test_history_dry_run() {
  echo "== test_history_dry_run =="
  copy_fixture clean-go-repo
  GO_PUBLIC_ROOT="$TMP/clean-go-repo" "$TOOL" history --dry-run --history-strategy orphan
  echo "PASS"
}

test_messy_go_blocks
test_clean_go_passes
test_history_secret_blocks
test_fix_apply_gitignore
test_history_dry_run
echo "All go-public tests passed"
