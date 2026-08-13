# Plan-input gate

Single source of truth for the plan-input gate. Every `review-plan-*` skill that reviews an implementation plan document carries a short in-body imperative that points here and honors it with a real `cog plan-gate check` call; this file owns the full protocol. Resolve it at point of use with `cog skill-refs path plan-quality/plan-input-gate.md`.

The gate exists because a plan reviewer given a bare prompt will review the prompt. That produces a confident annotated review of something that was never a plan, and it hides the real problem: no plan exists yet. Building the plan is the user's call, not the reviewer's.

## Directive

Before any review work — before reading for judgment, before building a context brief, and before dispatching to any fresh-context worker — confirm the input is a reviewable plan:

```bash
cog plan-gate check <plan-file|plan-dir>          # or: --input-file <abs staged inline text>
```

The gate classifies the input as `file`, `dir`, or `inline`, and returns `verdict: plan` or `verdict: insufficient`. It fails closed with `$EX_DATAERR`.

On `insufficient`, **STOP.** Do not review, do not partially review, and do not write the plan yourself. Report the gate's `reason` and `missing` in one short block, then ask the user to build a plan first and name the way to do it — `/plan-oneshot` for one lean plan, `/plan-multi` or `/plan-vetted` for a cross-checked one, `/plan-oneshot-codex` to have Codex write it. Resume the review only when the user comes back with a plan that clears the gate.

## Boundary

The gate decides shape; review judgment stays in the skill. It passes an input that carries the strict `cog plan-doc` heading contract, and also an input that is genuinely a plan in some other producer's shape — a heading, at least three canonical plan sections, and at least one plan-body section. A directory passes when at least one markdown source in it is a plan; the other files are supporting notes. That floor is deliberately low: it rejects a prompt, a stub, and a status surface, and it never adjudicates whether a real plan is a _good_ plan.

Depth and adequacy are separate questions answered elsewhere. `plan-quality/plan-quality-principles.md` is what a review checks a plan's content against once it is through the gate, and `orchestration/input-quality-rubric.md` is the `good-input` / `needs-plan` routing judgment an executor makes — that route may legitimately regenerate a thin plan, where this gate hands the decision back to the user.
