# Skill-class contracts

The core skill taxonomy (ADR-0016) has five governed classes. Each carries a
positive membership contract — the markers, plan-mode-gate requirement, tier, and
input/output obligations a skill of that class MUST satisfy. The data source of
truth is `data/skill-class/contracts.yaml`; query it with `cog skill-class show
--class <c> --json` and verify a draft with `cog skill-class check --skill <path>
--json`. `cog skill-lint`'s `skill-class-contract` rule enforces the union.

| Class | Prefix | Plan-mode gate | Tier (prefix default) | Input → output |
|-------|--------|----------------|-----------------------|----------------|
| `plan` | `plan-*` | forbidden | high | goal/orientation → plan in the structural plan/round contract |
| `review` | `review-*` | forbidden | review-oneshot high; else registry/exempt | diff/scope → shared structured-findings contract |
| `review-plan` | `review-plan-*` | forbidden | high | plan/round → annotated plan-review verdict |
| `executor` | `executor-*` | required | medium | one prompt/plan (`-ar <path>`) → canonical execution report |
| `runner` | `runner-*` | required | low | queue → verbatim prompt dispatch to a queue-blind subagent |

Cross-cutting prerequisites the class check composes (each stays owned by its own
facet rule):

- **plan-mode-gate** — only `executor-*`/`runner-*` carry `<!-- cog-plan-mode-gate -->`
  (canonical stanza from `cog gate render --id plan-mode`); every other class must not.
- **model/effort tier** — must resolve to the class's expected tier from
  `data/model-effort/{claude,codex}/tiers.yaml` (the registry's per-tier `skills`
  list is the single escape hatch).
- **prefix taxonomy** — a governed declared intent (plan-emitter, plan-reviewer,
  executor) must match the name's prefix class.
- **producer-blindness** — a consumer names only its structural input contract,
  never the producing skill.
- **input-fidelity / context-brief gate** — a brief-building delegator at a
  fresh-context boundary carries both markers and builds/validates a brief.
- **stage-agnostic identifiers** — artifact/field/flag names encode role, not stage.
- **plan-quality principles** — a `plan`/`review-plan` skill's *output content* (not just its
  wiring) follows `cog skill-refs path plan-rounds/plan-quality-principles.md`: concrete-over-abstract,
  machine-checkable acceptance criteria, requirement traceability, an end-to-end verification gate,
  explicit out-of-scope, and never-summarize-split-instead.

The contract is data-backed, so adding or retiring a class prerequisite is a
single edit to `data/skill-class/contracts.yaml` plus this reference.
