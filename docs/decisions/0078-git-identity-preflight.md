# ADR-0078: Deterministic git-identity preflight for identity-bearing bootstrap fields

## Context and Problem Statement

A `bootstrap-*` run wrote `authors = ["Gustavo Basso <gubasso@gmail.com>"]` into a project's
`Cargo.toml`, but that repo's commits are authored under a different email (`gu@gubasso.xyz`). Modern
`cargo init` omits `authors` and no cog template writes it, so the field was hand-authored by the model,
which guessed an email from session context instead of reading the repo's own git identity. Any
identity-bearing field a bootstrap skill writes (a `Cargo.toml` `authors` entry, a LICENSE copyright
holder) has the same failure mode when its value is left to model judgment.

## Considered Options

- Drop `authors` entirely (modern cargo/crates.io convention) and never write identity.
- Keep model-authored identity but add a prose reminder to read git config.
- Add a deterministic `cog` reader for the repo git identity, use it to populate identity-bearing
  fields, and fail closed with a step-by-step remediation when identity is unset.

## Decision Outcome

Chosen option: **deterministic reader + fail-closed preflight** — identity is a mechanic, not a
judgment, so it belongs in `cog`, not in prose. `cog git-identity check` resolves `user.name`/
`user.email` exactly as git resolves them (repo-local overriding global — the identity commits carry)
and exits non-zero when either is unset. A shared routine
(`skill-refs/bootstrap/git-identity-preflight.md`) owns the human-facing remediation wording; the helper
reports only facts. `bootstrap-rust` sources `Cargo.toml` `authors` from it, `bootstrap-repo` seeds the
LICENSE holder default from it, and the field is kept rather than dropped.

## Consequences

- Good: identity comes from a single deterministic source that matches the repo's commit identity; an
  unconfigured repo pauses with actionable steps instead of silently writing a wrong value.
- Good: reusable by any future identity-consuming bootstrap worker.
- Bad: one more preflight call and a possible pause on repos with no configured git identity.

## Status

Implemented. Enacted by `cog::fn::git_identity_json` (`lib/functions/fn_git.sh`),
`lib/commands/cmd_git_identity.sh`, `skill-refs/bootstrap/git-identity-preflight.md`, and the wiring in
`skills/claude/bootstrap-rust`, `bootstrap-repo`, and `bootstrap-cargo-publish`.
