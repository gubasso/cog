# Model/Effort Policy SoT + Rename plans-revision → review-implementation-plans

> Complexity: L | Rounds: 3 | Generated: 2026-06-19 | Repo: /workspaces/cog

## Problem Statement

`cog` ships Claude and Codex skills whose `SKILL.md` frontmatter pins a `model:` and `effort:`, and
whose Codex calls pass model/effort through `cog codex-runner`. Today that choice is an **implicit,
undocumented convention**: most "procedural execution" skills already use `model: opus` + `effort:
low`, the bare-routine skills (`gc`, `tsk-new`) use `model: haiku`, and exploration/planning skills
(`ask`, `plan-*`, `prex`, `review-loop`) carry no override and ride the session default. Exactly one
skill breaks the pattern — `.claude/skills/plans-revision/SKILL.md` is `model: sonnet` + `effort:
high`, the only `sonnet` user in the tree.

There is no single source of truth (SoT) that says **which model + effort a task class should use**,
why, and with what real benchmark/pricing evidence behind it. The reference material that *does*
exist (Claude and Codex model tiers, pricing, benchmarks, reasoning-effort multipliers) lives in the
external `$DOCS_NOTES_REPO` (`/home/gbasso/DocsNNotes/tech/tools/claude-code/`) and is partly stale
(it lists Opus **4.7**; the current model is Opus **4.8**).

This plan establishes the model/effort policy as a first-class, evidence-backed SoT inside `cog`,
encodes the hard rule **never `model: sonnet` — use `model: opus` + `effort: low` instead**, and
then applies that policy by renaming and re-grading the one outlier skill (and its sibling `cog`
commands) from `plans-revision` to `review-implementation-plans`.

## Strategy

Three dependency-ordered rounds, foundations first.

1. `research-current-model-data` refreshes the evidence: deep web research against official Anthropic
   and OpenAI/Codex sources for the current Claude (Opus 4.8 / Sonnet 4.6 / Haiku 4.5 / Fable 5) and
   Codex (gpt-5.5 / gpt-5.4 / gpt-5.4-mini) models — benchmarks, pricing, reasoning-effort support
   and token multipliers — written into dated, periodically-revalidatable maintenance references in
   `docs/reference/`.
2. `model-effort-policy-sot` authors the policy: a policy document plus two richly descriptive TOML
   data files (one Claude, one Codex) in `docs/reference/`, plus an ADR recording the "never sonnet"
   decision, wired into `AGENTS.md` / `CLAUDE.md`.
3. `rename-to-review-implementation-plans` applies the policy: an atomic rename of the
   `plans-revision` skill **and** its `cog plans-revision-scan` / `plans-revision-verify` commands to
   `review-implementation-plans`, re-grading the skill to `model: opus` + `effort: low`, and fixing
   every reference — then a final gated cleanup that retires the now-superseded DocsNNotes
   model-reference source files.

This plan is **self-contained and independent**: all model/effort material lives under `cog`'s
Diátaxis `docs/` tree (`docs/reference/` for the policy, the TOML data, and the dated evidence;
`docs/decisions/` for the ADR), because the policy is authoring-time guidance plus a recorded
decision — not a runtime-loaded skill source. It does **not** depend on the `cog-self-contained-skill-refs`
plan and does **not** place anything in `skill-refs/`.

## Rounds

1. `research-current-model-data.md` — deep web research → dated Claude + Codex benchmark/pricing/effort references in `docs/reference/`.
2. `model-effort-policy-sot.md` — policy doc + two descriptive TOML data files in `docs/reference/` + the "never sonnet → opus+low" ADR + AGENTS.md/CLAUDE.md wiring.
3. `rename-to-review-implementation-plans.md` — atomic rename of the `plans-revision` skill + `cog` commands to `review-implementation-plans`, re-graded to opus/low, all references fixed, then gated retirement of the DocsNNotes model-reference sources.

## Execution Commands

```bash
# Execute the next todo round (executor reads queue-rounds.yaml, runs the first todo round, then stops):
/prex -ar @.implementation-plans/plans/model-effort-policy-and-rename/

# Or target a specific round file directly:
/prex -ar .implementation-plans/plans/model-effort-policy-and-rename/research-current-model-data.md
```

## Execution Discipline

**Rounds must be executed one at a time.** Each round is a self-contained unit of work designed for
a single `/prex` session. Do not implement multiple rounds in one session.

When `/prex` is pointed at this directory or this `README.md`, it MUST:

1. Read this plan's `queue-rounds.yaml`.
2. Find the first round with status `todo`.
3. Set that round's `status` to `doing`, execute ONLY that round, then set it to `done` and stop.
4. End the session — a fresh `/prex` session is launched for any subsequent round.

## Decisions & Constraints

