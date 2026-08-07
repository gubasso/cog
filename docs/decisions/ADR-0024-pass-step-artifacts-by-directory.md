# ADR-0024: Pass step artifacts by directory

## Context and Problem Statement

A step declared its outputs as typed handles: a bare filename for a file, a typed object for a scalar the agent wrote to `scalars.json`. Callers referenced them as `${{ steps.<as>.outputs.<handle> }}`, and a receipt failed the step when a declared artifact was missing or mistyped. That made cog a runtime judge of content produced by a probabilistic agent, and bought static checkability the producer cannot honour.

## Considered Options

- Keep declared handles with runtime enforcement
- Keep declared handles but check them only at lint time
- Pass whole step directories along `needs:` edges

## Decision Outcome

Chosen option: `Pass whole step directories along needs: edges`. Each step writes its artifacts into its own directory under the run directory, and `needs:` hands every upstream directory to the step that depends on it. Declared inputs and outputs remain in a step file as description, aligned against its skill at lint time and never enforced at run time. The skill owns what it reads and produces.

## Consequences

- The expression dialect, `scalars.json`, the implicit `stdout` handle, and the reserved output filenames are removed. A workflow file becomes a dependency graph rather than a data-flow specification.
- Data flow is no longer readable from the workflow file. A reader learns it from the skills, and step-to-skill alignment becomes the only static check, so it has to exist.
- Q-004 dissolves rather than resolves, because with no declared inputs the launch surface is the task and there is no user input flag left to grant or withhold.

## Status

Accepted
