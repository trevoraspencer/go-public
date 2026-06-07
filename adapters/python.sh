#!/usr/bin/env bash
test() {
  if command -v pytest >/dev/null 2>&1; then
    pytest
  elif [[ -f Makefile ]] && grep -qE '^test:' Makefile; then
    make test
  else
    echo "[python] No pytest or make test detected"
  fi
}

lint() {
  if command -v ruff >/dev/null 2>&1; then
    ruff check .
  elif [[ -f Makefile ]] && grep -qE '^lint:' Makefile; then
    make lint
  else
    echo "[python] No lint command detected"
  fi
}

license_audit() {
  if command -v pip-licenses >/dev/null 2>&1; then
    pip-licenses
  else
    echo "[python] pip-licenses not installed; skipping detailed license audit"
  fi
  if command -v pip-audit >/dev/null 2>&1; then
    pip-audit || true
  fi
}

module_metadata_check() {
  if [[ -f pyproject.toml ]]; then
    grep -Eq 'name\s*=' pyproject.toml || {
      echo "[python][warn] pyproject.toml may be missing project name"
    }
  fi
}
