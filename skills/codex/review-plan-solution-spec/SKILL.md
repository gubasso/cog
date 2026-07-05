---
name: review-plan-solution-spec
description: >
  Review a target solution bundle against the sanitized capability contract,
  requirement traceability, target references, and scoped behavioral leakage
  policy.
---

<!-- trigger-tests: "review-plan-solution-spec", "review solution spec" -->

# Review Plan Solution Spec

Review a target solution bundle before implementation. Keep the review producer-blind: name only the
solution bundle, public capability bundle, denylist path, and shared contracts supplied in the prompt.

## Inputs

The prompt supplies:

- solution bundle paths;
- public capability bundle paths;
- private denylist path for scoped behavioral-section scans;
- solution contract path;
- capability contract path;
- leakage policy path;
- user reference-doc paths used by the target design.

If required input is missing, return `revise` with the missing artifact list.

## Review Axes

Evaluate target architecture fit, new interface design, implementation sequencing, requirement
coverage, Layer-B acceptance tests, documentation updates, target-stack scoping, and behavioral
sections that must remain source-agnostic.

## Scoped Leakage Gate

The solution bundle intentionally contains target-stack terms. Scan only behavioral sections that
should remain source-agnostic:

```bash
cog spec-leakage-scan <behavioral-section-files> --source-denylist <denylist-path> --json
```

Any behavioral-section finding is a blocking `revise` verdict. Do not treat target architecture prose
as leakage merely because it names the chosen target stack.

## Output

Emit a structured plan-review verdict with `APPROVED`, `MODIFIED`, `REMOVED`, and `ADDED` sections.
End with `pass` only when the solution bundle is implementable, trace-complete, and clean under the
scoped leakage gate. Otherwise end with `revise` and concrete required changes.
