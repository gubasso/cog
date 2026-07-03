# ADR-0060: gc parallel repo fan-out and Codex twin removal

## Context and Problem Statement

`gc` committed a session's multiple touched repos **sequentially**: after `cog gc-plan` partitioned
the declared session files by owning repo, a single-context loop staged, drafted a message, ran the
fix-all round loop, and pushed each repo one after another
([ADR-0039](0039-gc-fix-all-round-loop.md), [ADR-0059](0059-gc-change-provenance-foreign-dirty-stop.md)).
Per-repo commit work is independent — git commits across separate repos are never atomic and a
failure in one repo already never rolled back an earlier repo's commit — so the sequential loop cost
wall-clock time with no safety benefit. The `cog gc-*` command surface already targets any repo
without `cd` (`--repo-root`, `git -C`), and `cog runner-commit-parse` already aggregates one
`COMMIT_*` line per repo and fails closed on any `*_FAILED`. Separately, the Codex `gc` twin
(`skills/codex/gc`) fixed hooks inline (no cheap/expensive engine split) and is not used by the
operator, while the parallel capability being added is Claude-only.

## Considered Options

- Keep `gc` monolithic and merely parallelize the loop inline (one context driving N concurrent
  commit routines) — rejected: the per-repo routine (message-draft judgment, round loop, hook-fix
  delegation) is substantial and belongs in an isolated fresh context per repo.
- Introduce a governed `runner-*` coordinator and `executor-*` per-repo worker — rejected: a
  repo-set from `gc-plan` is not an executor-selecting queue and a per-repo committer does not
  execute an arbitrary prompt/plan, so neither governed prefix fits (see
  [ADR-0016](0016-skill-prefix-taxonomy.md)).
- Keep the Codex `gc` twin as a sequential fallback — rejected: Codex cannot fan out Agent subagents
  the same way and the operator does not use it.

## Decision Outcome

**Decision A — `gc` becomes an N-way homogeneous parallel fan-out coordinator.** `gc` keeps its
user-facing name and triggers. It runs the one-time session setup, baseline, session-file-list
judgment, `cog gc-plan` partition, and every safety STOP (escapes, `surprises`, `foreign-dirty`
STOP-and-ask, `--all` union-and-rescan) **before** any subagent spawns — a parallel worker never
makes the "ask the user" call. It then dispatches one independent Claude Agent subagent per touched
repo, all issued in a single assistant message so they run concurrently, verifies each with the
proof-of-delegation pattern, and aggregates the per-repo result lines with `cog runner-commit-parse`
(fails closed on any `*_FAILED`). This is a new orchestration pattern: prior art
(`plan-multi`/`review-plan-multi`) fans out two heterogeneous workers (one Claude Agent + one Codex
job); N homogeneous Agent subagents is new — the concurrency mechanism (many tool calls in one
assistant message) is proven, only the multiplicity is new. The pattern is documented as
`Homogeneous Parallel Fan-Out` in `skill-refs/orchestration/orchestration-patterns.md`.

**Decision B — the per-repo commit routine is extracted to a new worker skill `gc-repo`.** `gc-repo`
is an ungoverned `other`-class skill (tier `low`: `opus`, `effort: low`), invoked as a fresh-context
worker via the Agent tool, not by the user. It owns the routine moved out of `gc`: stage
(`cog gc-stage --repo-root`), the post-stage diffstat materiality check, draft-and-lint of the
Conventional Commits message, the fix-all round loop (`gc-commit` → `gc-classify-failure` →
delegate to `gc-hook-fix` → re-stage → retry; stuck check via `gc-loop-progress`), optional
`gc-push`, and emitting exactly one canonical `cog msg` status line. A `--multi-repo` flag controls
the `repo=<root>` suffix so a single-repo commit keeps the historical bare `COMMIT_OK <sha>`
contract. `gc-hook-fix` is unchanged. No `cog gc-*` JSON contract changes — the existing
`--repo-root` surface fully covers a standalone per-repo worker.

**Decision C — the Codex `gc` twin is deleted.** `skills/codex/gc` is removed and `gc` is Claude-only,
because N-way Agent fan-out is a Claude-only capability and the operator does not use the Codex twin.
`cog skill-lint` has no twin-pairing rule, so a lone Claude `gc` with no Codex twin is compliant.

**Decision D — the prefix taxonomy is unchanged.** Ungoverned names already permit an ungoverned
fan-out coordinator (`gc`) and a `gc-`-namespaced worker (`gc-repo`), consistent with the existing
`gc-hook-fix`. A `gc-` name classifies as `other` (`cog::fn::skill::classify_prefix`), so both `gc`
and `gc-repo` correctly carry no plan-mode gate, no context-brief gate, and no input-fidelity marker:
the `gc → gc-repo` and `gc-repo → gc-hook-fix` handoffs are deterministic structured handoffs (repo
root + repo-relative paths file + scratch dir + result-line file + flags), not best-constructed
judgment briefs. No amendment to [ADR-0016](0016-skill-prefix-taxonomy.md) is required.

This ADR relates to and partially supersedes the standing assumption of a Codex `gc` twin in
[ADR-0031](0031-conventional-commit-validation.md), [ADR-0039](0039-gc-fix-all-round-loop.md), and
[ADR-0059](0059-gc-change-provenance-foreign-dirty-stop.md); those accepted ADRs are not edited. The
round loop (ADR-0039), the Conventional Commits pre-flight gate (ADR-0031), and the change-provenance
`foreign-dirty` STOP and destructive-recovery prohibition (ADR-0059) are all retained — the round
loop moves verbatim in substance into `gc-repo`, and the safety STOPs stay in the `gc` coordinator.

## Consequences

- Good: multiple repos commit concurrently, cutting wall-clock time, with no loss of safety semantics.
- Good: the per-repo routine runs in an isolated fresh context per repo; the depth chain `gc` →
  `gc-repo` → `gc-hook-fix` is 3 of the fixed 5 levels.
- Good: `gc` is a leaner coordinator; the reusable homogeneous-fan-out pattern is documented once for
  future skills.
- Neutral: single-repo commits now route through one `gc-repo` worker for uniformity; the bare
  single-repo result-line contract is preserved via the worker's `--multi-repo` flag.
- Bad: the mixed-file materiality safety check, previously an interactive prompt in `gc`, becomes a
  worker fail-closed (`COMMIT_FAILED` with a mixed-scope reason) surfaced by the coordinator after
  aggregation, because a parallel worker never prompts the user.

## Status

Accepted — `skills/claude/gc/SKILL.md` (coordinator refactor), `skills/claude/gc-repo/SKILL.md` (new
worker), `skills/codex/gc/SKILL.md` (deleted), `data/model-effort/claude/tiers.yaml`,
`data/model-effort/codex/tiers.yaml`, `skill-refs/orchestration/orchestration-patterns.md`,
`docs/reference/skills.md`; tests in `test/integration/skills_claude.bats` and
`test/integration/cmd_skill_lint.bats`. `skills/claude/gc-hook-fix/SKILL.md` and the `cog gc-*`
command surface are unchanged.
