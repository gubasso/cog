# ADR-0080: Cog-owned, boundary-finalized review-loop terminal step

## Context and Problem Statement

A `review-loop` worker dispatched by `executor-prex` finished its review work but ended its turn without running its terminal step, so `summary.md` and the `REVIEW_LOOP_OK` result line were never produced and the caller fell back to ad-hoc agent re-dispatch. The `cog` machinery was already deterministic; the one non-deterministic hinge was that the LLM worker had to _remember_ to run the terminal command, and it stopped in the skip window after the work looked done. This class of non-determinism had to be eliminated at the orchestrated boundary that a user launches.

## Considered Options

- Leave the skippable ceremony and rely on caller detection plus bounded agent re-dispatch.
- A worker-side Stop hook that blocks the subagent from ending without `summary.md`.
- Convert the terminal step into a cog-owned postcondition the caller finalizes deterministically.

## Decision Outcome

Chosen option: **cog-owned, boundary-finalized terminal step** — the worker maintains the narrative body (`summary-body.md`) and reason (`termination-reason.txt`) as durable per-round artifacts and terminates with one command, `cog review-loop-summary finalize --run-dir <dir>`; if the worker still returns without `summary.md`, the `executor-prex` boundary runs `finalize` itself (plain Bash, no agent re-dispatch). `finalize` is idempotent and fails closed when no body exists, so `cog` never fabricates a narrative. A `terminal-contract` `cog skill-lint` rule and a uniform `<!-- cog-terminal-contract: <TOKEN> -->` marker keep the class visible and forbid reintroducing a skippable self-emit ceremony. The worker-side Stop hook was rejected because its registration lives in external harness settings, outside repository self-containment (ADR-0071).

## Consequences

- Good: the terminal step is deterministic mechanics owned by `cog`, extending ADR-0046/ADR-0009; the bespoke re-dispatch recovery is deleted and cannot drift back.
- Good: enforcement is class-wide, so type-2 "model must remember to emit" workers cannot reappear.
- Bad: the type-1 vs type-2 distinction and the curated worker/boundary set live in `cog skill-lint` and must be updated when a new terminal-contract worker is added.

## Status

Implemented — `lib/commands/cmd_review_loop_summary.sh` (`finalize`/`set-reason`), `lib/commands/cmd_skill_lint.sh` (`terminal-contract` rule), `skills/claude/review-loop/SKILL.md`, and `skills/claude/executor-prex/references/review-loop.md`. Extends ADR-0046 and ADR-0009; relates to ADR-0070 and ADR-0071.
