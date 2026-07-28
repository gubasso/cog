---
name: plan-split
description: >
  Split one over-ceiling implementation round into two complete child rounds
  from supplied seam hints, then write a structured split verdict.
argument-hint: "<round-path-abs> <seam-hints-path-abs> <output-path-abs>"
disable-model-invocation: true
allowed-tools: Bash Read Write Grep Glob
---

<!-- trigger-tests: "plan-split", "split this implementation round", "split an over-ceiling round" -->
<!-- cog-skill: plan-emitter -->

# Plan Split

Split one over-ceiling round into exactly two complete child rounds. The skill makes the seam judgment and authors the child prose. Deterministic requirement stamping, slug derivation, and coverage verification stay behind `cog`.

## Inputs

`$ARGUMENTS` is exactly three absolute paths:

1. `<round-path-abs>` - the parent round markdown file.
2. `<seam-hints-path-abs>` - a readable report containing seam hints.
3. `<output-path-abs>` - the split verdict path to write.

If any path is missing or not absolute, ask for corrected paths before writing.

## Reference Resolution

Resolve and read the shipped references at point of use:

```bash
CONTRACT_PATH="$(cog skill-refs path plan-rounds/round-splitting-contract.md)"
TEMPLATE_PATH="$(cog skill-refs path plan-rounds/round-templates.md)"
RUBRIC_PATH="$(cog skill-refs path plan-rounds/complexity-rubric.md)"
```

Use the contract for verdict shape and coverage semantics, Template A for child round structure, and the rubric for connascence and decomposition rules.

## Phase 1: Pick The Seam

Read the parent round and seam hints. Select the lowest-connascence acceptable seam that preserves every parent requirement. Prefer seam hints with explicit ID partitions.

Defensively stamp the parent before authoring children:

```bash
cog round-req stamp "$ROUND_PATH" --json
REQ_JSON="$(cog round-req list "$ROUND_PATH" --json)"
```

The stamp is idempotent and gives child rounds stable requirement IDs.

## Phase 2: Irreducibility Check

If no acceptable seam exists, write no child files. Emit a verdict with `split_performed: false`, a clear reason, and no child paths, then stop.

## Phase 3: Author Child Rounds

Create exactly two child round files in the parent plan directory. Derive each child slug from its seam-side label:

```bash
SLUG_JSON="$(cog plan-slug --text "$SIDE_LABEL" --json)"
```

Use content-named slugs. Do not use ordinal names.

For each child:

- Use Template A structure.
- Carry every assigned parent criterion with its original `(R<n>)` ID and text.
- Keep each parent criterion verbatim in at least one child.
- Allow a shared foundation criterion to appear in both children.
- Add new child-specific criteria only when needed for completeness.
- After both child files exist, run `cog round-req stamp` on each child so new criteria receive fresh IDs from the plan directory's current max.

Move surrounding detail to the child where it belongs. Do not mutate queue files.

## Phase 4: Verify Coverage

Run deterministic coverage over the parent and both children:

```bash
cog round-split coverage --parent "$ROUND_PATH" --children "$CHILD_A" "$CHILD_B" --json
```

If coverage fails, fix the child rounds and rerun. Do not emit a successful split verdict until coverage reports `lost: []`.

## Phase 5: Emit Verdict

Write the split verdict to `<output-path-abs>` using the round-splitting contract's verdict YAML block. Include:

- split_performed
- parent
- children
- seam
- coverage
- notes

For a successful split, include both child paths and the exact coverage JSON summary. For an irreducible input, include the reason and leave child paths empty. Re-read the output after writing and confirm it is non-empty.

## Guardrails

- Write only child round files and the verdict.
- Produce exactly two children for a successful split.
- Keep queue reconciliation with the caller.
- Keep deterministic parsing, stamping, slugs, and coverage behind `cog`.
