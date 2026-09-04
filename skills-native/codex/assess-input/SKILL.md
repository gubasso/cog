---
name: assess-input
description: >
  Classify executor input as good-input (already a detailed, ready implementation
  plan) or needs-plan (a bare prompt or a plan too thin for the task), emitting a
  structured routing verdict for the executor input-evaluation gate.
---

# Assess Input

Judge whether executor input already carries a good implementation plan, and emit one routing verdict the executor consumes. This skill owns the judgment; deterministic signal extraction and verdict persistence stay behind `cog assess-input`.

The verdict is exactly one route:

- `good-input` — the input is a detailed, well-structured plan adequate for the task size (optionally with extra prompts or context). The executor reviews it rather than regenerating it.
- `needs-plan` — the input is a bare prompt, or a plan too thin or partial for the task. The executor generates a proper plan first.

## Inputs

The prompt provides `--run-dir <dir>` followed by the original executor input, verbatim. The input may be free text, one or more plan file paths, directory references, or any mix. The verdict is written under `<run-dir>`.

## Phase 1: Stage And Gather Signals

Write the original input verbatim to `<run-dir>/assess-input-source.md`. Identify every readable plan file referenced in the input (a path to a readable regular `.md`, or the `.md` files inside a referenced directory).

Gather deterministic structural signals:

```bash
cog assess-input facts --input-file <run-dir>/assess-input-source.md --file <each referenced plan> --json
```

The facts report byte/line counts, which canonical plan-section headings appear, and a heading count for the inline input and for each referenced file.

## Phase 2: Judge The Route

Apply the rubric at `$(cog skill-refs path orchestration/input-quality-rubric.md)` to the input and the signals. Decide the route and a confidence of `high`, `medium`, or `low`. Higher heading coverage and substantive, scope-proportional depth favor `good-input`; near-zero plan structure favors `needs-plan`. When genuinely uncertain, choose `needs-plan`.

## Phase 3: Record The Verdict

Persist the verdict, including the signals that drove it, so the call is auditable and tunable:

```bash
cog assess-input record --run-dir <run-dir> --route <needs-plan|good-input> --confidence <high|medium|low> --rationale "<one line>" --signal max_heading_count=<n> --signal plan_files=<n> --json
```

Confirm the artifact with `cog assess-input validate <run-dir>/assess-input.json`. Return one line stating the route and the verdict path.

## Guardrails

- Deterministic signal extraction and verdict persistence stay behind `cog assess-input`.
- Write only under the run directory; do not modify repository files.
- Emit exactly one route per input.
