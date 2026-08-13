---
name: plan-vetted
description: >
  Produce one vetted implementation plan through dual-engine planning: evaluate the
  input, then generate a plan when it is thin (needs-plan) or multi-review it when it
  is already detailed (good-input), writing the vetted plan to a caller-supplied output.
argument-hint: "<prompt-or-plan-path> [--output <abs.md>]"
disable-model-invocation: true
allowed-tools: Bash Read Write Edit Agent Grep Glob
---

<!-- trigger-tests: "plan-vetted", "produce one vetted plan", "vetted dual-engine plan", "generate or multi-review a plan" -->
<!-- cog-skill: plan-emitter -->
<!-- cog-skill: input-fidelity -->

# Plan Vetted

Produce one vetted implementation plan through an input-evaluation gate plus dual-engine planning. The gate decides whether the input already carries a good plan or needs one built; a dual-engine producer (two strong models drafting or reviewing independently, then a synthesized best-of-both) does the vetting, so neither route needs a separate review pass. This skill owns sequencing and judgment, and judges the input gate in its own context. Run directory setup, input classification, verdict persistence, canonical artifact paths, and the final export stay behind `cog`. This is a Claude-only coordinator: its producers run Claude and Codex together.

**Context-brief gate.** Before dispatching to any fresh-context worker, build and validate its input brief per `$(cog skill-refs path orchestration/context-brief-gate.md)` — build it with `cog context-brief build --request` and confirm it with `cog context-brief validate`.

## Inputs

`$ARGUMENTS` is a prompt/task description or an existing readable regular `.md` plan path, optionally followed by `--output <abs.md>`. The `--output` path is where the vetted plan is exported for the caller; the remaining tokens are the input. When `--output` is absent, report the canonical `prepared-plan.md` path instead.

Delegate classification and run setup to `cog executor`:

```bash
cog executor init --executor plan-vetted --engine claude --input <prompt-or-plan> --json
```

Use the run directory and canonical artifact path it returns (`prepared-plan.md`). For prompt input it writes `request.md`; for plan input it writes `plan-source` with the supplied plan path.

## Input Evaluation (gate)

Judge the route here, in this context. The input is already present, so the verdict costs one command and one judgment call.

Write the original input verbatim to `<run-dir>/assess-input-source.md`, identify every readable plan file it references, and gather the deterministic signals:

```bash
cog assess-input facts --input-file <run-dir>/assess-input-source.md --file <each referenced plan> --json
```

Apply the rubric at `$(cog skill-refs path orchestration/input-quality-rubric.md)` to the input and those signals. Higher heading coverage and scope-proportional depth favor `good-input`; near-zero plan structure favors `needs-plan`. When genuinely uncertain, choose `needs-plan`. Persist the verdict so the call stays auditable and tunable:

```bash
cog assess-input record --run-dir <run-dir> --route <needs-plan|good-input> --confidence <high|medium|low> --rationale "<one line>" --signal max_heading_count=<n> --signal plan_files=<n> --json
```

`record` writes `<run-dir>/assess-input.json` and fails closed, so its own output is the confirmation.

Both producers are dual-engine Claude coordinators. The `needs-plan` generator runs as a fresh full run that spawns its own engines — a `claude-delegate` Agent, or an inline-chain in this coordinator's context so its interview reaches the operator; the `good-input` reviewer is delegated through the Agent tool. Each keeps its inner opposite-engine Codex worker forked.

## Context Brief

Build the producer's input as a validated context brief per `$(cog skill-refs path orchestration/context-brief-contract.md)`. For plan input, first write the supplied-plan source context verbatim and in full to `<run-dir>/request.md` (init writes it for prompt input). Scaffold the authored body, fill it from the whole session — a well-oriented **Objective**; **Output Format**; **Boundaries**; **Context & Decisions** carrying the full substance; **Artifacts** inline when load-bearing or pointed-to when large; **Effort Guidance**; **Not Evaluated** — keeping your own verdict out, then build the brief from the raw request:

```bash
cog context-brief template --out "<run-dir>/brief-body.md"
# fill <run-dir>/brief-body.md per the contract, then:
cog context-brief build --request "<run-dir>/request.md" --body "<run-dir>/brief-body.md" --out "<run-dir>/brief.md"
```

`build` attaches the request verbatim and fails closed unless every section is present and filled. Pass `<run-dir>/brief.md` as the orientation/context in the producer delegation below.

## Prepare The Plan

Write the prepared plan to `<run-dir>/prepared-plan.md`.

- **`needs-plan` → generate (`/plan-multi`).** Run `/plan-multi` as a fresh full run that spawns its own dual engines — a foreground `claude-delegate` Agent, or an inline-chain (read `$HOME/.claude/skills/plan-multi/SKILL.md` and follow it in this coordinator context) — never through the `Skill` tool, which refuses `plan-multi`'s `disable-model-invocation`. Pass `--output <run-dir>/prepared-plan.md` and `<run-dir>/brief.md` as the complete orientation/context (the validated context brief built above), running both engines (not `--solo`). `plan-multi` interviews only in its coordinator and forbids its workers from asking, so its inner opposite-engine Codex draft stays a forked isolation boundary. The operator interview is preserved either way: inline-chaining lets `plan-multi`'s `AskUserQuestion` reach the operator directly, and a `claude-delegate` run works from the decisions the brief already settled. The coordinator's own verdict stays withheld from the forked review, where bias isolation matters.

- **`good-input` → multi-review (`/review-plan-multi`).** Delegate to a foreground Claude subagent through the Agent tool that reads `$HOME/.claude/skills/review-plan-multi/SKILL.md` and follows it. The fork is deliberate and survives the inline-by-default rule in `$(cog skill-refs path orchestration/orchestration-patterns.md)`: this coordinator withholds its own verdict, so the reviewer must form an independent judgment in a context that never saw it. Pass the plan under review (the supplied plan path for plan input, or `<run-dir>/request.md` for prompt input) plus `<run-dir>/brief.md` as the request brief it is reviewed against. The subagent runs both engines and returns the absolute path of its definitive vetted review. Adopt that review as the prepared plan:

  ```bash
  cog executor adopt-prepared --run-dir <run-dir> --from <returned-review-path> --json
  ```

After this stage, verify that `<run-dir>/prepared-plan.md` exists and is non-empty before continuing.

## Output

When `--output` was supplied, export the canonical prepared plan to it:

```bash
cog executor export-prepared --run-dir <run-dir> --output <output> --json
```

Return two lines: the output path (the exported `--output` when supplied, otherwise `<run-dir>/prepared-plan.md`) and the route (`needs-plan` or `good-input`). A `good-input` result is an annotated review of the supplied plan (APPROVED/MODIFIED/ADDED/REMOVED); a consumer implements the reconciled plan it specifies.

## Error Handling

At every boundary, verify the durable postcondition before advancing:

- Gate: `cog assess-input record` returns a route of `needs-plan` or `good-input`.
- Prepare: `prepared-plan.md` exists and is non-empty.
- Plan input: the supplied plan path exists and is readable before review.
- Output: when `--output` is supplied, the exported file exists and is non-empty.

On failure, stop and preserve the run directory artifacts. Do not infer status from prose when a `cog` command reports structured output.

## Guardrails

- Keep the gate, producer delegation, and the export foreground; never background them.
- Native Codex effort only, via `--effort`, inside the delegated producers.
- Do not run git commands unless explicitly authorized.
- Deterministic mechanics stay behind `cog executor`, `cog assess-input`, `/plan-multi`, and `/review-plan-multi`.
- This skill produces one vetted plan.
