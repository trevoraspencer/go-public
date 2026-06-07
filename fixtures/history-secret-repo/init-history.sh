#!/usr/bin/env bash
# Creates git history with a removed secret for fixture testing.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"
git init -q
git config user.email "fixture@example.com"
git config user.name "Fixture"
printf 'ghp_removedSecretFromHistory1234567890ABCDE\n' > secrets.txt
git add -A
git commit -q -m "accidental secret commit"
git rm -f secrets.txt
git commit -q -m "remove secret file"
echo "History-secret fixture initialized"
