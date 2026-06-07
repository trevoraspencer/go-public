# Agent context handoff

Paste this into a **fresh agent chat** when you need design context or want to continue go-public work. It is **not** a substitute for the skill files themselves.

For an empty repo, use the installer instead:

```bash
bash setup-go-public-skill.sh
git add -A && git commit -m "Add go-public skill"
```

## Two different jobs

| Artifact | Purpose |
|----------|---------|
| **This handoff** (`docs/HANDOFF.md`) | Brief a new agent on architecture, safety rules, and where you left off |
| **Installer** (`setup-go-public-skill.sh`) | Write the actual skill + CLI files into a repo (byte-identical, no network) |

Do not paste the installer into chat — copy the file. Large base64 blocks truncate easily; a truncated installer is worse than none.

## Architecture (30-second version)

- **Skill** (`.cursor/skills/go-public/SKILL.md`) — agent workflow, judgment, phase sequencing
- **CLI** (`scripts/go-public`) — repeatable gates, dry-runs, JSON report, CI checks
- **Adapters** (`adapters/`) — stack-specific test/license hooks (generic, go, node, python, rust)
- **Policy** (`.go-public.yaml`, `.gitleaks.toml`) — denylist, gitignore requirements, allowlists

The skill is not the source of truth for gates. The script is.

## Safety rules (non-negotiable)

1. Dry-run is the default.
2. Never force-push without `publish --confirm`.
3. Never change GitHub visibility automatically.
4. Always scan **full git history**, not only the working tree.
5. Always create a backup tag before history rewrite.
6. Never claim the repo is safe to publish without running verification commands.
7. Credential rotation is always manual — never claim it was done.

## Default workflow

```bash
scripts/go-public audit --dry-run --report go-public-report.json
scripts/go-public preflight --dry-run
scripts/go-public fix --apply --phase 1    # safe remediations only
scripts/go-public history --dry-run --history-strategy orphan
scripts/go-public history --apply-history --history-strategy orphan
scripts/go-public verify-clone --public-branch public-main
scripts/go-public publish --confirm --public-branch public-main --target-branch main
```

Prefer **orphan** history unless full history is clean and the user wants provenance.

## Targeting another repository

```bash
GO_PUBLIC_ROOT=/path/to/target-repo scripts/go-public audit --dry-run
```

## Where to continue

When resuming work, tell the agent:

1. Which phase you completed (0–9)
2. Whether `go-public-report.json` exists and its `ready_to_publish` value
3. Whether history rewrite was applied locally or only dry-run
4. Any manual steps still open (credential rotation, legal review, GitHub settings)

## Regenerating the installer

After changing skill or script files:

```bash
scripts/build-installer.sh
tests/test_installer.sh
```
