---
name: plan-solution-spec
description: >
  Hydrate a sanitized capability bundle into a target solution bundle using
  user-supplied target stack, architecture direction, and reference-doc paths.
argument-hint: "<validated-brief-path>"
disable-model-invocation: true
allowed-tools: Bash Read Write Grep Glob
---

<!-- trigger-tests: "plan-solution-spec", "hydrate capability spec", "create solution spec" -->
<!-- cog-skill: plan-emitter -->

# Plan Solution Spec

Produce the target solution bundle described by
`$(cog skill-refs path spec-pipeline/solution-spec-contract.md)`. The input is a sanitized public
capability bundle plus target references. Treat the bundle as the source of behavioral truth.

## Inputs

`$ARGUMENTS` is a validated context brief path. The brief supplies:

- public capability bundle paths;
- target project path;
- target stack and architecture direction;
- user-supplied reference-doc paths;
- solution contract path;
- leakage policy path;
- output directory under `RUN_DIR`.

If the brief is missing or invalid, stop and ask the caller for a validated brief path.

## Output

Write the solution bundle files:

- `manifest.yaml`
- `target-architecture.md`
- `interface-design.md`
- `implementation-plan.md`
- `acceptance-test-plan.md`
- `requirement-trace.yaml`
- `docs-and-decisions.md`

The solution bundle binds target choices from the user's references. It does not infer behavior from
any private extraction notes or source-specific token list.

## Hydration

Use the public capability bundle to define behavior and the user references to define target shape:

- target architecture and runtime boundaries;
- persistence, retention, and interop choices;
- new interface design;
- implementation plan;
- Layer-B acceptance tests against the new interface;
- documentation and decision updates.

The target interface may use new command names, routes, modules, and tests that fit the target stack.
Preserve Layer-A requirement IDs in `requirement-trace.yaml`.

## Coverage Gate

Before returning, verify traceability:

```bash
cog round-split coverage "$SOLUTION_BUNDLE_DIR/requirement-trace.yaml" --json
```

If coverage fails, revise `requirement-trace.yaml`, `implementation-plan.md`, or
`acceptance-test-plan.md` until every requirement is covered or explicitly waived.
