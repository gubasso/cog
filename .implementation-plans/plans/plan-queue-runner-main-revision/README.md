# Plan Queue Runner: Main-Queue Support + Plans-Revision Step

> Complexity: L | Rounds: 3 | Generated: 2026-06-19 | Repo: /workspaces/cog | Executor: prex (EF 1.5)

## Problem Statement

`cog`'s `runner-queue` skill (`skills/claude/runner-queue/SKILL.md`) today drives ONE
plan's inner `rounds:` queue to completion: for each runnable `todo` round it dispatches the round's
verbatim `/prex` prompt to a fresh `claude-delegate`, verifies the round flipped itself to `done` in
`queue-rounds.yaml`, commits with `/gc -a`, and loops. Two features must be added, coherently:

**Feature A — Main-queue support.** Drive the repo-wide MAIN queue at
`/workspaces/cog/.implementation-plans/queue-plans.yaml`, whose top-level key is `plans:` (a list of whole
plans, each `item/status/depends_on/prompt/notes`), executing every listed plan in order. Each plan
entry in the migrated live data targets a plan directory prompt
(`/prex -ar @.implementation-plans/plans/<slug>/`) whose rounds live in that directory's
`queue-rounds.yaml`. The live data is directory-only, so the resolver classifies exactly one form —
`inner_queue` (a directory containing `queue-rounds.yaml`) — and fails closed on anything else.

A prior `/ask -wc` research pass (Claude Explore + Codex), verified against the live repo,
established that most infrastructure already exists:

- The queue helpers in `lib/functions/fn_queue.sh` are already schema-generic for `plans|rounds`
  (`queue_schema_key`, `queue_validate_file`, `queue_count`, `queue_has_item`, `queue_bootstrap_file`,
  `queue_append_entry`, `queue_render_entry_block`, `queue_assert_helper_owned_shape` all take a
  `schema` arg), and `cog queue-bootstrap` / `cog queue-append` already accept `--schema plans|rounds`.
- **Only the SELECTION path is rounds-hardcoded** (`queue_select_next_round` and
  `queue_validate_rounds_selectable` in `fn_queue.sh:138,262`; their caller `cmd_queue_select.sh:32,50`).
- **No status-mutation helper exists.** For the inner round queue, the round's own `/prex` flips its
  `rounds[]` status to `done` and the runner only verifies. For the MAIN queue there is no `/prex`
  that owns the plan-level flip, and `/gc` only commits — so a deterministic `cog queue-status-set` is
  required (the single most important new piece).

**Feature B — Plans-revision step.** After executing a plan or round and committing with `/gc`, and
BEFORE selecting the next queue item, run a revision step that checks the current repo state against
ALL queue items (the main `plans:` queue + every inner `rounds:` queue) and updates the
implementation plans to stay coherent with the actual code: mark already-implemented items `done`,
revise remaining `todo`/`backlog` plan & round files to match current code, and append new
rounds/plans to capture regressions or newly-found gaps. The goal: a following plan execution
implements any regression, and the plans stay coherent with — and incrementally ahead of — the
implementation.

## Strategy

Three rounds in strict dependency order, decomposed so each round is one cohesive `/prex` session and
the orchestrator skill (`runner-queue/SKILL.md`) is edited exactly ONCE:

- **Round 1 — queue-main-primitives**: pure deterministic `cog` layer for Feature A. Generalize
  selection to `--schema plans|rounds`; add `cog queue-status-set` (guarded single-item flip); add
  `cog runner-queue-resolve-plan` (classify a/b/c); extend `cog runner-queue-setup` to
  detect and persist `QUEUE_SCHEMA`. Tests + command-surface docs. No skill prose changes.
- **Round 2 — plans-revision-mechanics**: pure deterministic `cog` layer for Feature B plus the new
  project-local skill. Add revision inventory + verify commands (reusing the `fn_refactor` fingerprint
  prior art) and the new `.claude/skills/plans-revision/SKILL.md`. Tests + skill-lint + ADR. No runner
  prose changes.
- **Round 3 — runner-orchestration-integration**: edit `skills/claude/runner-queue/SKILL.md`
  ONCE to drive a `plans:` main queue inline (depth 0), resolve each plan form, drive inner queues
  when needed, flip main plans `done` via `queue-status-set`, and invoke the plans-revision subagent
  after every committed item. Integration tests + skill-lint + docs.

Round 2 depends on Round 1's `queue-status-set`/`queue-append` (its only sanctioned mutation paths)
and `QUEUE_SCHEMA` detection. Round 3 depends on both.

## Rounds

1. `queue-main-primitives.md` — schema-generic selection, `queue-status-set`, `resolve-plan`, setup
   schema detection.
2. `plans-revision-mechanics.md` — revision scan/verify `cog` commands + the new `plans-revision`
   project skill.
3. `runner-orchestration-integration.md` — rewrite `runner-queue/SKILL.md` to drive the main
   queue and invoke revision at both committed-item boundaries.

## Execution Commands

