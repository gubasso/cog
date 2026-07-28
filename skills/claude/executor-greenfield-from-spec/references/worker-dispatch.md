# Worker Dispatch

This reference defines the coordinator-owned brief and dispatch shapes.

## Capability Extraction

Objective: produce one merged public capability bundle and the private bundle under `RUN_DIR` from read-only observation of all sources.

Brief contents:

- source paths and read-only access boundary;
- per-source purpose map — for a specific-feature source, which capability to extract; for a general-inspiration source, which architectural qualities to abstract;
- explicit instruction that inspiration-source architecture is abstracted into sanitized capability and nonfunctional expectations, never carried as concrete source layout or naming;
- public bundle output directory;
- private bundle output directory;
- capability contract path;
- leakage policy path;
- target-independent behavior priorities from the interview;
- the operator's extraction-phase interview decisions, carried under _Context & Decisions_.

Postconditions:

- merged public bundle files exist and are non-empty;
- the union `source-leakage-denylist.txt` exists and is non-empty when any source exposed tokens;
- `cog round-req stamp <public-bundle-dir> --json` has assigned requirement IDs;
- `cog spec-leakage-scan <public-files> --source-denylist source-leakage-denylist.txt --json` reports `ok: true`.

## Capability Review

Objective: review the public bundle for completeness, behavioral fidelity, requirement anchoring, and leakage.

Brief contents:

- public bundle paths;
- union `source-leakage-denylist.txt` path;
- capability contract path;
- leakage policy path;
- scanner report path;
- the operator's capability-phase interview decisions, carried under _Context & Decisions_.

Postconditions:

- review verdict is `pass` or `revise`;
- leakage findings are explicit and actionable;
- inspiration-source architecture is abstracted — no concrete source layout or naming in the bundle;
- completeness gaps name the affected requirement IDs or sections.

## Solution Planning

Objective: produce the target solution bundle from the public capability bundle and target references.

Brief contents:

- public capability bundle paths;
- target project path;
- target stack direction;
- user reference-doc paths;
- solution contract path;
- the operator's solution-phase interview decisions, carried under _Context & Decisions_;
- explicit note that no source artifacts from any source — specific-feature or general-inspiration — are part of the input.

Postconditions:

- solution bundle files exist and are non-empty;
- `requirement-trace.yaml` carries every Layer-A requirement ID;
- `acceptance-test-plan.md` describes tests against the new target interface.

## Solution Review

Objective: verify that the solution bundle realizes the behavioral contract and keeps behavioral sections source-agnostic.

Brief contents:

- solution bundle paths;
- public capability bundle paths;
- union `source-leakage-denylist.txt` path for scoped behavioral-section scan;
- solution contract path;
- leakage policy path;
- the operator's solution-phase interview decisions, carried under _Context & Decisions_.

Postconditions:

- review verdict is `pass` or `revise`;
- requirement trace gaps are listed by ID;
- target-stack terms are judged only in target-design sections;
- behavioral-section scan results are recorded.