- `Executor: prex (EF 1.5)` — sized for the four-pass prex pipeline.
- **Independent plan (`depends_on: []`).** All artifacts live under `cog`'s `docs/` tree; nothing
  here requires the `skill-refs/` tree or the `cog skill-refs` resolver. The model/effort policy is
  authoring-time guidance + a recorded decision (consulted when a skill is written), not a spec a
  skill loads at runtime — so its correct Diátaxis home is `docs/reference/` (policy + TOML + dated
  evidence) and `docs/decisions/` (the ADR).
- **Hard rule — never `model: sonnet`.** Any skill that would otherwise use `model: sonnet` must use
  `model: opus` + `effort: low`. This is the central decision the ADR in Round 2 records.
- **Default behavior for exploration/planning skills:** no `model:`/`effort:` override — ride the
  session default (Claude: Opus + high; Codex: gpt-5.5 + medium). A skill author may override per
  case when justified (e.g. raise effort to `xhigh`).
- **Data format = TOML** with deliberately **descriptive** fields (`use_when`, `signals`,
  `anti_signals`, `examples`, `reference_docs`, `rationale`, `escalation`) so an AI agent reading the
  data can reason about the correct classification, not just look up a value. (User-chosen format.)
- **`plans-revision` re-grade to `opus` + `effort: low`** is an explicit user decision (down from
  `sonnet` + `high`), and is the canonical worked example of the "never sonnet" rule. The reduced
  effort is intentional; the policy ADR documents the reasoning.
- **DocsNNotes retirement is done by this plan (Round 3, gated):** the stale
  `$DOCS_NOTES_REPO/tech/tools/claude-code/{models-reference.md, codex-models-pricing.md,
  codex-models-comparison.md}` are deleted only after the in-cog replacements
  (`docs/reference/models-reference-*.md`, `model-effort-policy.md`, and the TOML data) exist and
  verify. The executor deletes; the human commits the DocsNNotes repo separately (AGENTS.md forbids
  unauthorized git operations).
- **ADR number is assigned at execution, not hardcoded.** `0010`–`0012` are taken; the unrelated
  `cog-self-contained-skill-refs` plan also adds an ADR (its own "0010" reference is stale — the next
  free number is `0013`). Round 2 must pick the **next free** ADR number at execution, coordinating
  so the two new ADRs do not collide.

## Rejected Alternatives

- **Place the policy + TOML in `skill-refs/` and depend on `cog-self-contained-skill-refs`.** Rejected
  as over-coupling: `skill-refs/` is for specs skills load *at runtime*; the model/effort policy is
  authoring-time guidance plus a decision. Putting it in `docs/` keeps this plan independent, removes
  a cross-plan ordering hazard, and is still consistent with that plan's taxonomy (project docs, not
  a runtime skill source).
- **Rename the skill in a separate plan from the policy.** Rejected per user direction: the rename is
  the first concrete application of the policy and shares this directory; keeping them together keeps
  the "never sonnet → opus+low" rule and its canonical example in one place.
- **Keep `cog plans-revision-scan` / `-verify` command names unchanged.** Rejected per user
  direction: the commands are renamed alongside the skill for full naming consistency, accepting the
  larger ripple (command modules, handler fns, tests, help snapshots, docs, callers).
- **Guess current benchmark/pricing numbers from memory.** Rejected: the evidence must come from
  dated web research against official sources, because the stale DocsNNotes copy already drifted
  (Opus 4.7 vs 4.8).

## Risks & Edge Cases

- **ADR-number collision** with the unrelated self-contained plan's new ADR — mitigated by picking
  the next free number at execution (the plans are otherwise independent and may run in any order).
- **Rename ripple is wide.** `plans-revision` appears in the skill itself, `runner-queue/
  SKILL.md` (~13 refs), ADR-0012 prose, `cli-commands.md`, two bats suites, and help snapshots. The
  rename round greps for every occurrence rather than trusting a fixed list, and runs `cog
  skill-lint` + the integration suite as the postcondition.
- **`plans-revision` is project-local, not shipped.** It lives in `.claude/skills/` (not
  `skills/claude/`), so `install.sh` does not copy it; the rename must not accidentally move it into
  the shipped tree.
- **Re-grading `plans-revision` to `effort: low`** lowers reasoning budget for a fail-closed,
  judgment-heavy reconciliation skill. Accepted as an explicit user decision; the policy ADR records
  the trade-off so a future reviewer sees it was deliberate.
- **Premature DocsNNotes delete.** Round 3's gated cleanup skips the delete (and reports it) if the
  in-cog replacements are missing or verification is not green, so the source is never lost.

## Completion

When all rounds are done, set each round `done` in this plan's `queue-rounds.yaml` and set this plan
`done` in the top-level `.implementation-plans/queue-plans.yaml`. Nothing moves on disk.
