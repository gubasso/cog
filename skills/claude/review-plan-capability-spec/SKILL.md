---
name: review-plan-capability-spec
description: >
  Review a sanitized capability bundle for behavioral completeness,
  requirement anchoring, public/private separation, and deterministic leakage
  findings.
argument-hint: "<validated-brief-path>"
disable-model-invocation: true
allowed-tools: Bash Read Grep Glob
---

<!-- trigger-tests: "review-plan-capability-spec", "review capability spec", "audit capability bundle leakage" -->
<!-- cog-skill: plan-emitter -->

# Review Plan Capability Spec

Review a capability bundle before target solution planning. Keep the review producer-blind: name only
the public bundle, private denylist, and shared contracts supplied in the brief.

## Inputs

`$ARGUMENTS` is a validated context brief path. The brief supplies:

- public capability bundle paths;
- private denylist path;
- capability contract path;
- leakage policy path;
- scanner report path when one already exists.

If the brief is missing or invalid, stop and ask the caller for a validated brief path.

## Deterministic Leakage Gate

Run the scanner on public artifacts:

```bash
cog spec-leakage-scan <public-files> --source-denylist <denylist-path> --json
```

Any finding is a blocking `revise` verdict. Include the finding category, file, line, token, and
reason in the review output.

## Review Axes

Evaluate:

- bundle structure against the capability contract;
- public/private separation;
- requirement IDs and scenario coverage;
- domain concepts and state transitions;
- invariants and error semantics;
- retention and interop obligations;
- nonfunctional expectations;
- open questions and waivers;
- leakage not caught by token scanning.

## Output

Emit a structured plan-review verdict using the shared vocabulary:

- `APPROVED` for complete, clean material;
- `MODIFIED` for material that needs revision;
- `REMOVED` for leaked or inappropriate material;
- `ADDED` for missing behavior, invariants, scenarios, or trace entries.

End with `pass` only when the bundle is complete enough for target design and the leakage gate is
clean. Otherwise end with `revise` and concrete required changes.
