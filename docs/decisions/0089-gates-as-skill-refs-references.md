# ADR-0089: Gates Delivered as skill-refs References; stamp+lint Retired

## Context and Problem Statement

The repository had two mechanisms for shared, cross-skill canonical text:

- a **skill-refs reference doc** resolved via `cog skill-refs path` (lean, DRY, one source of truth), and
- **stamp + lint** — a stanza rendered by `cog gate render` and stamped verbatim into skill bodies,
  drift-pinned by a `cog skill-lint` rule. Its only two residents were the `plan-mode-gate`
  ([ADR-0037](0037-plan-mode-gate-canonical-render.md)) and `context-brief-gate`
  ([ADR-0044](0044-context-brief-gate.md)) stanzas, rendered through the unified `cog gate` command
  ([ADR-0045](0045-unified-gate-command-and-context-brief-verbs.md)).

Maintaining two mechanisms for the same purpose is redundant. The decision (made with the maintainer,
who accepted the tradeoff) is to standardize on **skill-refs as the single mechanism** for shared
cross-skill text and retire stamp+lint entirely.

## Considered Options

- Keep both mechanisms, using skill-refs for consulted knowledge and stamp+lint for enforced guarantees.
- Retire stamp+lint and deliver both gates as skill-refs references.

## Decision Outcome

Chosen option: **retire stamp+lint; deliver both gates as skill-refs references.**

- The gate wording moves to `skill-refs/orchestration/plan-mode-gate.md` and
  `skill-refs/orchestration/context-brief-gate.md` (generic, no per-skill name interpolation).
- Each orchestrator carries a short in-body **pointer** that keeps the salient imperative (the plan-mode
  STOP; the pre-dispatch build/validate) in the always-loaded body and defers the full protocol to the
  doc via `cog skill-refs path`.
- The `cog skill-lint` `plan-mode-gate` and `context-brief-gate` rules are removed, the `plan_mode_gate`
  facet is dropped from `data/skill-class/contracts.yaml` and the `skill-class-contract` composition,
  and the dead gate helpers in `fn_skill.sh` are deleted.
- The `cog gate` **stanza** verbs (`render`/`check`/`stamp`/`list`) and `fn_gate.sh` are deleted. The
  `cog gate` command is retained for the **operator-approval gate** (`approve`/`check-approval`/
  `prune-approvals`, [ADR-0074](0074-forge-resistant-approval-gate.md)), which is unrelated.

## Consequences

- Good: one mechanism for shared cross-skill text; leaner command surface; no stamp/drift ceremony.
- Bad (accepted tradeoff): the two gate lint rules were the only structural guarantee that every
  orchestrator carries the guard, that its wording has not drifted, and that context-brief orchestrators
  actually call `cog context-brief build|validate`. These become prose conventions, not enforced
  invariants. Salience of the plan-mode STOP is preserved by keeping the imperative inline in the
  pointer.
- The decision rule for future skills: use a skill-refs reference for *knowledge a skill applies*; the
  stamp+lint pattern is retired and not to be reintroduced.

## Status

Implemented. **Supersedes [ADR-0037](0037-plan-mode-gate-canonical-render.md),
[ADR-0044](0044-context-brief-gate.md), and
[ADR-0045](0045-unified-gate-command-and-context-brief-verbs.md).** The operator-approval gate
([ADR-0074](0074-forge-resistant-approval-gate.md)) and plan-mode read-only policy
([ADR-0015](0015-plan-skills-not-in-plan-mode.md)) are unchanged.
