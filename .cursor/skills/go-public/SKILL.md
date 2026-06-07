---
name: go-public
description: >-
  Convert a private, messy repository into a public-ready open-source release.
  Use when the user says "go public", "open source this", "make this repo public",
  "orphan branch release", "clean this repo for GitHub public", or similar.
---

# Go Public Skill

## Purpose

Use this skill when converting a private, messy repository into a public-ready open-source repository, usually published as a single clean commit using an orphan-branch strategy.

The goal is to produce a repository that is safe, hygienic, documented for strangers, legally reviewable, CI-verified, and ready for explicit human-controlled publication.

**The skill is not the source of truth.** It tells the agent how to reason and sequence work. **`scripts/go-public` owns the gates.**

## Architecture

```
.cursor/skills/go-public/SKILL.md   # Agent workflow and safety rules
scripts/go-public                   # CLI orchestrator
scripts/go-public-lib/              # Phase logic, report, git helpers
adapters/                           # Stack-specific test/license hooks (generic, go, node, python, rust)
.go-public.yaml                     # Policy configuration
.gitleaks.toml                      # Secret scan allowlists
fixtures/                           # Test repositories
tests/                              # Meta-test harness
```

## Command model

```bash
scripts/go-public audit
scripts/go-public fix
scripts/go-public preflight
scripts/go-public history --dry-run
scripts/go-public history --apply-history
scripts/go-public verify-clone
scripts/go-public report
scripts/go-public publish --confirm
```

Global flags:

| Flag | Purpose |
|------|---------|
| `--dry-run` | Default: read-only mode |
| `--apply` | Safe file mutations only |
| `--apply-history` | Local branch/tag history construction (separate from `--apply`) |
| `--publish --confirm` | Only allowed publish path |
| `--phase 0-9` | Run a single phase |
| `--from-phase N` | Run from phase N through 9 |
| `--only security,docs` | Filter phases |
| `--history-strategy orphan\|squash\|keep` | History rewrite strategy |
| `--allow-dirty` | Continue with warning when tree is dirty |
| `--report path` | JSON report output path |

## Phase decision tree

```
Start
  |
  v
Is git tree clean?
  |-- no --> stop unless --allow-dirty, report warning
  |
  v
Detect stack(s)
  |
  v
Phase 0: choose history strategy
  |-- secrets ever likely exposed? internal history messy? --> orphan recommended
  |-- clean intentional history? --> keep allowed
  |-- wants multiple public commits? --> squash N (deferred in v1)
  |
  v
Phase 1: full-history secret audit
  |-- findings outside documented allowlist --> blocker
  |
  v
Phase 2: legal/license audit
  |-- missing LICENSE or incompatible deps --> blocker/manual review
  |
  v
Phase 3: hygiene cleanup
  |-- internal files remain tracked --> blocker
  |
  v
Phase 4: docs stranger-readiness
  |-- README quickstart incomplete/broken links/placeholders --> blocker/warning
  |
  v
Phase 5: stack tests + CI
  |-- build/test/lint fail --> blocker
  |
  v
Phase 6: GitHub settings checklist
  |-- never mutate visibility automatically
  |
  v
Phase 7: public history creation
  |-- dry-run by default; APPLY_HISTORY creates local public branch + backup tag
  |
  v
Phase 8: fresh clone verification
  |-- clone/test/smoke/gitleaks fail --> blocker
  |
  v
Phase 9: post-public checklist
```

## Trigger phrases

- "go public"
- "open source this"
- "make this repo public"
- "private repo to public repo"
- "single commit public release"
- "orphan branch release"
- "clean this repo for GitHub public"
- "prepare this private repo for open source"

## Non-negotiable safety rules

1. Dry-run is the default.
2. Never force-push without `--publish --confirm`.
3. Never change GitHub visibility automatically unless the user explicitly requests a dedicated visibility command and confirms it.
4. Always scan full git history, not only the current working tree.
5. Always fail closed on secret findings outside documented test allowlists.
6. Always create a backup tag before creating or publishing rewritten history.
7. Always warn if the repo has uncommitted changes.
8. Always warn if the remote already appears public.
9. Never claim the repo is safe to publish unless verification commands have actually run.
10. Credential rotation is always a manual checklist item. Do not claim credentials were rotated.

