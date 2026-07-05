---
name: review-plan-capability-spec
description: >
  Review a sanitized capability bundle for behavioral completeness,
  requirement anchoring, public/private separation, and deterministic leakage
  findings.
---

<!-- trigger-tests: "review-plan-capability-spec", "review capability spec" -->

# Review Plan Capability Spec

Review a capability bundle before target solution planning. Keep the review producer-blind: name only
the public bundle, private denylist, and shared contracts supplied in the prompt.

## Inputs

The prompt supplies:

- public capability bundle paths;
- private denylist path;
- capability contract path;
- leakage policy path;
- scanner report path when one already exists.

If required input is missing, return `revise` with the missing artifact list.

## Deterministic Leakage Gate

Run the scanner on public artifacts:

```bash
cog spec-leakage-scan <public-files> --source-denylist <denylist-path> --json
```

Any finding is a blocking `revise` verdict. Include the finding category, file, line, token, and
reason in the review output.

## Review Axes

Evaluate bundle structure, public/private separation, requirement IDs, scenario coverage, domain
concepts, state transitions, invariants, error semantics, retention obligations, open questions, and
leakage not caught by token scanning.

## Output

Emit a structured plan-review verdict with `APPROVED`, `MODIFIED`, `REMOVED`, and `ADDED` sections.
End with `pass` only when the bundle is complete enough for target design and the leakage gate is
clean. Otherwise end with `revise` and concrete required changes.
