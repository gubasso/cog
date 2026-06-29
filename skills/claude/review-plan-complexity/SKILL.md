---
name: review-plan-complexity
description: >
  Grade one implementation plan, round, or prose fragment against the shipped
  complexity rubric and write a structured a-priori complexity report.
argument-hint: "<input-path-abs> <output-path-abs>"
disable-model-invocation: true
allowed-tools: Bash Read Write Grep Glob
---

<!-- trigger-tests: "review-plan-complexity", "grade this plan complexity", "write a complexity report" -->
<!-- cog-skill: plan-emitter -->

# Review Plan Complexity

Grade one implementation input before execution. The input may be a plan README, a round file, or a
fragment. The skill keeps scoring judgment in prose and delegates deterministic extraction,
requirement parsing, and reference resolution to `cog`.

## Inputs

`$ARGUMENTS` is normally exactly two absolute paths:

1. `<input-path-abs>` - the readable input to grade.
2. `<output-path-abs>` - the report path to write.

If the two-path shape is missing, continue conversationally only when the user supplied a readable
input and an explicit destination. Ask one focused clarification when either path is ambiguous.

## Reference Resolution

Resolve the shipped references at point of use:

```bash
RUBRIC_PATH="$(cog skill-refs path plan-rounds/complexity-rubric.md)"
CONTRACT_PATH="$(cog skill-refs path plan-rounds/round-splitting-contract.md)"
```

Read both references before scoring. Use the rubric axes, weights, floors, clarity gate, report
schema, and seam guidance. Use the contract for requirement-ID and seam-hint shape.

## Phase 1: Extract Signals

Run the deterministic extractor:

```bash
EXTRACT_JSON="$(cog plan-complexity extract "$INPUT_PATH" --json)"
REQ_JSON="$(cog round-req list "$INPUT_PATH" --json || true)"
```

Use `EXTRACT_JSON` as signal input, not as the final score. If `REQ_JSON` reports untagged
requirements, set `requirements_stamped: false` and include a recommendation to run
`cog round-req stamp` before splitting. Do not stamp or mutate the input.

## Phase 2: Score

Score the seven rubric axes from the input prose, extracted signals, and reference criteria:

- blast radius
- coupling
- behavioral surface
- test burden
- uncertainty
- slice quality
- operational risk

Apply the rubric's weights, floors, and clarity gate. Produce the final grade from the valid grade
set: `Trivial`, `Low`, `Moderate`, `High`, `Very High`, `Extreme`, or `Unscorable`.

## Phase 3: Split Signal

Determine `splittable` and `seam_hints`.

When requirements are stamped, each seam hint uses ID partitions:

```yaml
seam_hints:
  - label: api-vs-tests
    connascence: name
    left:
      label: api-surface
      requirement_ids: [R1, R2]
    right:
      label: test-and-docs
      requirement_ids: [R3, R4]
```

When requirements are unstamped, use normalized requirement text labels instead, set
`requirements_stamped: false`, and recommend `cog round-req stamp "$INPUT_PATH" --json`.

## Phase 4: Emit Report

Write the report to `<output-path-abs>` using the rubric and contract report schema. Include:

- grade
- score
- axis_scores
- drivers
- splittable
- seam_hints
- requirements_stamped
- deterministic_extract
- recommendation

The report is YAML. Create parent directories when needed. Re-read the output after writing and
confirm it is non-empty.

## Guardrails

- Keep the skill read-only with respect to the input.
- Name seams and requirement partitions; do not split files.
- Keep parsing, requirement listing, and signal extraction behind `cog`.