```bash
# Execute the next todo round (executor reads queue-rounds.yaml, runs the first `todo` round, then stops):
/prex -ar @.implementation-plans/plans/plan-queue-runner-main-revision/

# Or target a specific round file directly:
/prex -ar .implementation-plans/plans/plan-queue-runner-main-revision/queue-main-primitives.md
```

## Execution Discipline

**Rounds must be executed one at a time.** Each round is a self-contained unit of work designed for a
single `/prex` session. Do not implement multiple rounds in one session.

When `/prex` is pointed at this directory or this `README.md`, it MUST:

1. Read this plan's `queue-rounds.yaml`.
2. Find the first round with status `todo`.
3. Set that round's `status` to `doing`, execute ONLY that round, then set it to `done` and stop.
4. End the session — a fresh `/prex` session is launched for any subsequent round.

## Decisions & Constraints

- **Executor: prex (EF 1.5).** Rounds sized for one `/prex` session each. Raw axes
  (files 4, cross-cut 4, deps 3, novelty 3, risk 4 = 18) / 1.5 = 12 -> **L** (the maximum grade
  reachable under prex; exactly met). XL is unreachable under prex.
- **Reuse, don't rewrite (Feature A).** The schema-generic `fn_queue.sh` helpers, `queue-bootstrap`,
  `queue-append`, and `cmd_runner_queue_parse_commit.sh` stay unchanged. Only the selection path
  is generalized; two new commands (`queue-status-set`, `runner-queue-resolve-plan`) are added;
  setup gains schema detection.
