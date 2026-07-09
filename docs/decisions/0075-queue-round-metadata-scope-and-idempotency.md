# ADR-0075: Queue round metadata for scope-guard and cross-round idempotency

## Context and Problem Statement

Two failure modes from a live `runner-plan` run had no first-class signal. First, a round scoped to 3
files rewrote 258; nothing flagged the runaway before commit and a human caught it by eyeballing the
diff. Second, a re-deploy round was a silent no-op because an earlier round had already deployed the
same overlay; there was no cross-round idempotency signal. Both need the queue to carry a round's
declared intent and the CLI to compare actuals against it.

## Considered Options

- Leave scope and idempotency to human review of each diff (what failed).
- Add a separate sidecar file per round (extra surface, drifts from the queue).
- Extend the existing rounds-queue entry with optional metadata the runner enforces via `cog`.

## Decision Outcome

Chosen option: **optional rounds-queue metadata + runner enforcement.** `fn_queue.sh` accepts and
shape-validates three optional per-round fields without requiring them: `scope: {max_files, max_lines}`,
`artifacts: [{type, path}]` (what the round deploys), and `idempotency_check: [{type, path}]` (what it
expects already present). A surgical `cog queue-status-set` preserves them across status flips. Two
verbs enforce them. `cog review-scope check --max-files --max-lines` measures the whole working-tree
changeset (staged, unstaged, untracked) and exits non-zero with a verdict on breach; the runner runs it
before committing and STOPs on breach. `cog review-queue-rounds-check-idempotency --queue --round` scans
earlier rounds' declared `artifacts` for a match against the target round's declared artifacts and
`idempotency_check`, returning `already_deployed` items; the runner records each as `NO_OP_ARTIFACT`
after the boundary. The idempotency command is a standalone dash-named command, matching the existing
`review-queue-rounds-scan`/`-verify` family (not a subverb).

## Consequences

- Good: a runaway diff is caught before commit; a cross-round no-op is reported, not silent; the queue
  stays the single source of round intent.
- Bad: line counts exclude untracked-file content (not in `git diff --numstat`), so the file count is
  the primary runaway signal there; the fields are opt-in, so an unannotated round gets no guard.

## Status

Implemented — enacted in `lib/functions/fn_queue.sh`, `lib/commands/cmd_review_scope.sh`,
`lib/functions/fn_review_queue_rounds.sh`,
`lib/commands/cmd_review_queue_rounds_check_idempotency.sh`, and `runner-plan`. Shares this decision
across the scope-guard (WS2) and idempotency registry (WS4).
