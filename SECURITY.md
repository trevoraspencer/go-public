# Security Policy

## Reporting a vulnerability

If you discover a security issue in go-public, please report it privately:

- Use GitHub's [private vulnerability reporting](https://docs.github.com/en/code-security/security-advisories/guidance-on-reporting-and-writing-information-about-vulnerabilities/privately-reporting-a-security-vulnerability)
  for this repository, or
- Open a minimal issue asking for a private channel — do **not** include
  exploit details, secrets, or affected paths in a public issue.

Please do not open a public issue that discloses the vulnerability before a fix
is available.

## Scope

go-public is local tooling that audits a repository before public release. It:

- Runs read-only by default; mutations require explicit `--apply`,
  `--apply-history`, or `publish --confirm`.
- Never changes GitHub repository visibility automatically.
- Never force-pushes without `publish --confirm`.
- Scans full git history, not only the working tree.

The most security-relevant surface is the secret-scanning logic
(`scripts/go-public-lib/audit.sh`, `verify_clone.sh`) and the allowlist
configuration (`.go-public.yaml`, `.gitleaks.toml`). A bug that causes a real
secret to be treated as allowlisted, or that skips history during a scan, is
considered high severity.

## Handling secrets in findings

This tool reports potential secrets it finds. When sharing reports or logs
externally, redact matched values. The bundled scanners run with redaction
enabled (`gitleaks --redact`), and the supplementary grep prints matched lines
to stderr for local review only.

## Credential rotation

Detecting a secret is not the same as remediating it. If a credential ever
touched the repository, rotate it. go-public never claims credentials were
rotated — that is always a manual step.