## Default strategy

Prefer **orphan** history strategy unless there is a clear reason to preserve history.

Recommend orphan when:

- The repository has messy private commits.
- Internal docs, prompts, logs, or agent artifacts were committed.
- Secrets may have touched the repository at any point.
- The user wants a clean public launch.
- The repo is being positioned as a first public release.

Allow **keep** only when full history has been audited, no private material exists in history, commit history is valuable, and the user explicitly wants provenance.

Allow **squash** when the user wants a small number of thematic commits and source history is mostly clean (squash is deferred in v1 — use orphan or keep).

## Status model

Each phase returns: `pass`, `warn`, `block`, `skip`, or `manual`.

`ready_to_publish` may only become true when:

- Phases 0–8 have no blockers
- Phase 1 full-history scan passed
- Fresh-clone verification passed (run `verify-clone`, not audit alone)
- Backup tag exists if history rewrite is planned
- Manual checklist is emitted, not silently assumed complete

## Required workflow

Run phases in order. Each phase must produce report output and must not silently skip blockers.

### Phase 0: Release strategy (advisory, not mutating)

Goals: detect repo shape, recommend history strategy, record decision, prepare dry-run history tooling.

Checks: current branch, remote URL, commit/author counts, dirty tree, existing tags, internal directories (`.factory/`, `.cursor/plans/`, `notes/`, `scratch/`), large blobs, whether remote may already be public.

Deliverables: `docs/PUBLIC_RELEASE.md`, `scripts/go-public history --dry-run`, report phase 0.

Gate: strategy recorded, dirty tree warning emitted, no destructive action.

### Phase 1: Security and secrets (blocking — hardest gate)

A secret finding is a blocker unless it is a documented synthetic test sentinel. Do not allow vague "probably fine" handling.

Required checks:

- `gitleaks detect --source .` (with `.gitleaks.toml` if present)
- Full-history grep for high-confidence patterns (`ghp_`, `github_pat_`, `sk-`, `AKIA`, private keys, JWT-like blobs)
- `git ls-files` sensitive filename audit
- `.gitignore` coverage audit against `.go-public.yaml` `gitignore_required`
- Example env files contain placeholders only (not production-like values)

Allowlist policy: test sentinels only (e.g. `sk-TEST-SENTINEL-*`); production allowlist normally empty; every allowlist entry must include a reason.

Manual reminders: rotate all credentials; revoke uncertain OAuth tokens, PATs, deploy keys, cloud keys, and webhook secrets; never claim rotation is complete.

### Phase 2: Legal and licensing

Distinguish blockers from manual review:

- Missing LICENSE: blocker
- GPL dependency in distributed binary: blocker/manual review
- Missing SECURITY.md: warning
- Unknown copied code provenance: blocker until documented

Gate: LICENSE exists; dependency license audit has no unresolved blockers; manual legal checklist emitted.

### Phase 3: Repository hygiene

Remove internal artifacts and add prevention guards (`.gitignore`, donor denylist scans, personal path scans).

