# ADR-0011: Directory plan queue format

## Context and Problem Statement

The plan-writer family now needs a durable format that supports large work, independent domain
streams, and queue-driven execution without special cases. Earlier single-file plans, capped round
counts, and generic queue filenames created ambiguity between the repo-wide plan ledger and a plan
directory's executable rounds.

## Considered Options

- Keep single-file and directory plans, with a fixed round cap.
- Keep directory plans but retain generic `QUEUE.yaml` filenames.
- Require directory plans, uncapped rounds, two-layer decomposition, and named queue files.

## Decision Outcome

Chosen option: **require directory plans, uncapped rounds, two-layer decomposition, and named queue
files**. Every implementation plan is now a directory; the single-file / Template E format is
retired. Round count is scope-driven and uncapped. Layer 1 is a domain split that produces flat
sibling plan directories connected by top-level `depends_on`; Layer 2 grades each directory and
splits it into uncapped rounds. Queue files are named `queue-plans.yaml` at the plan-tree root and
`queue-rounds.yaml` inside each plan directory.

## Consequences

- Good: plan state has one shape, large work can be split by domain before per-directory rounds, and
  queue filenames identify their role.
- Good: queue consumers can distinguish the repo-wide plan ledger from executable round queues.
- Bad: existing producer, consumer, docs, tests, and live plan data must migrate away from the old
  `QUEUE.yaml` and single-file assumptions.

## Status

Accepted. Supersedes the queue-filename terminology of
[ADR-0007](0007-in-session-subagent-delegation.md) and records the plan-format decisions
(directory-only plans, uncapped rounds, two-layer decomposition, and queue rename) that previously
lived outside the ADR set.
