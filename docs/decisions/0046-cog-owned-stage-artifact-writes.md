# ADR-0046: cog-owned stage artifact writes

## Context and Problem Statement

In `executor-oneshot` and `executor-vetted`, Stage 2 (execution) runs natively in the orchestrator's own session, so the orchestrator model holds the Write tool and typed the canonical artifact path from prose (`write the report to <run-dir>/execution-report.md`), then self-attested the "exists and is non-empty" postcondition. A run was observed writing `stage2-execution.md` instead and attesting success, so the canonical artifact the summary and postconditions reference was never produced. The write path and its verification were probabilistic model judgment, not deterministic mechanics.

## Considered Options

- Keep prose instructing a literal canonical-path write, and rely on the model to follow it.
- Resolve the canonical path into a variable and have the model Write to it (still a model literal).
- Let cog own the write: the model stages report content anywhere; cog places it at the canonical name and owns the existence/non-empty gate.

## Decision Outcome

Chosen option: **cog owns the write and the gate** — the model writes report content to a working file, then `cog executor adopt --run-dir <dir> --ordinal <ordinal> --from <file>` copies it into the cog-resolved canonical slot, and `cog executor verify-artifact --run-dir <dir> --ordinal <ordinal>` fails closed on a missing or empty artifact. The canonical filename is never a model literal. The prepare artifact was already delegated through a worker's `--output`/`adopt-prepared`, so only the native execution report needed routing.

## Consequences

- Good: the canonical artifact name is deterministic; a model that mis-names its working file still yields the canonical artifact, and postconditions are non-zero-exit gates, not self-attestation.
- Good: `cog skill-lint`'s `artifact-write-ownership` rule prevents the prose leak from returning in the curated native-execution executor set.
- Bad: one more indirection (stage to a working file, then adopt) in the execution step.

## Status

Implemented. Verbs in `lib/functions/fn_executor.sh` (`adopt_artifact_json`, `verify_artifact_json`) and `lib/commands/cmd_executor.sh`; the `artifact-write-ownership` rule in `lib/commands/cmd_skill_lint.sh`; routed in `skills/claude/executor-oneshot/SKILL.md` and `skills/claude/executor-vetted/SKILL.md`. Builds on the stage-agnostic identifiers of [ADR-0040](./0040-stage-agnostic-identifiers.md).
