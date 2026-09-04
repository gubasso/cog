# Skill-class contracts

The core skill taxonomy (ADR-0006) has five governed classes. Each carries a positive membership contract — the markers and input/output obligations a skill of that class MUST satisfy. The data source of truth is `data/skill-class/contracts.yaml`. Read that table for a class's contract, and verify a draft with `cog skill-lint <path>`, whose `skill-class-contract` rule enforces the union.

| Class         | Prefix          | Input → output                                                 |
| ------------- | --------------- | -------------------------------------------------------------- |
| `plan`        | `plan-*`        | goal/orientation → self-contained plan-doc                     |
| `review`      | `review-*`      | diff/scope → shared structured-findings contract               |
| `review-plan` | `review-plan-*` | plan → annotated plan-review delta                             |
| `executor`    | `executor-*`    | one prompt/plan (`-ar <path>`) → canonical execution report    |
| `bootstrap`   | `bootstrap-*`   | project + operator intent → reconciled files via `cog *-apply` |

| Class                                            | `plan-emitter` marker |
| ------------------------------------------------ | --------------------- |
| `plan`                                           | Required              |
| `review`, `review-plan`, `executor`, `bootstrap` | Forbidden             |

Reviews remain reviews. A plan-naming consumer retains the annotated delta and follows `cog skill-refs path plan-quality/plan-review-fold.md` before a plan-doc handoff. This contract governs Claude and Codex equally.

The `bootstrap-*` class covers the domain and language workers; the `bootstrap` orchestrator (no suffix) is the dispatcher, governed by the `input-fidelity` facet rule and carrying a context-brief gate pointer. A `bootstrap-*` worker that ships cog templates MUST run the domain-worker routine each run (`cog bootstrap-template-review check|stamp`), once per domain it owns; the `bootstrap-template-review` facet rule enforces this for every domain the worker owns. Ownership is a mapping, not the skill name: `bootstrap-lint` owns `editorconfig` and `precommit`, `bootstrap-rust` owns `cargo-publish`, every other worker owns the domain its name carries, and the `bootstrap` orchestrator owns none and is exempt.

Cross-cutting prerequisites the class check composes (each stays owned by its own facet rule):

- **prefix taxonomy** — a governed declared intent (plan-emitter, plan-reviewer, executor) must match the name's prefix class.
- **producer-blindness** — a consumer names only its structural input contract, never the producing skill.
- **input-fidelity** — a brief-building delegator at a fresh-context boundary carries the `<!-- cog-skill: input-fidelity -->` marker.
- **stage-agnostic identifiers** — artifact/field/flag names encode role, not stage.
- **bootstrap-template-review** — a `bootstrap-*` worker references the domain-worker routine (`cog bootstrap-template-review --domain <domain>`) once for each template-review domain it owns, so its cog templates stay freshness-tracked.
- **plan-quality principles** — a `plan`/`review-plan` skill's _output content_ (not just its wiring) follows `cog skill-refs path plan-quality/plan-quality-principles.md`: concrete-over-abstract, machine-checkable acceptance criteria, requirement traceability, an end-to-end verification gate, explicit out-of-scope, and never-summarize-split-instead.

The plan-mode and context-brief gates are **not** composed facets: each is a short prose pointer in the orchestrator body to the shared source of truth (`cog skill-refs path orchestration/plan-mode-gate.md` and `orchestration/context-brief-gate.md`). Only `executor-*` skills carry the plan-mode pointer; every fresh-context-boundary orchestrator carries the context-brief pointer and honors it with a real `cog context-brief build`/`validate` call.

The contract is data-backed, so adding or retiring a class prerequisite is a single edit to `data/skill-class/contracts.yaml` plus this reference.
