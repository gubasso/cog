# Round 3: Best-practice research + tracking registration

> Plan: skill-research-shelf | Round: 3 of 3 | Complexity: M | Generated: 2026-06-19 |
> Repo: /workspaces/cog | Executor: prex (EF 1.5)

## Context

Round out the shelf with best-practice patterns and make it tracked for periodic revalidation, so the
findings do not silently go stale.

## Previous Rounds

Round 1 built `cog research-shelf`; Round 2 persisted official-docs research.

## Scope of This Round

**IN scope:**

- Web research on best-practice / exemplar skills for: planning skills (interactive plan-mode-style
  planners), plan-review skills, and single-agent executor / agent-handoff orchestration patterns.
  Persist via `cog research-shelf record`.
- Register the shelf in the periodic-revalidation registry
  (`docs/reference/maintenance-tracking.yaml`) using the schema owned by `repo-update-tracking`
  (`cog tracking-scan`) — emit the entry that registry expects; do NOT reimplement tracking.
- Add a short `docs/reference/research-shelf/README.md` explaining how skills CONSUME the shelf
  (reuse-if-not-overdue, else re-research and `cog research-shelf record`) — the contract
  `lean-plan-and-review-skills` and the executors depend on.

**OUT of scope:**

- The `cog tracking-scan` command itself (owned by `repo-update-tracking`).
- Authoring the consuming skills.

## Deterministic vs Probabilistic

- Deterministic (cog): persistence + the tracking-registry entry format.
- Judgment: which exemplars are worth recording; the consume-the-shelf contract wording.

## Validation

- `cog research-shelf validate` passes; `cog tracking-scan` (from `repo-update-tracking`) recognizes
  the shelf entry. `just lint` + `just test` green. Marks plan `skill-research-shelf` done in the
  top-level queue as the final round.

## Execution Discipline

One round per `/prex` session; flip this round `done`, set the plan `done` in the top-level queue, and
stop. Commit with `/gc -a` afterward.
