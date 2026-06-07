# Claude Code guidance

This repository's agent workflow, safety rules, and phase sequencing are documented in
**[AGENTS.md](AGENTS.md)** — the canonical, vendor-neutral guide. Read it before doing
any go-public work.

A Claude Code Agent Skill is also available at
[`.claude/skills/go-public/SKILL.md`](.claude/skills/go-public/SKILL.md). It activates on
go-public trigger phrases and defers to `AGENTS.md` for the full procedure.

Key reminders (full detail in `AGENTS.md`):

- `scripts/go-public` owns the gates — this guidance only sequences the work.
- Dry-run is the default; mutations require `--apply` / `--apply-history`; remote pushes
  require `publish --confirm`.
- Always scan full git history for secrets, and never claim credentials were rotated.
