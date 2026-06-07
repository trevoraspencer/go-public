#!/usr/bin/env bash
detect() {
  [[ -f Cargo.toml ]]
}

test() {
  cargo test
}

lint() {
  cargo fmt --check
  cargo clippy -- -D warnings
}

license_audit() {
  cargo metadata --format-version=1 >/tmp/go-public-cargo-metadata.json
  if command -v cargo-deny >/dev/null 2>&1; then
    cargo deny check licenses
  else
    echo "[rust] cargo-deny not installed; cargo metadata generated only"
  fi
}

module_metadata_check() {
  grep -Eq '^name\s*=' Cargo.toml || {
    echo "[rust][blocker] Cargo.toml missing package name" >&2
    return 1
  }
  grep -Eq '^license\s*=' Cargo.toml || {
    echo "[rust][warn] Cargo.toml missing package license field"
  }
}
