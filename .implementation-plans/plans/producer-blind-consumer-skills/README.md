# Producer-Blind Consumer Skills

> Complexity: L (single round by explicit directive) | Rounds: 1 | Generated: 2026-06-22 | Repo: /workspaces/cog

## Problem Statement

A consumer skill must depend only on the **structural input contract** it reads — never on the
identity of the skill that produced that input. `runner-queue` drives the `.implementation-plans/`
directory to completion regardless of whether `plan-writer`, `plan-writer-multi`, or a hand-authored
queue produced it; its opening line nonetheless says *"Drive a **plan-writer** implementation
queue…"*, coupling the consumer to one producer (and naming only one of several real producers).

The same anti-pattern lives in `review-findings` (Claude and Codex), which names `review-code-deep`
and `review-loop` as the producers of its findings instead of describing the findings contract
structurally. A cluster of adjacent cross-skill couplings (plan-one-lean referencing plan-writer's
interview pattern; plan-writer naming its coordinator; the Codex plan-writer's twin/coordinator
cross-references) violates the related self-containment / twin-meta rules (ADR 0019/0021).

The *validation* half of the golden rule is already satisfied — `runner-queue` delegates all input
handling to `cog runner-queue-setup`, `cog queue-select`, and `cog runner-queue-resolve-plan`. This
plan removes the remaining **prose** coupling, codifies the rule as a project golden rule (new ADR),
and adds deterministic enforcement in `cog skill-lint`.

## Strategy

The work is one cohesive change — introducing and enforcing a single golden rule — so it is delivered
as **one round** (explicit user directive; see Decisions). The round groups four workstreams: (A) the
core producer-blindness prose fixes, (B) the adjacent cross-skill coupling cleanup, (C) the ADR +
reference + non-negotiable codification, and (D) a `cog skill-lint` rule with tests. The lint rule
uses a code-side consumer→producer map rather than an in-skill marker, so no skill file gains a line
(important: `runner-queue/SKILL.md` is exactly at the 500-line lint limit).

## Rounds

The authoritative order and status live in `queue-rounds.yaml`.

1. `producer-blindness-rule.md` — fix producer-name leaks in consumer skills, clean up adjacent
   couplings, codify the golden rule (ADR + docs + non-negotiable), and enforce it with a new
   `cog skill-lint` `producer-blindness` rule plus tests.

## Execution Commands

```bash
# Single round — execute the round file directly with the lean executor:
/executor-lean -ar .implementation-plans/plans/producer-blind-consumer-skills/producer-blindness-rule.md

# Or point at the directory (executor reads queue-rounds.yaml, runs the first todo round, then stops):
/executor-lean -ar @.implementation-plans/plans/producer-blind-consumer-skills/
```

## Execution Discipline

**Rounds must be executed one at a time.** Each round is a self-contained unit of work designed for a
single `/executor-lean` session. This plan has exactly one round; do not bundle unrelated work into
the session.

When `/executor-lean` is pointed at this directory or this `README.md`, it MUST:

1. Read this plan's `queue-rounds.yaml`.
2. Find the first round with status `todo`.
3. Set that round's `status` to `doing`, execute ONLY that round, then set it to `done` and stop.
4. End the session — a fresh session is launched for any subsequent round.

## Decisions & Constraints

- **Executor: executor-lean (single-pass, EF 1.0)** — the user directed `/executor-lean` as the
  executor and a single round. The complexity heuristic scores this work around L (multi-file across
  skills + docs + lint code + tests), which would normally split into multiple rounds; the
  single-round structure is an explicit override, accepted because the change is one conceptual
  golden-rule introduction and each step is mechanical and independently verifiable.
- **Lint design is a code-side map, not an in-skill marker.** `runner-queue/SKILL.md` is exactly 500
  lines and the `line-count` lint rule fails over 500; an in-skill `<!-- cog-skill: producer-blind -->`
  marker would trip it. The consumer→producer association therefore lives in `cog skill-lint` itself
  (keyed by skill `name:`), which also makes the rule un-evadable by dropping a marker.
- **Producer-blindness ≠ legitimate delegation.** `/executor-*` references in `runner-queue` are its
  *output* edge (matched by prefix taxonomy); executors naming `/plan-one-lean` / `/review-plan-lean`
  are pipeline delegations (ADR 0025); `plan-writer-multi` naming `plan-writer` is its core coordinator
  function; `plan-one-lean-codex` naming `$plan-one-lean` is a delegation launcher (ADR 0021). None of
  these change.
- **`cog research-shelf … --consuming-skills` is out of scope** — it is a deterministic producer-side
  `cog` metadata field, not consumer prose coupling.
- Verification uses the repo CLI `./bin/cog`, NOT the stale stowed `~/.local/bin/cog` (which is broken:
  it references a removed `fn_refs.sh`).

## Rejected Alternatives

- **In-skill `producer-blind` marker listing forbidden producers** — rejected because `runner-queue`
  is at the 500-line cap and a marker line would break the `line-count` rule; a code-side map is also
  harder to evade.
- **A global "no consumer may name any other skill" rule** — rejected: it cannot deterministically
  distinguish a producer leak from a legitimate delegation (executor → `/plan-one-lean`) and would
  false-positive heavily. The curated consumer→producer map keeps false positives at zero.
- **Extracting plan-one-lean's interview pattern to a shared skill-ref** — unnecessary: the interview
  bullets are already inlined in `plan-one-lean`, so the fix is just dropping the "reuse plan-writer's
  pattern" cross-reference lead-in.

## Risks & Edge Cases

- **500-line limit on `runner-queue`** — handled by the no-marker design; the only edit there is a
  one-line reword. Re-check `wc -l` stays ≤ 500.
- **Lint rule must not regress existing skills** — after the prose fixes, every real skill must pass
  `./bin/cog skill-lint`. The new rule scans prose only (skipping fenced code blocks) and keys off
  `name:`, so non-consumer skills are unaffected.
- **Markdownlint MD040** — every fenced block in the new ADR and reference section must declare a
  language (`text` when none applies).
- **ADR numbering** — `0026` is currently free; if a concurrent change claims it, use the next free
  number and update the cross-links.

## Completion

When the round is done, set it `done` in this plan's `queue-rounds.yaml` and set this plan `done` in
the top-level `.implementation-plans/queue-plans.yaml`. Nothing moves on disk.