Block on: tracked internal paths, personal paths (`/Users/`, `/home/`, `C:\Users\`), donor denylist terms from `.go-public.yaml`.

Deliverables: cleanup diff, guard rules, report phase 3.

### Phase 4: Public documentation

Test docs like code. README requirements:

- One-line project description
- Status (alpha, beta, stable, experimental)
- Requirements, install, configuration, usage
- Verification or health check
- Security model
- License and contributing pointer
- No unresolved placeholders (`<this-repo>`, `YOUR_ORG`, `OWNER/REPO`, `CHANGE_ME`)

Deliverables: `README.md`, `CONTRIBUTING.md`, `CHANGELOG.md` (as applicable), report phase 4.

### Phase 5: Code, module, and CI readiness

Run stack adapters for test/lint/metadata. Stack checks:

- **Go**: `go test`, `go vet`, optional staticcheck, module path matches public import path
- **Node**: package manager test/lint, `private: true` warning, repository metadata
- **Python**: pytest/ruff if configured, pyproject metadata
- **Rust**: `cargo test`, `cargo clippy`, `cargo fmt --check`

Warn if CI missing; block on test/metadata failures. Default CI should be minimal — do not invent heavy CI.

### Phase 6: GitHub settings checklist (manual)

Emit checklist only. Never mutate visibility. Cover: description/topics, secret scanning, Dependabot, branch protection, required CI, issue/PR templates.

### Phase 7: Create public history (destructive-adjacent)

Separate permissions: `--apply` (safe edits), `--apply-history` (local branch), `--publish --confirm` (remote push).

- Dry-run by default
- `--apply-history` creates backup tag `private-archive/YYYYMMDD-HHMMSS` + local public branch
- Orphan strategy must produce exactly one commit
- `--publish --confirm` pushes backup tag first, then public branch

### Phase 8: Fresh-clone verification

Run `scripts/go-public verify-clone`. Simulates a stranger cloning the public branch: install, build/test, gitleaks, history secret scan.

Gate: clone builds/tests; gitleaks passes; README quickstart viable.

### Phase 9: Post-public checklist (manual)

Emit checklist for tagging, release notes, issue triage, security reports, dependency alerts.

## Agent behavior rules

1. Start with `scripts/go-public audit --dry-run`.
2. Do not edit files until the audit report identifies what should change.
3. Prefer small phase-specific branches:
   - `cursor/phase0-public-release-strategy`
   - `cursor/phase1-security-secrets`
   - `cursor/phase2-legal-licensing`
   - `cursor/phase3-artifact-cleanup`
   - `cursor/phase4-public-docs`
   - `cursor/phase5-ci-readiness`
4. After each phase, run the relevant gate command.
5. Keep changes idempotent.
6. Never remove ambiguous files without reviewing whether they are user-facing.
7. Use stack adapters rather than hardcoding one language.
8. Always update the report.
9. Prefer explicit TODO/manual checklist entries over pretending uncertain things are done.
10. End with exact next commands, not vague guidance.

## Preferred commands

```bash
# Initial assessment
scripts/go-public audit --dry-run --report go-public-report.json

# Security preflight (phases 0–1)
scripts/go-public preflight --dry-run

# Apply safe fixes
scripts/go-public fix --apply --phase 1
scripts/go-public fix --apply --phase 3
scripts/go-public fix --apply --phase 4

# Preview history rewrite
scripts/go-public history --dry-run --history-strategy orphan

# Create local public branch
scripts/go-public history --apply-history --history-strategy orphan

# Fresh-clone verification
scripts/go-public verify-clone --public-branch public-main

# Explicit publish
scripts/go-public publish --confirm --public-branch public-main --target-branch main
```

## Definition of done

The repository is only public-ready when:

- Full-history secret audit passes
- Current tracked-file audit passes
- Legal/license checklist has no unresolved blockers
- Internal artifacts are removed
- Public documentation is stranger-readable
- Stack tests pass
- CI exists and passes or is intentionally deferred with justification
- Public branch has the expected history shape
- Fresh-clone verification passes
- Manual steps are clearly listed
- `ready_to_publish` in the report is `true`

## v1 scope

**Must have:** audit, fix, preflight, history dry-run/apply-history, verify-clone, JSON report, generic/go/node/python/rust adapters, fixture tests.

**Defer:** GitHub API mutation, automatic issue labels, automatic release creation, full SPDX dependency graph, multi-commit squash, advanced README command replay.

## Targeting another repository

When auditing a repo other than the tool installation:

```bash
GO_PUBLIC_ROOT=/path/to/target-repo scripts/go-public audit --dry-run
```

Adapters and policy load from the tool root; the target repo is specified via `GO_PUBLIC_ROOT`.

## Distribution

Two artifacts serve different jobs:

| Artifact | Purpose |
|----------|---------|
| `docs/HANDOFF.md` | Context for a fresh agent chat — architecture, safety, resume point |
| `setup-go-public-skill.sh` | Self-contained installer that writes skill + CLI files into a repo |

Bootstrap an empty repo:

```bash
bash setup-go-public-skill.sh
git add -A && git commit -m "Add go-public skill"
```

The installer is base64-embedded for byte-perfect fidelity (no heredoc or quoting collisions). It performs no git, remote, or network operations. Regenerate after source changes with `scripts/build-installer.sh`; verify with `tests/test_installer.sh`.

Do not paste the installer into chat — copy the file. Truncated installers fail silently and are worse than none.
