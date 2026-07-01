# ADR-0057: Plan-vault producer retarget and global git default

## Context and Problem Statement

[ADR-0048](0048-plan-vault-storage-and-resolution.md) built the plan vault, but producers still
hardcode `.implementation-plans/`, the global vault is created without git (so plans are not
trackable by default), and the `<slug>-<hash16>` project key has no collision guarantee — two repos
whose SHA-256 prefixes collide would share one key. Three deltas close these gaps.

## Considered Options

- Leave producers on `.implementation-plans/` and keep git opt-in.
- Retarget producers to vault-resolved paths, make the global vault git-by-default, and harden the
  project key with a collision-extend.
- Make every store (including local `.cog/plans`) git-by-default.

## Decision Outcome

Chosen option: **retarget producers + global git-by-default + collision-extend.**

- **D1 — Producer retarget.** Producers resolve and write only through `cog plan project resolve` /
  `cog plan new` / `cog plan path` (exposing `plan_root`/`plans_dir`/`queue_path`/`plan_dir`/
  `plan_slug`) and never hardcode `.implementation-plans/`.
- **D2 — Global git-by-default.** `cog plan store init` and any command that creates the global tree
  git-init the global store by default, with a `--no-git` opt-out. Local `.cog/plans` stays non-git
  (it lives inside the project's own repo).
- **D3 — Collision-extend.** When a `<slug>-<hash16>` key already exists for a *different* persisted
  `git_identity`, the SHA-256 prefix extends (18, 20, … up to 64 hex) until the key is unique or
  matches the same identity; the chosen key is persisted in `project.sh` so re-resolution is
  idempotent. Failing all 64 hex fails closed.

This **partially supersedes [ADR-0048](0048-plan-vault-storage-and-resolution.md)** for producer
paths, global git, and key collision, without changing XDG storage, trust gates, local/global tiers,
or resolution precedence.

## Consequences

- Good: plans are git-trackable by default; producers are path-agnostic and producer-blind; keys are
  collision-proof and stable across re-resolution and worktrees.
- Bad: new global-store runs gain a `.git/` they did not have before (`--no-git` opts out).

## Status

Implemented by [fn_plan_resolve.sh](../../lib/functions/fn_plan_resolve.sh),
[fn_plan_store.sh](../../lib/functions/fn_plan_store.sh), and [cmd_plan.sh](../../lib/commands/cmd_plan.sh).
