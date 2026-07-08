# ADR-0070: executor-prex explicit plan/review split; review-oneshot rides HIGH

## Context and Problem Statement

[ADR-0038](0038-plan-vetted-extraction.md) collapsed `executor-prex`'s original explicit two-stage
front end — Codex drafts a plan, Claude reviews it — into a single `plan-vetted` delegation that owns
an input-quality gate plus dual-engine planning (`plan-multi` / `review-plan-multi`). That merge made
the front end powerful but opaque: a reader cannot see the adversarial Codex-drafts / Claude-vets shape
that gives `executor-prex` its identity, and the dual-engine planning runs Codex and Claude at HIGH,
which is heavier than the flow needs for its common case.

We want `executor-prex` to be a legible five-stage adversarial pipeline — Codex drafts the plan, Claude
reviews it, Codex implements, Claude reviews the implementation, optional review loop — at
deliberately-chosen effort tiers, without disturbing `executor-vetted`, which still wants the
`plan-vetted` dual-engine producer.

Separately, `review-oneshot` (the fresh-context full-review skill used for `executor-prex`'s
implementation-review stage and by `review-loop`) sits at XHIGH per [ADR-0041](0041-named-tier-ladder.md)'s
prefix-to-tier ladder. XHIGH is ~3–5× the token/latency burn of HIGH, and in practice HIGH is a
sufficient floor for the implementation-review stage.

## Considered Options

- **Keep `plan-vetted` in `executor-prex`.** No churn, but the adversarial shape stays hidden and the
  front end stays at dual-engine HIGH.
- **Re-split the front end and re-enable Codex thread-resume for implementation** (the pre-ADR-0038
  continuity model). Restores warm context but reintroduces the account/thread-state fragility ADR-0038
  removed.
- **Re-split the front end, keep the fresh-exec implementation, retier `review-oneshot` to HIGH.**
  Explicit five stages; single-engine planning; implementation stays a self-contained fresh `exec`.

## Decision Outcome

Chosen option: **explicit five-stage `executor-prex` with a fresh-exec implementation and a HIGH
`review-oneshot`.**

1. `executor-prex` runs five stages: (1) Codex drafts the plan via `plan-oneshot-codex` at native
   effort `medium` → `draft-plan.md`; (2) Claude vets the draft via `review-plan-oneshot` (HIGH) →
   `vetted-plan.md`, then the approval loop; (3) Codex implements the vetted plan as a fresh durable
   `exec` at `medium`; (4) Claude reviews the implementation via `review-oneshot` (now HIGH); (5) the
   optional `review-loop`. The authoritative reviewed plan keeps the filename `vetted-plan.md`, so the
   implementation, implementation-review, review-loop, and `cog review-loop-input` / hook-guard
   contracts are unchanged.
2. Implementation stays a **fresh `exec` with the vetted plan inlined** — no Codex planning thread to
   resume. This reverses only ADR-0038's stage-1 *merge*, not its thread-resume removal.
3. `plan-vetted`, `plan-multi`, and `review-plan-multi` are **unchanged** and remain the vetted-plan
   producer for `executor-vetted`; ADR-0038's extraction decision stands there.
4. `plan-oneshot-codex`'s default Codex run effort drops from `high` to `medium`.
5. `review-oneshot` (Claude and its Codex twin) is retiered **XHIGH → HIGH**. The `review-oneshot-*`
   prefix default in the tier ladder stays XHIGH; `review-oneshot` itself is pinned to HIGH via its
   `high` registry membership in `data/model-effort/{claude,codex}/tiers.yaml` — the single escape
   hatch, mirroring how `executor-prex` overrides the `executor-*` MEDIUM default. XHIGH remains a
   defined, reserved escalation rung.

## Consequences

- The front end is single-engine (Codex drafts, Claude vets) rather than dual-engine. This is a
  deliberate simplicity/cost trade; `executor-vetted` remains the dual-engine option.
- `executor-prex`'s capability power recomputes from 52 to 45 (its `data/power-grade/executor-capability/passes.yaml`
  entry loses the gate role and the dual-engine plan sum, gains a single-engine plan and an explicit
  plan-review stage, and its implementation review drops to `opus48-high`). It remains the
  highest-power native executor (`ceil_pct` 100), but the `%`-bands widen, shifting some upper-moderate
  complexity scores from `executor-prex` toward `executor-vetted`/`executor-oneshot`. The match/band
  tests are recalibrated accordingly.
- Retiering `review-oneshot` lowers the effort of every caller that reviews through it (`executor-prex`
  stage 4, `review-loop` round 1); this is the intended cost reduction. The change is recorded in the
  living tier docs, the `review` skill-class contract, and this ADR; ADR-0041's ladder text is amended,
  not rewritten.

## Status

Implemented. Enacted by `skills/claude/executor-prex/SKILL.md` and its `references/` (new
`build-plan.md` and `review-plan.md`, renumbered stages), `skills/claude/plan-oneshot-codex/SKILL.md`,
`skills/claude/review-oneshot/SKILL.md`, `data/model-effort/{claude,codex}/tiers.yaml`,
`data/power-grade/executor-capability/passes.yaml`, `data/skill-class/contracts.yaml`, and the
`docs/reference/model-effort-policy.md` / `docs/reference/skill-contract.md` prose; verified by `cog
skill-lint`, `cog power-grade executor-validate`, and `test/integration/power_grade.bats`.
