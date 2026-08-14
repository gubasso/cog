# ADR-0031: Preflight provider preconditions before the durable job

## Context and Problem Statement

A runner classifies a job purely from durable artifacts, so an observer killed at the Bash ceiling loses nothing ([ADR-0009](./ADR-0009-orchestration-and-durable-jobs.md)). That works while the exit code means one thing. Adding `claude-runner` breaks the assumption.

`claude-session` execs the child rather than supervising it, so a status is either the wrapper's own from before the exec or `claude`'s own from after, and the two ranges overlap: 64 is both `EX_USAGE` and a legal agent exit. The wrapper writes an `err.kind` diagnostic on its own failures and never on the child's, but that discriminator lives in captured stderr prose, which is exactly the provider-owned text the runner contract refuses to parse.

The failures at issue are preconditions, not outcomes: no bound account, no resolved profile, a child below the refresh-lock version floor, a missing or refused credential. Each is a standing condition that a retry reproduces, and each is knowable before anything is spawned.

## Considered Options

- Classify a launch failure by parsing the provider's own diagnostic
- Check preconditions before launching, then treat every job status as the agent's
- Manage credentials so the precondition cannot fail

## Decision Outcome

Chosen option: `Check preconditions before launching, then treat every job status as the agent's`. A runner reports version and authentication preconditions as its own result, before it creates a durable state file. Once the job exists, its status belongs to the agent and is classified from artifacts alone, unchanged from today.

Managing credentials was rejected as out of scope by the provider-runner slice and by [ADR-0009](./ADR-0009-orchestration-and-durable-jobs.md): reporting a precondition is diagnosis, satisfying one is account management.

## Consequences

- The artifact-only classification rule keeps one meaning, so no runner parses provider prose.
- A precondition failure costs no durable state file and no run directory.
- Preflight is a second process launch per dispatch, which is accepted: it runs before any spend.
- `codex-runner` gains a preflight it does not have today; the retrofit that owned it was retired, so it is unscheduled and [Q-007](../plan/open-questions.md) tracks the `claude-runner` lane.

## Status

Accepted
