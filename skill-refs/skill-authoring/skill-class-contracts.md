# Skill-class contracts

The core skill taxonomy (ADR-0006) has six governed classes. Each carries a positive membership contract — the markers, tier, and input/output obligations a skill of that class MUST satisfy. The data source of truth is `data/skill-class/contracts.yaml`; query it with `cog skill-class show --class <c>
--json` and verify a draft with `cog skill-class check --skill <path> --json`. `cog skill-lint`'s `skill-class-contract` rule enforces the union.

| Class         | Prefix          | Tier (prefix default)                     | Input → output                                                 |
| ------------- | --------------- | ----------------------------------------- | -------------------------------------------------------------- |
| `plan`        | `plan-*`        | high                                      | goal/orientation → plan in the structural plan/round contract  |
| `review`      | `review-*`      | review-oneshot high; else registry/exempt | diff/scope → shared structured-findings contract               |
| `review-plan` | `review-plan-*` | high                                      | plan/round → annotated plan-review verdict                     |
| `executor`    | `executor-*`    | medium                                    | one prompt/plan (`-ar <path>`) → canonical execution report    |
| `runner`      | `runner-*`      | low                                       | queue → verbatim prompt dispatch to a queue-blind subagent     |
| `bootstrap`   | `bootstrap-*`   | low                                       | project + operator intent → reconciled files via `cog *-apply` |

The `bootstrap-*` class covers the domain and language workers; the `bootstrap` orchestrator (no suffix) is the dispatcher, governed by the `input-fidelity` facet rule and carrying a context-brief gate pointer. A `bootstrap-*` worker that ships cog templates MUST run the template-refresh routine each run (`cog bootstrap-template-review check|stamp`); the `bootstrap-template-review` facet rule enforces this for every worker whose domain is a valid template-review domain (`bootstrap-rust` ships no cog templates and is exempt).

Cross-cutting prerequisites the class check composes (each stays owned by its own facet rule):

- **model/effort tier** — must resolve to the class's expected tier from `data/model-effort/{claude,codex}/tiers.yaml` (the registry's per-tier `skills` list is the single escape hatch).
- **prefix taxonomy** — a governed declared intent (plan-emitter, plan-reviewer, executor) must match the name's prefix class.
- **producer-blindness** — a consumer names only its structural input contract, never the producing skill.
- **input-fidelity** — a brief-building delegator at a fresh-context boundary carries the `<!-- cog-skill: input-fidelity -->` marker.
- **stage-agnostic identifiers** — artifact/field/flag names encode role, not stage.
- **bootstrap-template-review** — a `bootstrap-*` worker whose domain is a valid template-review domain references the template-refresh routine (`cog bootstrap-template-review`) so its cog templates stay freshness-tracked.
- **plan-quality principles** — a `plan`/`review-plan` skill's _output content_ (not just its wiring) follows `cog skill-refs path plan-rounds/plan-quality-principles.md`: concrete-over-abstract, machine-checkable acceptance criteria, requirement traceability, an end-to-end verification gate, explicit out-of-scope, and never-summarize-split-instead.

The plan-mode and context-brief gates are **not** composed facets: each is a short prose pointer in the orchestrator body to the shared source of truth (`cog skill-refs path orchestration/plan-mode-gate.md` and `orchestration/context-brief-gate.md`). Only `executor-*`/`runner-*` skills carry the plan-mode pointer; every fresh-context-boundary orchestrator carries the context-brief pointer and honors it with a real `cog context-brief build`/`validate` call.

The contract is data-backed, so adding or retiring a class prerequisite is a single edit to `data/skill-class/contracts.yaml` plus this reference.
