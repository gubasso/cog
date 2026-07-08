# ADR-0072: cargo-dist first-class distribution and continuous-maintainership PUBLISHING.md

## Context and Problem Statement

The `bootstrap-cargo-publish` worker (ADR-0066) treated cargo-dist as a vague "optional" footnote and
shipped a `PUBLISHING.md` that mixed one-time first-publish setup (token, `cargo login`, configuring
the trusted publisher) into the durable runbook. Two latent hazards followed: the doc bloated an
in-repo file with one-time steps, and nothing stated that cargo-dist's generated `release.yml` is a
different file from the release-plz publish workflow — so a trusted publisher registered against
`release.yml` would silently reject every OIDC publish.

## Considered Options

- Leave cargo-dist as an optional aside and keep the mixed PUBLISHING.md.
- Make binary distribution first-class, trim PUBLISHING.md to continuous maintenance only, and codify
  the workflow-filename split.
- Also auto-generate AUR/OBS/Homebrew packaging pipelines.

## Decision Outcome

Chosen option: **first-class conditional cargo-dist + continuous-maintainership PUBLISHING.md + codified
filename split.** (1) Binary distribution via cargo-dist is a first-class conditional step for CLI/app
crates; it generates its own `.github/workflows/release.yml`, kept distinct from the release-plz
workflow `release-plz.yml`, and only `release-plz.yml` is registered with the crates.io Trusted
Publisher. AUR/OBS/Homebrew (beyond the generated tap) are documented downstream/manual channels, not
auto-generated. (2) In-repo `PUBLISHING.md` carries only continuous-maintainership content; the
one-time first-publish setup is a single pointer line. (3) Per ADR-0071, that pointer targets the
official crates.io Trusted Publishing docs, never a personal/external repo. (4) `cog` lays down
`dist-workspace.toml` only and never runs `dist`/publish — the operator runs `dist init`/`dist generate`.

## Consequences

- Good: no OIDC-breaking filename collision; lean in-repo docs; self-contained pointer; distribution is
  a legible conditional step.
- Bad: the `dist generate` → `release.yml` step stays a manual operator follow-up cog cannot verify.

## Status

Implemented — `skills/claude/bootstrap-cargo-publish/SKILL.md`,
`skill-refs/templates/cargo-publish/docs/PUBLISHING.md`, `skill-refs/rust/rust-publish-conventions.md`,
`skill-refs/release/release-workflow-conventions.md`. Refines ADR-0066; applies ADR-0071.
