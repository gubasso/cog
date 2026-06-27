# ADR-0048: Plan Vault Storage and Resolution

## Context and Problem Statement

`.implementation-plans/` is project-local and legacy consumers hardcode that path. New plan workflows need a git-trackable user vault, an opt-in project-local vault, stable project identity, and a trust gate that keeps untrusted local configuration inert.

## Considered Options

- Keep only `.implementation-plans/`.
- Add a global XDG data vault only.
- Add a two-tier vault with trust-gated local resolution.

## Decision Outcome

Chosen option: **Add a two-tier vault with trust-gated local resolution** — it preserves the producer-blind inner queue shape while giving users a global default and a deliberate local override.

The default store is `${XDG_DATA_HOME:-$HOME/.local/share}/cog/plans`. Project-local stores live at `<repo>/.cog/plans` and are selected only after `cog plan trust` records a matching fingerprint in `${XDG_STATE_HOME:-$HOME/.local/state}/cog/trust/plans.json`. Project keys use `<slug>-<hash16>`, where the hash streams the `git-identity` through SHA-256 (the per-checkout realpath is recorded in `COG_PLAN_ROOTS`, not hashed), so worktrees of one repository and a moved repository coalesce to a single key. Resolution honors CLI flags, `COG_PLAN_*` env, project `.cog/config.sh`, user config, then the global default.

The inner tree remains:

```text
queue-plans.yaml
plans/<plan-slug>/README.md
plans/<plan-slug>/queue-rounds.yaml
plans/<plan-slug>/rounds/*.md
```

## Consequences

- Good: Global plans are available by default, local plans require explicit trust, and consumers can depend on one resolved queue shape.
- Bad: Local config or metadata edits can invalidate trust and require re-approval.

## Status

Implemented.

Implemented by [fn_plan_store.sh](../../lib/functions/fn_plan_store.sh), [fn_plan_config.sh](../../lib/functions/fn_plan_config.sh), [fn_plan_trust.sh](../../lib/functions/fn_plan_trust.sh), [fn_plan_resolve.sh](../../lib/functions/fn_plan_resolve.sh), and [cmd_plan.sh](../../lib/commands/cmd_plan.sh).
