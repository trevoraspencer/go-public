#!/usr/bin/env bash
node_pm() {
  if [[ -f pnpm-lock.yaml ]]; then
    echo pnpm
  elif [[ -f yarn.lock ]]; then
    echo yarn
  else
    echo npm
  fi
}

test() {
  local pm
  pm="$(node_pm)"
  case "$pm" in
    pnpm) pnpm install --frozen-lockfile && pnpm test ;;
    yarn) yarn install --frozen-lockfile && yarn test ;;
    npm) npm ci && npm test ;;
  esac
}

lint() {
  local pm
  pm="$(node_pm)"
  if jq -e '.scripts.lint' package.json >/dev/null 2>&1; then
    case "$pm" in
      pnpm) pnpm lint ;;
      yarn) yarn lint ;;
      npm) npm run lint ;;
    esac
  else
    echo "[node] No lint script"
  fi
}

license_audit() {
  if command -v license-checker >/dev/null 2>&1; then
    license-checker --summary
  else
    echo "[node] license-checker not installed; skipping detailed license audit"
  fi
  if [[ "$(node_pm)" == "npm" ]]; then
    npm audit --audit-level=high || true
  fi
}

module_metadata_check() {
  command -v jq >/dev/null 2>&1 || {
    echo "[node] jq required for package metadata check"
    return 1
  }
  local name private_flag repo
  name="$(jq -r '.name // empty' package.json)"
  private_flag="$(jq -r '.private // false' package.json)"
  repo="$(jq -r '.repository.url // .repository // empty' package.json)"
  [[ -n "$name" ]] || {
    echo "[node][blocker] package.json missing name" >&2
    return 1
  }
  if [[ "$private_flag" == "true" ]]; then
    echo "[node][warn] package.json has private:true. OK for app repos, blocker for publishable packages."
  fi
  if [[ "$repo" =~ YOUR_ORG|OWNER|REPO|example\.com ]]; then
    echo "[node][blocker] package repository field appears placeholder-like: $repo" >&2
    return 1
  fi
}
