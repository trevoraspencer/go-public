#!/usr/bin/env bash
detect() {
  [[ -f go.mod ]]
}

test() {
  go test ./...
}

lint() {
  go vet ./...
  if command -v staticcheck >/dev/null 2>&1; then
    staticcheck ./...
  else
    echo "[go] staticcheck not installed; skipping optional check"
  fi
}

license_audit() {
  go list -m all >/tmp/go-public-go-modules.txt
  echo "[go] Wrote module list to /tmp/go-public-go-modules.txt"
  if command -v go-licenses >/dev/null 2>&1; then
    go-licenses report ./...
  else
    echo "[go] go-licenses not installed; module list generated only"
  fi
}

module_metadata_check() {
  local module
  module="$(go list -m)"
  echo "[go] module: $module"
  if [[ "$module" =~ ^example\.com/|^github\.com/YOUR_ORG/|^github\.com/OWNER/ ]]; then
    echo "[go][blocker] module path appears placeholder-like: $module" >&2
    return 1
  fi
}
