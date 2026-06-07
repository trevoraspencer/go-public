#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALLER="$ROOT/setup-go-public-skill.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

MANIFEST=(
  ".cursor/skills/go-public/SKILL.md"
  "scripts/go-public"
  "scripts/go-public-lib/common.sh"
  "scripts/go-public-lib/git.sh"
  "scripts/go-public-lib/report.sh"
  "scripts/go-public-lib/audit.sh"
  "scripts/go-public-lib/docs.sh"
  "scripts/go-public-lib/history.sh"
  "scripts/go-public-lib/verify_clone.sh"
  "adapters/generic.sh"
  "adapters/go.sh"
  "adapters/node.sh"
  "adapters/python.sh"
  "adapters/rust.sh"
  ".go-public.yaml"
  ".gitleaks.toml"
  "LICENSE"
  "README.md"
)

echo "== test_installer_byte_identical =="
bash "$INSTALLER" "$TMP"

for rel in "${MANIFEST[@]}"; do
  if ! diff -q "$ROOT/$rel" "$TMP/$rel" >/dev/null; then
    echo "Byte mismatch: $rel" >&2
    diff -u "$ROOT/$rel" "$TMP/$rel" >&2 || true
    exit 1
  fi
done

if [[ ! -x "$TMP/scripts/go-public" ]]; then
  echo "scripts/go-public is not executable" >&2
  exit 1
fi

echo "PASS (${#MANIFEST[@]} files byte-identical, orchestrator +x)"
