# Worker Dispatch

This reference defines the coordinator-owned brief and dispatch shapes.

## Capability Extraction

Objective: produce the public capability bundle and private bundle under `RUN_DIR` from read-only
source observation.

Brief contents:

- source path and read-only access boundary;
- public bundle output directory;
- private bundle output directory;
- capability contract path;
- leakage policy path;
- target-independent behavior priorities from the interview.

Postconditions:

- public bundle files exist and are non-empty;
- private denylist exists and is non-empty when source tokens were observed;
- `cog round-req stamp <public-bundle-dir> --json` has assigned requirement IDs;
- `cog spec-leakage-scan <public-files> --source-denylist <denylist> --json` reports `ok: true`.

## Capability Review

Objective: review the public bundle for completeness, behavioral fidelity, requirement anchoring, and
leakage.

Brief contents:

- public bundle paths;
- private denylist path;
- capability contract path;
- leakage policy path;
- scanner report path.

Postconditions:

- review verdict is `pass` or `revise`;
- leakage findings are explicit and actionable;
- completeness gaps name the affected requirement IDs or sections.

## Solution Planning

Objective: produce the target solution bundle from the public capability bundle and target
references.

Brief contents:

- public capability bundle paths;
- target project path;
- target stack direction;
- user reference-doc paths;
- solution contract path;
- explicit note that source artifacts are not part of the input.

Postconditions:

- solution bundle files exist and are non-empty;
- `requirement-trace.yaml` carries every Layer-A requirement ID;
- `acceptance-test-plan.md` describes tests against the new target interface.

## Solution Review

Objective: verify that the solution bundle realizes the behavioral contract and keeps behavioral
sections source-agnostic.

Brief contents:

- solution bundle paths;
- public capability bundle paths;
- private denylist path for scoped behavioral-section scan;
- solution contract path;
- leakage policy path.

Postconditions:

- review verdict is `pass` or `revise`;
- requirement trace gaps are listed by ID;
- target-stack terms are judged only in target-design sections;
- behavioral-section scan results are recorded.
