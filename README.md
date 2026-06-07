# go-public

Portable tooling and a Cursor skill for converting a private repository into a public-ready open-source release.

The **skill** (`.cursor/skills/go-public/SKILL.md`) gives agents workflow discipline and judgment. The **script** (`scripts/go-public`) owns repeatable gates, dry-runs, reports, and CI-usable checks.

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
.cursor/skills/go-public/SKILL.md   # Agent workflow and safety rules
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
