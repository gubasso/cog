# ADR-0064: Rename the revision boundary to review-queue-rounds

## Context and Problem Statement

The post-implementation revision boundary established by ADR-0012 and extended by ADR-0014 shipped as
`review-plan-implementation` — a project-local skill plus a `cog` backing family
(`review-plan-implementation-scan`/`-verify`, `cog::fn::review_plan_implementation_*`). Two problems
accumulated:

- **Namespace violation.** ADR-0016 reserves the `review-plan-*` sub-namespace for plan review that
  happens *before* implementation. This boundary runs *after* a committed queue item, reconciling the
  plan vault's queues with code that already landed. A post-implementation reconciliation boundary must
  not sit in the pre-implementation `review-plan-*` sub-namespace.
- **Store-scope coupling.** The boundary backing code hardcoded `<repo>/.implementation-plans/` and
  died on a fresh vault, so it could not consume the store-scoped plan vault (local `.cog/plans` or
  global `<store>/projects/<project_key>`) produced by the current plan builders (ADR-0048/0057).

## Considered Options

- Keep the name and special-case the vault paths inside the `review-plan-*` boundary.
- Rename the boundary to `review-queue-rounds` under plain `review-*`, promote it to a shipped runtime
  skill, and make it vault-store-aware through the shared resolver.

## Decision

Rename the entire boundary family from `review-plan-implementation` to **`review-queue-rounds`** under
plain `review-*`, in one consistent sweep: the runtime skill (promoted from the project-local
`.claude/skills/review-plan-implementation/` to the shipped
`skills/claude/review-queue-rounds/SKILL.md`), the `cog review-queue-rounds-scan`/`-verify` commands,
the `cog::fn::review_queue_rounds_*` helpers, the `data/model-effort/claude/tiers.yaml` low-tier pin,
the tests, and every man/completion/doc reference.

The boundary and both `runner-*` setups now resolve the vault through one shared verb,
`cog plan runner-resolve --target <plan_dir|queue> [--json]`, which labels the store
(`local`/`global`/`custom`) and returns a role-named `plan_root`/`main_queue`. The scan/fingerprint code
is parametrized on `plan_root` (no `.implementation-plans` literal, no `die` on a fresh vault; the
in-repo local vault is pruned from the repo source fingerprint).

## Consequences

- Because plain `review-*` is governed by the `tiers.yaml` registry pin only (not a prefix default),
  renaming the pin (`review-plan-implementation` → `review-queue-rounds`, still under `low`) is what
  keeps the boundary at the `low` tier per ADR-0047.
- ADRs 0011, 0012, 0014, and 0020 reference the historical `review-plan-implementation` name. Per the
  accepted-ADR policy their bodies are not rewritten; each carries a note pointing here.
- Historical `review-plan-implementation` references inside already-written `.implementation-plans/`
  legacy plan artifacts are left untouched — they belong to other, unrelated in-flight plans.
- The rename does not change the boundary's contract: ADR-0012 verify semantics, ADR-0029
  plan-owned/runner-reconciled completion, and `/gc` as the only commit authority are preserved.
