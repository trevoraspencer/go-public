# go-public

Portable, agent-agnostic tooling for converting a private repository into a public-ready open-source release.

The **agent guide** (`AGENTS.md`) gives coding agents workflow discipline and judgment. The **script** (`scripts/go-public`) owns repeatable gates, dry-runs, reports, and CI-usable checks.

## Supported agents

The workflow is maintained once, in the canonical [`AGENTS.md`](AGENTS.md), which is read natively by most coding agents. Agents with a different convention get a thin pointer file that defers to it — single source of truth, no drift.

| Agent | Entry point |
|-------|-------------|
| Codex | `AGENTS.md` |
| Cursor | `.cursor/rules/go-public.mdc` → `AGENTS.md` |
| Factory Droid | `AGENTS.md` |
| Grok build | `AGENTS.md` |
| Claude Code | `CLAUDE.md` + `.claude/skills/go-public/SKILL.md` → `AGENTS.md` |

Adding another agent means adding one pointer file that references `AGENTS.md` — never forking the workflow.

## Install into an empty repo

Drop `setup-go-public-skill.sh` into the repo root and run:

```bash
bash setup-go-public-skill.sh
git add -A && git commit -m "Add go-public tooling"
```

The installer embeds all operational files as base64 (byte-identical to this repo's sources), including the agent guides (`AGENTS.md`, `CLAUDE.md`, and the per-agent pointer files). It sets `+x` on `scripts/go-public` and touches nothing else — no git, remote, or network. Portable on Linux (`base64 -d`) and macOS (`base64 -D`).

**Handoff vs installer:** `docs/HANDOFF.md` is context for a fresh agent chat (design, safety, where you left off). The installer writes the actual files. Use both when bootstrapping: run the installer for repo contents, paste the handoff when continuing in a new session.

To regenerate the installer after editing sources:

```bash
scripts/build-installer.sh
tests/test_installer.sh
```

## Quick start

```bash
# Initial read-only assessment
scripts/go-public audit --dry-run --report go-public-report.json

# Security preflight (phases 0–1)
scripts/go-public preflight --dry-run

# Apply safe remediations (.gitignore, PUBLIC_RELEASE.md)
scripts/go-public fix --apply

# Preview orphan public history
scripts/go-public history --dry-run --history-strategy orphan

# Create local public branch (after gates pass)
scripts/go-public history --apply-history --history-strategy orphan

# Verify fresh clone
scripts/go-public verify-clone --public-branch public-main

# Explicit publish (never automatic)
scripts/go-public publish --confirm --public-branch public-main --target-branch main
```

## Architecture

```
AGENTS.md                           # Canonical agent workflow and safety rules
CLAUDE.md                           # Claude Code pointer to AGENTS.md
.claude/skills/go-public/SKILL.md   # Claude Code Agent Skill (defers to AGENTS.md)
.cursor/rules/go-public.mdc         # Cursor project rule (defers to AGENTS.md)
scripts/go-public                   # CLI orchestrator
scripts/go-public-lib/            # Phase logic, report, git helpers
adapters/                         # Stack-specific test/license hooks
.go-public.yaml                   # Policy configuration
.gitleaks.toml                    # Secret scan allowlists
fixtures/                         # Test repositories
tests/                            # Meta-test harness
```

## Commands

| Command | Purpose |
|---------|---------|
| `audit` | Read-only assessment across phases 0–9 |
| `preflight` | Phases 0–1 only (strategy + secrets) |
| `fix --apply` | Safe file mutations (.gitignore, release doc) |
| `history` | Dry-run or `--apply-history` local branch creation |
| `verify-clone` | Fresh-clone build/test/secret scan |
| `report` | Regenerate JSON report |
| `publish --confirm` | Push backup tag + public branch (explicit only) |

## Safety model

- **Dry-run is the default.** Mutations require `--apply` or `--apply-history`.
- **Never** changes GitHub visibility automatically.
- **Never** force-pushes without `publish --confirm`.
- **Always** scans full git history, not only the working tree.
- **Always** creates a backup tag before history rewrite.
- **Separate permissions:** `--apply` (safe edits), `--apply-history` (local branch), `publish --confirm` (remote push).

## Report schema

`go-public-report.json` uses `schema_version: "0.1"` with per-phase `status`, `blockers`, `warnings`, `manual_steps`, and `evidence`. `ready_to_publish` is only true when phases 0–8 have no blockers.

## Testing

```bash
tests/test_go_public_audit.sh
```

Fixtures include `messy-go-repo` (expected blockers), `clean-go-repo` (expected pass), and `history-secret-repo` (secret only in history).

## Targeting another repository

```bash
GO_PUBLIC_ROOT=/path/to/target-repo scripts/go-public audit --dry-run
```

## License

MIT — see [LICENSE](LICENSE).
