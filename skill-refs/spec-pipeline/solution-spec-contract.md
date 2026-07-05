# Solution Spec Contract

The solution spec binds a sanitized capability bundle to the user's chosen target stack,
architecture, conventions, and reference documentation. It is the final implementation input for the
plan-to-queue tail.

## Bundle

| File | Purpose |
| --- | --- |
| `manifest.yaml` | Bundle schema, target project path, artifact list, reference-doc paths, and validation notes. |
| `target-architecture.md` | Target stack, architecture, runtime boundaries, persistence, deployment shape, and major tradeoffs. |
| `interface-design.md` | New target interface, commands or routes, input and output contracts, and user workflows. |
| `implementation-plan.md` | Ordered build plan with files, modules, risks, verification, and rollback notes. |
| `acceptance-test-plan.md` | Layer-B acceptance tests against the new interface, generated after target interface seeding. |
| `requirement-trace.yaml` | Mapping from Layer-A requirement IDs to target design elements and Layer-B tests. |
| `docs-and-decisions.md` | Target documentation updates, project decisions, and follow-up notes. |

## Inputs

The worker receives only:

- the public capability bundle;
- user-selected target stack and architecture direction;
- user-supplied reference-doc paths reachable in the workspace or declared external docs area;
- target project constraints and output paths.

The worker does not receive source roots, private extraction notes, source tests, source command
lists, or source-specific stack tokens.

## Reference Docs

Reference documentation is an input carried by path. The solution spec records the paths it used and
summarizes the target conventions extracted from them. It does not bake external documentation into a
runtime skill dependency.

## Layer-B Acceptance Tests

Layer-B tests are generated after the new interface is seeded. They exercise the target interface,
not the source interface. Each test case carries the Layer-A requirement IDs it covers.

Run coverage before implementation handoff:

```bash
cog round-split coverage <requirement-trace.yaml> --json
```

The handoff is ready only when every Layer-A requirement ID has a target design element and at least
one Layer-B acceptance check, or an explicit documented waiver in `requirement-trace.yaml`.

## Leakage Scope

The solution bundle intentionally contains target-stack names. Apply `cog spec-leakage-scan` only to
behavioral sections that are supposed to remain source-agnostic, and use the private denylist when the
orchestrator provides it. Do not scan target architecture prose as if target stack names were source
leakage.
