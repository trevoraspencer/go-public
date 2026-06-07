#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOOL="$ROOT/scripts/go-public"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

copy_fixture() {
  local name="$1"
  rm -rf "${TMP:?}/$name"
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

test_fix_phase_1_only() {
  echo "== test_fix_phase_1_only =="
  copy_fixture messy-go-repo
  GO_PUBLIC_ROOT="$TMP/messy-go-repo" "$TOOL" fix --apply --phase 1
  grep -q '.factory/' .gitignore
  if [[ -f docs/PUBLIC_RELEASE.md ]]; then
    echo "PUBLIC_RELEASE.md should not be created for phase 1 only" >&2
    exit 1
  fi
  echo "PASS"
}

test_report_absolute_path() {
  echo "== test_report_absolute_path =="
  copy_fixture clean-go-repo
  GO_PUBLIC_ROOT="$TMP/clean-go-repo" "$TOOL" audit --dry-run --report "$TMP/abs-report.json"
  test -f "$TMP/abs-report.json"
  grep -q '"schema_version"' "$TMP/abs-report.json"
  echo "PASS"
}

test_cli_options_override_config() {
  echo "== test_cli_options_override_config =="
  copy_fixture clean-go-repo
  GO_PUBLIC_ROOT="$TMP/clean-go-repo" "$TOOL" audit --dry-run --phase 7 \
    --history-strategy keep \
    --public-branch cli-public \
    --target-branch cli-main \
    --report report.json
  grep -q '"strategy": "keep"' report.json
  grep -q '"public_branch": "cli-public"' report.json
  grep -q '"target_branch": "cli-main"' report.json
  echo "PASS"
}

test_adapter_functions_do_not_leak() {
  echo "== test_adapter_functions_do_not_leak =="
  local repo adapters
  repo="$TMP/adapter-leak-repo"
  adapters="$TMP/adapters"
  mkdir -p "$repo" "$adapters"
  cat >"$repo/go.mod" <<'EOF'
module github.com/example/adapter-leak-repo

go 1.22
EOF
  cat >"$repo/package.json" <<'EOF'
{"name":"adapter-leak-repo"}
EOF
  cat >"$adapters/go.sh" <<'EOF'
#!/usr/bin/env bash
module_metadata_check() { return 0; }
license_audit() { return 0; }
lint() { return 0; }
test() { printf 'go-test\n' >> "$GO_ADAPTER_TEST_COUNT"; return 0; }
EOF
  cat >"$adapters/node.sh" <<'EOF'
#!/usr/bin/env bash
module_metadata_check() { return 0; }
license_audit() { return 0; }
lint() { return 0; }
EOF
  cd "$repo"
  git init -q
  git config user.email "fixture@example.com"
  git config user.name "Fixture"
  git config commit.gpgsign false
  git add -A
  git commit -q -m "fixture initial"
  GO_ADAPTER_TEST_COUNT="$repo/test-count" GO_PUBLIC_ROOT="$repo" GO_PUBLIC_ADAPTERS_DIR="$adapters" "$TOOL" audit --dry-run --phase 5 --report report.json
  grep -q '"ci_readiness"' report.json
  if [[ "$(wc -l < "$repo/test-count")" != "1" ]]; then
    echo "Go adapter test function leaked into another adapter invocation" >&2
    exit 1
  fi
  echo "PASS"
}

test_messy_go_blocks
test_clean_go_passes
test_history_secret_blocks
test_fix_apply_gitignore
test_fix_phase_1_only
test_history_dry_run
test_report_absolute_path
test_cli_options_override_config
test_adapter_functions_do_not_leak
echo "All go-public tests passed"
