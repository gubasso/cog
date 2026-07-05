# ADR-0066: Bootstrap cargo-publish worker with script-local auth

## Context and Problem Statement

A "set up crate publishing the way we intend" request had no home. crates.io metadata belongs to
`bootstrap-rust`, task recipes to the taskrunner domain, and the release workflow to the CI domain —
yet nothing owned the publish judgment (auth mode, release tool, semver gating, readiness) or the
helper scripts and runbook. A hard operator directive also forbids any skill or `cog` verb from
reading or writing crates.io credentials.

## Considered Options

- Fold publishing into `bootstrap-rust`.
- Fold publishing into `bootstrap-taskrunner`.
- Add a `cog cargo-publish-auth` verb that owns the auth check.
- A dedicated conditional `bootstrap-cargo-publish` worker with the auth check living only in the
  deployed helper scripts.

## Decision Outcome

Chosen option: **a dedicated conditional `bootstrap-cargo-publish` worker with script-local auth** — a
Rust + publishing sibling of `bootstrap-rust` (not a `bootstrap-audit` domain, keeping the audit matrix
language-orthogonal). Deterministic mechanics live in `cog cargo-publish-detect|check|apply`
(`lib/functions/fn_cargo.sh`); no `cog` verb and no skill reads a credential. The crates.io auth check
is a deliberate exception inside the deployed `publish` script, which reports auth *configured* (never
valid) and prints remediation. Default tooling: release-plz + Trusted Publishing/OIDC +
`cargo-semver-checks` for lib crates; cargo-dist optional for CLI/app crates; the first publish is
manual.

## Consequences

- Good: clean ownership boundaries, zero credential surface in `cog` or skills, and the language-worker
  pattern generalizes to publishing.
- Bad: one documented exception to mechanics-in-`cog` (the script-local auth gate) that reviewers must
  recognize as intentional.

## Status

Implemented — `skills/claude/bootstrap-cargo-publish/SKILL.md`,
`lib/commands/cmd_cargo_publish_{detect,check,apply}.sh`, `lib/functions/fn_cargo.sh`,
`skill-refs/templates/cargo-publish/`, `skill-refs/rust/rust-publish-conventions.md`, the `low` tier
entry in `data/model-effort/claude/tiers.yaml`, and the `bootstrap` orchestrator wiring.
