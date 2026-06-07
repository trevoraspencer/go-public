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

Allow **keep** only when full history has been audited, no private material exists in history, commit history is valuable, and the user explicitly wants provenance.

Allow **squash** when the user wants a small number of thematic commits and source history is mostly clean (squash is deferred in v1 — use orphan or keep).

## Required workflow

Run phases in order. Each phase must produce report output and must not silently skip blockers.

### Phase 0: Release strategy

Goals: detect repo shape, recommend history strategy, record decision, prepare dry-run history tooling.

Deliverables: `docs/PUBLIC_RELEASE.md`, `scripts/go-public history --dry-run`, report phase 0.

Gate: strategy recorded, dirty tree warning emitted, no destructive action.

### Phase 1: Security and secrets (blocking)

Required checks:

- `gitleaks detect --source .` (with `.gitleaks.toml` if present)
- Full-history grep for high-confidence patterns (`ghp_`, `github_pat_`, `sk-`, `AKIA`, private keys, JWT-like blobs)
- `git ls-files` sensitive filename audit
- `.gitignore` coverage audit

Allowlist policy: test sentinels only (e.g. `sk-TEST-SENTINEL-*`); production allowlist normally empty.

Manual reminders: rotate all credentials; revoke uncertain tokens; never claim rotation is complete.

### Phase 2: Legal and licensing

Gate: LICENSE exists; dependency license audit has no unresolved blockers; manual legal checklist emitted.

### Phase 3: Repository hygiene

Remove internal artifacts (`.factory/`, `.cursor/plans/`, `notes/`, `scratch/`, private plans). Block on personal paths and donor denylist terms.

### Phase 4: Public documentation

README must be stranger-readable: install, configuration, usage, security, license. Block on unresolved placeholders (`<this-repo>`, `YOUR_ORG`, `CHANGE_ME`).

### Phase 5: Code, module, and CI readiness

Run stack adapters for test/lint/metadata. Warn if CI missing; block on test/metadata failures.

### Phase 6: GitHub settings checklist (manual)

Emit checklist only. Never mutate visibility.

### Phase 7: Create public history (destructive-adjacent)

- Dry-run by default
- `--apply-history` creates backup tag + local public branch
- `--publish --confirm` pushes (separate from `--apply`)

### Phase 8: Fresh-clone verification

Run `scripts/go-public verify-clone`. Gate: clone builds/tests; gitleaks passes; README quickstart viable.

### Phase 9: Post-public checklist (manual)

Emit checklist for tagging, release notes, issue triage, security reports.

## Status model

Each phase returns: `pass`, `warn`, `block`, `skip`, or `manual`.

`ready_to_publish` may only become true when phases 0–8 have no blockers, Phase 1 full-history scan passed, fresh-clone verification passed, backup tag exists if history rewrite is planned, and manual checklist is emitted.

## Agent behavior rules

1. Start with `scripts/go-public audit --dry-run`.
2. Do not edit files until the audit report identifies what should change.
3. Prefer small phase-specific branches (`cursor/phase1-security-secrets`, etc.).
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

# Security preflight
scripts/go-public preflight --dry-run

# Apply safe fixes
scripts/go-public fix --apply --phase 1
scripts/go-public fix --apply --phase 3

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

## Targeting another repository

When auditing a repo other than the tool installation:

```bash
GO_PUBLIC_ROOT=/path/to/target-repo scripts/go-public audit --dry-run
```

Adapters and policy load from the tool root; the target repo is specified via `GO_PUBLIC_ROOT`.
