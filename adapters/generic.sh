#!/usr/bin/env bash
detect() {
  return 0
}

test() {
  if [[ -f Makefile ]] && grep -qE '^test:' Makefile; then
    make test
  else
    echo "[generic] No test command detected"
  fi
}

lint() {
  if [[ -f Makefile ]] && grep -qE '^lint:' Makefile; then
    make lint
  else
    echo "[generic] No lint command detected"
  fi
}

license_audit() {
  echo "[generic] No dependency license audit configured"
}

module_metadata_check() {
  echo "[generic] No module metadata check configured"
}
