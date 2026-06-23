# ADR-0026: Consumer skill producer-blindness

## Context and Problem Statement

A consumer skill reads a structural input — a directory layout, a YAML queue, a findings JSON shape —
and acts on it. Several consumer skills named the upstream skill that produced that input instead of
describing the input contract structurally. `runner-queue` opened with "Drive a plan-writer
implementation queue…", coupling the queue consumer to one producer even though it drives the
`.implementation-plans/` directory to completion regardless of which skill wrote the queue. Both
`review-findings` skills (Claude and Codex) named `review-lean` and `review-loop` as the
producers of their findings input rather than describing the structured-findings contract they
actually consume.

Naming the producer in consumer prose is a coupling leak: it implies the consumer only works with one
upstream, it drifts when new producers appear, and it duplicates producer identity that the input
contract already carries. The validation half of the rule was already satisfied — `runner-queue`
delegates all input parsing to `cog` subcommands — but the prose still leaked producer identity.

## Considered Options

- Leave producer names in consumer prose and rely on review to catch drift.
- Add an in-skill marker that lists allowed producers per consumer.
- Describe the structural input contract in consumer prose, keep a curated consumer-to-producer map in
  command code, and enforce blindness with a deterministic `cog skill-lint` rule.

## Decision Outcome

Chosen option: **a consumer skill depends only on its structural input contract and is blind to which
skill produced that input**. A consumer describes the contract it reads (e.g. the
`.implementation-plans/` directory structure, the shared structured-findings contract), never the
identity of the producing skill. All input validation and parsing is delegated to `cog`. Enforcement
is the `producer-blindness` rule in `cog skill-lint`, driven by a curated consumer-to-producer map
held in command code (`lib/commands/cmd_skill_lint.sh`), not by an in-skill marker — `runner-queue`'s
`SKILL.md` already sits at the 500-line lint cap, and the map belongs with deterministic mechanics.

The initial map enforces:

```text
runner-queue    -> plan-writer, plan-writer-multi
review-findings -> review-lean, review-loop
```

The rule scans mapped consumer skills for forbidden producer names — as whole skill-name tokens — in
both frontmatter `description:` text and body prose, while ignoring fenced code blocks.

## Consequences

- Good: consumers stay decoupled from upstream identity, so new producers need no consumer edits.
- Good: enforcement is deterministic and scoped — only mapped consumers are checked, and token
  matching prevents substring false positives.
- Good: the curated map lives in command code, so adding a consumer-to-producer pair never grows a
  skill body past its lint cap.
- Bad: the map is curated by hand; a new consumer must be added to the map to gain enforcement.

## Status

Implemented. The reference cases are `runner-queue` (queue consumer) and `review-findings` (findings
consumer), with enforcement by the `producer-blindness` rule in `cog skill-lint`.

## Related Decisions

- ADR-0008: skills stay probabilistic; deterministic mechanics (input parsing, the lint map) live in
  `cog`.
- ADR-0011: the directory plan-queue format is the structural input contract `runner-queue` consumes.
- ADR-0016: prefix taxonomy distinguishes producers (`plan-*`, `review-*`) from consumers
  (`runner-*`) and triage (`review-findings`).
- ADR-0019: lean, positively framed prose — describe the input contract, not the producer.
- ADR-0021: twin skill naming; producer-blindness complements the no-runtime-twin-meta rule.
- ADR-0024 / ADR-0025: reference self-containment and SoT executor delegation; producer-blindness is
  the consumer-side counterpart to those producer-side self-containment rules.
