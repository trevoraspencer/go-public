#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALLER="$ROOT/setup-go-public-skill.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Shared with scripts/build-installer.sh via scripts/installer-manifest.txt.
mapfile -t MANIFEST < "$ROOT/scripts/installer-manifest.txt"

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