- **Detection discriminates on the top-level YAML key**: `rounds:` -> inner queue (today's behavior);
  `plans:` -> main queue; both/neither -> fail closed. Detection lives in `cog`
  (`runner-queue-setup`), not skill prose (ADR-0008).
- **Per-plan form resolution** (`cog runner-queue-resolve-plan`) resolves a selected plan entry to
  its `inner_queue` form, parsing both the `/prex -ar <target>` and the `/prex -ar @<target>` prompt
  forms (the live main queue uses the `@`-prefixed directory form). The live data is directory-only:
  a valid plan target is a directory containing `queue-rounds.yaml` -> `inner_queue`; a file target or
  a directory without `queue-rounds.yaml` fails closed. There is exactly one resolver kind.
- **Two distinct status authorities (crisp rule):**
  - *Inner-round `done` is verify-only.* The round's own `/prex` flips its `rounds[]` status; the
    runner re-reads and requires `done` (unchanged from today).
  - *Main-plan `done` is ALWAYS set by `cog queue-status-set --schema plans --from todo --to done`*,
    because no `/prex` owns the plan-level flip and `/gc` only commits. The runner never hand-edits a
    queue.
- **`/gc` is the only commit authority.** New helpers may update queue status but must NOT commit.
- **Deterministic mechanics live in `cog` (ADR-0008).** Every new mechanic is a `cog` subcommand or
  `cog::fn::*` helper with a line-2 `: 'desc: ...'` sentinel, machine-facing JSON (ADR-0009), and
  `bats` tests. Skills keep only sequencing/judgment/orchestration prose.
- **Backward-compat default.** `cog queue-select` defaults `--schema rounds`; its existing JSON output
  contract (`ok/queue_path/clean_check/state/selected/todo_remaining/blocked/reason`) is preserved
  byte-for-byte, plus an additive `schema` field.
- **Orchestration & depth (load-bearing).** Per `docs/reference/orchestration-contract.md`,
  Skill-inline = 0 depth; a foreground Agent/delegate = +1; hard cap is 5 (depth-5 has no Agent tool).
  The main-queue loop runs INLINE in the same skill context (zero added depth). Depth shape:
  main loop (0) -> per-plan inner loop (0) -> `claude-delegate` per round (+1) -> `/prex`
  (same delegate ctx) -> review subagents (+1/+2). The plans-revision subagent is ONE foreground Agent
  level, a SIBLING of (not nested under) the round delegate, spawned from the same inline loop.
  DO NOT delegate "run this main queue" to another subagent — it burns a level for no isolation and
  risks the cap.
- **Env-first no-backgrounding (ADR-0010).** Rely on `CLAUDE_CODE_DISABLE_BACKGROUND_TASKS=1` plus
  Bash timeouts >= 600000; never a `PreToolUse` backgrounding hook; never background Codex or a long
  orchestration call.
- **Durable postconditions at every boundary.** After each round: re-read inner queue, require
  `rounds[item]==done`. After each plan (always `inner_queue`): re-run inner `queue-select` and require
  `state==complete`; then `cog queue-status-set --schema plans --from todo --to done`, then re-read and
  require `plans[item]==done`. After each revision:
  `cog plans-revision-verify` passes AND the worktree is clean. Resume is free: the persisted
  `plans[].status` is the durable state.
- **`--max N` and `--dry-run`** apply at the PLAN level for a main queue (count plans, list remaining
  `todo` plans), mirroring the existing round-level semantics for an inner queue.

### Feature B — settled requirements (from the coordinator interview; firm decisions)

- **Q1 Revision authority -> Adaptive.** Revise remaining `todo`/`backlog` plan & round files to stay
  coherent with current code; mark already-implemented items `done`; AND append new rounds/plans for
  regressions or newly-found gaps. Never edits the recorded history of completed (`done`) items.
- **Q2 Revision cadence -> Both boundaries.** After every committed item — both inner rounds AND
  main-queue plans — reconcile ALL plans (main queue + every inner queue). One extra agent call per
  item.
- **Q3 Packaging -> New project skill + agent.** New `.claude/skills/plans-revision/SKILL.md` invoked
  as a dedicated foreground subagent; deterministic drift / state-vs-queue mechanics in NEW `cog`
  subcommands (reusing the `fn_refactor` drift prior art) per ADR-0008.
- **Q4 Safety posture -> Auto-apply + fail closed.** Revision applies edits unattended and commits
  them via `/gc` (keeping the next item's clean-tree guard valid); a no-drift cycle is a no-op with no
  commit; if it cannot reach a clean, committed, verifiable result, STOP the whole run.

## Rejected Alternatives

- **Rewrite the queue helpers for the main queue** — rejected. The `/ask` pass confirmed `fn_queue.sh`
  is already schema-generic and `queue-bootstrap`/`queue-append` already take `--schema`; only
  selection is hardcoded. Feature A is "generalize selection + add resolve/status-set + extend skill
  prose", not a rewrite.
- **Let `/gc` flip the main plan status** — rejected (this was a wrong assumption in the Explore pass;
  Codex caught it and direct inspection of `lib/` confirmed nothing flips a plan-level status). `/gc`
  only commits. A dedicated `cog queue-status-set` is required.
- **Delegate the whole main-queue loop to a subagent** — rejected. It adds a depth level for no
  isolation benefit and risks the fixed 5-level cap. The main loop stays inline (depth 0).
- **Edit the runner skill across two rounds** — rejected. All `runner-queue/SKILL.md`
  orchestration changes are consolidated into Round 3 so the orchestrator is rewritten once.
- **A parallel mutation path inside the revision skill** — rejected. Revision must use the same
  `cog queue-status-set` / `cog queue-append` helpers Feature A introduces, never invent its own queue
  writer.
- **Make revision optional / advisory** — rejected by Q4 (auto-apply + fail closed): revision edits
  are applied and committed unattended, or the run stops.
- **Reinvent a drift fingerprint for revision** — rejected. Reuse/extend
  `cog::fn::refactor_scan_fingerprint` (`lib/functions/fn_refactor.sh`) and the
  `cmd_refactor_scan_drift.sh` prior art.

## Risks & Edge Cases

- **Backward-compat regression in selection.** Generalizing `queue_select_next_round` must keep the
  existing single-queue path identical. Mitigation: default `--schema rounds`; keep the JSON output
  contract and self-check filter byte-identical (plus an additive `schema`); add a regression bats
  case for the unchanged rounds path.
- **Setup dies on `plans:`.** `cmd_runner_queue_setup.sh` runs the first `queue-select` at setup
  (line 108) — today that would die on a `plans:` queue via `queue_validate_rounds_selectable`.
  Mitigation: detect the schema in setup and thread it into the first select.
- **Resolver prompt parsing.** The live main queue uses only the directory form `/prex -ar @<dir>/`;
  the data is directory-only. `resolve-plan` must still parse both the `@`-prefixed and bare directory
  forms and normalize relative targets against `repo_root`; a bare target that resolves to a file
  (rather than a plan directory with `queue-rounds.yaml`) fails closed.
- **Revision auto-commit breaks the next item's clean-tree guard.** Mitigation: revision commits via
  `/gc` so the tree is clean before the next item; a no-drift cycle is a no-op (no commit); the runner
  verifies a clean worktree + `plans-revision-verify` before proceeding. Fail closed otherwise.
- **Revision editing completed history.** Mitigation: Q1 forbids editing recorded history of `done`
  items; `cog plans-revision-verify` asserts before/after that every previously-`done` item still
  exists and is still `done` (deterministic immutability guard), failing closed if violated.
- **Depth-budget overflow.** The revision subagent is a sibling of the round delegate at +1; verify
  the 5-level cap is never exceeded. Mitigation: keep both loops inline; never nest the loop in a
  subagent.
- **Doc/completion/man/help drift gate.** New `cog` command surfaces must update
  `docs/reference/cli-commands.md`, `completions/cog.bash`, `man/cog.1(.scd)`, and help snapshots, or
  pre-commit drift checks fail.

## Completion

When all rounds are done, set each round `done` in this plan's `queue-rounds.yaml` and set this plan `done`
in the top-level `/workspaces/cog/.implementation-plans/queue-plans.yaml` (via `cog queue-status-set
--schema plans` once the runner itself can do so, or by the executing `/prex` per its final step).
Nothing moves on disk.
