# ADR-0045: Unified `cog gate` Command and Context-Brief Verb Cleanup

> **Superseded by [ADR-0089](./0089-gates-as-skill-refs-references.md).** The `cog gate` stanza verbs (`render`/`check`/`stamp`/`list`) are retired; `cog gate` now hosts only the operator-approval gate (ADR-0074). Gate wording lives in `skill-refs/orchestration/`.

## Context and Problem Statement

The "prompt injection" surface — `cog` subcommands that emit canonical, marker-delimited stanzas stamped into `SKILL.md` files and drift-checked by `cog skill-lint` — grew per-concern. The plan-mode gate lived under `cog plan-mode-gate render` ([ADR-0037](./0037-plan-mode-gate-canonical-render.md)) and the context-brief gate under `cog context-brief gate render` ([ADR-0044](./0044-context-brief-gate.md)). Each new managed block would have added another top-level command plus its own near-identical lint branch. The concern, not the abstraction, was the noun.

Separately, `cog context-brief` was overloaded: it both **built a runtime artifact** (`scaffold`/`build`/`validate`) and **stamped a gate** (`gate render`) — two unrelated operations sharing one noun. The artifact verb `scaffold` also misnamed its behavior (it emits a fillable body template to stdout/a file; it does not materialize a filesystem scaffold), and the boolean `--json` flag was a one-off rather than a format selector.

The design was settled across two dual-engine (`/ask -wc`, Codex cross-checked) research rounds, which converged on the noun-verb conventions of clig.dev, `kubectl`/`gh`, and the `terraform fmt -check`/`prettier --check` render-plus-verify pattern.

## Considered Options

- Keep per-concern gate commands; add `cog context-brief gate render` and future `*-gate render` siblings (status quo; command sprawl, duplicated lint branches).
- Promote the abstraction to one noun `cog gate` parameterized by `--id`, with verbs `render | check | stamp | list`; retire the per-concern commands.
- Collapse `context-brief scaffold`+`build` into one assemble verb (rejected: a human/agent editing phase sits between them, unlike `helm template`).

## Decision Outcome

Chosen: **a unified `cog gate` noun and a cleaned-up `cog context-brief` artifact noun.**

### `cog gate` (managed canonical blocks)

- `cog gate render --id <plan-mode|context-brief> --skill <name>` — emit the stamped block to stdout. Output is byte-for-byte identical to the retired `cog plan-mode-gate render` and `cog context-brief gate render`.
- `cog gate check --id <id> --skill <name> --input <file> [--format text|json]` — report whether a file's stamped stanza matches the canonical render (drift). Exit non-zero on drift/missing.
- `cog gate stamp --id <id> --skill <name> --input <file>` — stamp or refresh the canonical block in a file in place (idempotent).
- `cog gate list [--format text|json]` — list the registered gate ids.

The single source of truth for each stanza's **wording** stays in `lib/functions/fn_skill.sh` (`cog::fn::skill::*_gate_*`); `lib/functions/fn_gate.sh` is a thin registry over those primitives, and both `cog gate` and `cog skill-lint` call the same functions, so the text cannot drift. Markers stay `<!-- cog-plan-mode-gate -->` and `<!-- cog-context-brief-gate -->` byte-for-byte (a BEGIN/END marker grammar is deferred — the `--id` parameterization already delivers the unified-noun win without re-stamping every skill).

### `cog context-brief` (runtime artifact builder)

- `scaffold` → **`template`** (`scaffold` kept as a deprecated alias for one release).
- `build` / `validate` gain `--format md|json` / `--format text|json`; `--json` kept as a deprecated alias for one release.
- `validate` (artifact completeness) stays deliberately distinct from gate's `check` (drift), mirroring `terraform validate` vs `terraform fmt -check` and `helm lint` vs `helm template`.
- The `gate render` subcommand is removed (moved to `cog gate`).

## Consequences

- One discoverable command family for every managed block; future gates are a registry row plus a canonical-text function, not a new top-level command or lint branch.
- This ADR supersedes the **command-surface** of [ADR-0037](./0037-plan-mode-gate-canonical-render.md) (`cog plan-mode-gate render` → `cog gate render --id plan-mode`) and [ADR-0044](./0044-context-brief-gate.md) (`cog context-brief gate render` → `cog gate render --id context-brief`); both ADRs' _rules_ (where gates live, dual enforcement) stand unchanged. It refines the artifact verbs of [ADR-0042](./0042-context-builder-shared-capability.md) (`scaffold` → `template`, `--json` → `--format`). Accepted ADRs are retained as historical record.
- `CLAUDE.md`, `AGENTS.md`, `docs/reference/cli-commands.md`, `docs/reference/skill-contract.md`, the completions, and the man page are updated to the new command strings. Skill prose that called `cog context-brief scaffold` now calls `cog context-brief template`; no skill prose invoked the retired gate-render commands (gates are stamped at authoring time, not at runtime).
