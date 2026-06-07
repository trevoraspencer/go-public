---
name: go-public
description: >-
  Convert a private, messy repository into a public-ready open-source release.
  Use when the user says "go public", "open source this", "make this repo public",
  "orphan branch release", "clean this repo for GitHub public", or similar.
---

# Go Public Skill

This skill is the Claude Code entry point for the go-public tooling. The full workflow,
phase decision tree, and required commands are maintained once, in the canonical
**[AGENTS.md](../../../AGENTS.md)** at the repository root. Read it before acting — this
file is a thin activator so the procedure never drifts across agents.

## When to use

Converting a private, messy repository into a public-ready open-source repository,
usually published as a single clean commit using an orphan-branch strategy. The goal is a
repository that is safe, hygienic, documented for strangers, legally reviewable,
CI-verified, and ready for explicit human-controlled publication.

**The skill is not the source of truth for gates.** `scripts/go-public` owns the gates,
dry-runs, reports, and CI checks.

## First command

```bash
scripts/go-public audit --dry-run --report go-public-report.json
```

Do not edit files until the audit identifies what should change. Then follow the phase
workflow in `AGENTS.md`.

## Non-negotiable safety rules

1. Dry-run is the default.
2. Never force-push without `publish --confirm`.
3. Never change GitHub visibility automatically.
4. Always scan full git history, not only the working tree.
5. Always fail closed on secret findings outside documented test allowlists.
6. Always create a backup tag before creating or publishing rewritten history.
7. Never claim the repo is safe to publish unless verification commands have actually run.
8. Credential rotation is always manual — never claim it was done.

For the command model, global flags, phase-by-phase gates, status model, and definition
of done, see **[AGENTS.md](../../../AGENTS.md)**.
