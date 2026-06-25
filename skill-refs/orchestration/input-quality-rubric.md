# Input-Quality Rubric

Shared rubric for the executor input-evaluation gate. The `assess-input` skill applies this rubric to
classify arbitrary executor input into one of two routes, so multiple executors share one consistent,
tunable verdict. Deterministic structural signals come from `cog assess-input facts`; the judgment
below is the skill's.

## Routes

The verdict is exactly one route per input.

| Route | Meaning | Executor consequence |
| ----- | ------- | -------------------- |
| `good-input` | The input already carries a detailed, well-structured implementation plan adequate for the task size (optionally with extra prompts/context). | The executor reviews the existing plan rather than regenerating it. |
| `needs-plan` | The input is a bare prompt, or a plan too thin/partial for the task size. | The executor generates a proper plan before executing. |

## What counts as "good input"

Treat the input as `good-input` only when a reader could implement from it with little re-planning.
Strong, structured signals:

- One or more explicit plan sections: a goal/objective, context, an ordered implementation plan or
  numbered steps, acceptance criteria, and ideally assumptions, risks, or dependencies.
- Concrete scope: named files, components, commands, or interfaces — not just an outcome.
- Coverage proportional to task size: a large task needs phased/sequenced steps, not a single
  paragraph.

Default to `needs-plan` when:

- The input is a single instruction, a question, or an outcome with no steps.
- A plan exists but is a stub, an outline, or omits the steps/criteria a reader would need.
- Plan depth is clearly below what the task size demands.

## Using the deterministic signals

`cog assess-input facts` reports, per referenced file and for inline input: byte/line counts, which
canonical plan-section headings appear, and a heading count. Higher heading coverage and substantive
length are evidence toward `good-input`; near-zero plan headings is evidence toward `needs-plan`.
Signals inform the judgment — they are not a fixed threshold, and the rubric above governs ties.

## Bias toward thoroughness

When genuinely uncertain between the two routes, choose `needs-plan`: regenerating a plan is the safer
failure than executing on a thin one. Record the verdict, confidence, and the signals that drove it
through `cog assess-input record` so the call is auditable and tunable over time.
