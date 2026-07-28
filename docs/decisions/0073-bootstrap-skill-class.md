# ADR-0073: `bootstrap` governed skill class and template-review participation

## Context and Problem Statement

`bootstrap-*` skills form a coherent family (an orchestrator plus domain and conditional language workers) but were never a governed class: `classify_prefix` mapped them to `other`, they had no entry in `data/skill-class/contracts.yaml`, and no rule enforced their shared obligations. Separately, the `bootstrap-template-review` freshness tracker recognized only seven domains, so `bootstrap-cargo-publish` — which ships cog templates — was never freshness-tracked, and nothing required a template-shipping worker to run the refresh routine.

## Considered Options

- Leave `bootstrap-*` ungoverned and wire `cargo-publish` into template-review ad hoc.
- Formalize `bootstrap` as a governed class (peer of `plan`/`review`/`executor`/`runner`) with a template-review participation obligation enforced by skill-lint.
- Additionally create a `templates/rust/` tree so `bootstrap-rust` is freshness-tracked too.

## Decision Outcome

Chosen option: **formalize `bootstrap` as a governed class + enforce template-review participation.** `classify_prefix`/`prefix_default_tier` map `bootstrap-*` → class `bootstrap`, tier `low`; a `bootstrap` contract joins `data/skill-class/contracts.yaml` (plan-mode-gate forbidden, tier low, and a producer obligation that a template-shipping worker runs the refresh routine). A new blocking skill-lint rule `bootstrap-template-review` requires any `bootstrap-<domain>` worker whose domain is a valid template-review domain to reference the refresh routine; the rule is keyed off `cog::fn::bootstrap_review::valid_domain`, so adding a domain auto-requires the reference. `cargo-publish` is added to that allowlist and its worker now runs the routine (type `rust`). `bootstrap-rust` and the `bootstrap` orchestrator ship no cog templates and are exempt. No `templates/rust/` tree is created.

## Consequences

- Good: `bootstrap-*` is governed like every other class; template-shipping workers cannot silently drift their templates out of freshness tracking; the CLI allowlist and the lint rule stay in lockstep.
- Bad: the class/coverage rules are one more thing an author must satisfy; the `bootstrap` orchestrator (no suffix) stays `other`, governed by its existing context-brief/input-fidelity rules.

## Status

Implemented — refines ADR-0016; builds on ADR-0062 (orchestrator), ADR-0065 (language worker), ADR-0066 (cargo-publish worker), ADR-0061 (rundir). Enacted in `lib/functions/fn_skill.sh`, `lib/functions/fn_skill_class.sh`, `data/skill-class/contracts.yaml`, `lib/functions/fn_bootstrap_review.sh`, `lib/commands/cmd_skill_lint.sh`, and `skills/claude/bootstrap-cargo-publish/SKILL.md`.
