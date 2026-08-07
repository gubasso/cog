# ADR-0026: Judge loop convergence with a prose criterion

## Context and Problem Statement

A loop declared `until:` as an expression cog evaluated after each round, while the driver separately reported an outcome through `advance` — two authorities for one verdict. With declared handles removed, `until:` was the expression dialect's last consumer and the scalars it compared no longer exist. Every framework whose steps are run by a model states its stopping criterion in prose and bounds it with a hard ceiling.

## Considered Options

- Keep the expression dialect for `until:`
- Evaluate a predicate over a reserved JSON file the agent writes
- Carry `until:` as prose the orchestrator judges

## Decision Outcome

Chosen option: `Carry until: as prose the orchestrator judges`. `until:` is a string cog stores and never parses. At each round boundary the orchestrator reads the criterion and the round's directories, then reports through `advance`, which remains the only writer of round N+1 and gains a closed `--reason` vocabulary beside its outcome. `max_rounds:` is checked inside `advance` before a round is materialized, and a round that produced no files refuses `continue` and `converged`.

## Consequences

- The expression dialect is deleted. There is no remaining evaluation site, so the grammar cannot drift back into a scripting language.
- cog still enforces the ceiling, the decision token, both closed vocabularies, and round completeness without reading one artifact. A premature `converged` stays possible and is auditable from the per-round record.
- The driver obligation forbidding a reimplemented expression language inverts into an obligation to judge `until:` and report a decision.
- A conformance fixture must script its driver's outcomes, because a real judgment is not deterministic.

## Status

Accepted
