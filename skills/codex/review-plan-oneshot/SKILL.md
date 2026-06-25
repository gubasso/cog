---
name: review-plan-oneshot
description: >
  Review one implementation plan before concrete implementation, using the
  persisted research shelf for reusable context and saving the annotated
  review through cog plan-review.
---

# Review Plan Codex

Review one implementation plan before concrete implementation. This skill keeps review judgment,
sequencing, and annotation decisions in prose, while delegating scaffold, output-path, write, and
validation mechanics to `cog plan-review`.

## Invocation

When an orchestrator invokes this skill through `cog codex-runner`, it must pass native effort
`high`, `--access write`, `--state <file>`, never encode effort in this skill's frontmatter, and
never use a legacy `--profile`. `run-exec` launches a durable job; the orchestrator polls-and-classifies
with one verb, `cog codex-runner finalize --max-wall <secs>` — the exit code is the signal (0 ok ·
1 failed · 75 still running), so it re-runs finalize while it exits 75; duration is never judged.

```bash
cog codex-runner run-exec --mode danger --access write --effort high --prompt <file> --output <file> --events <file> --state <file> [--stderr <file>]
```

## Inputs

`$ARGUMENTS` is normally exactly three absolute paths:

1. `<plan-path-abs>` - the implementation plan to review.
2. `<request-path-abs>` - the original request or goal context.
3. `<output-path-abs>` - the annotated review artifact path.

This three-absolute-path shape is the **Orchestrator Invocation Contract**. If `$ARGUMENTS` is not
three absolute paths, fall back to conversational review only when the user supplied both a request
or goal and a plan. If either input is missing or materially ambiguous, ask one focused
clarification before continuing.

## Phase 1: Parse And Scaffold

Do not create or write the output path manually. Delegate artifact mechanics to `cog plan-review`.
The skill body references the deployed command form, plain `cog plan-review`.

For orchestrator mode, call:

```bash
cog plan-review orchestrator "$PLAN_PATH" "$REQUEST_PATH" "$OUTPUT_PATH" --json
```

For manual or non-orchestrator mode, call:

```bash
cog plan-review save --plan "$PLAN_PATH" --request "$REQUEST_PATH" --output "$OUTPUT_PATH" --repo-root "$REPO_ROOT" --json
```

The scaffold, required headings, result-line contract, and output path are owned by
`cog plan-review`; do not invent a separate artifact format. After `orchestrator` or `save` returns,
fill judgment into the existing scaffold sections and preserve the scaffold headings.

## Phase 2: Research Shelf

Read the persisted shelf before repeating research. Reuse-or-refresh is a judgment call: a shelf
entry is reusable only when its `topic-tags`, `consuming-skills`, sources, and `revalidate-after`
date fit the plan under review. The shelf command does not select entries for you.

Use these commands for shelf mechanics. There is no `research-shelf read` mode; read by listing IDs
and getting entries:

```bash
cog research-shelf init --json
cog research-shelf validate --json
cog research-shelf list --json
cog research-shelf get "$ID" --json
```

Relevant existing shelf entries tagged for `review-plan-*` include:
`rs-20260620-c3fb5f0f`, `rs-20260620-91415b5f`, `rs-20260620-cc89197b`,
`rs-20260620-5d8fd920`, `rs-20260620-321e69e0`, `rs-20260620-834d262b`,
`rs-20260620-e4129886`, `rs-20260620-f9fca421`, `rs-20260620-21b76fdc`.
Also consider `rs-20260620-e8141499` and `rs-20260620-40e45566` when their topics fit.

When relevant research is missing, stale, or too broad for the task, refresh it from appropriate
current sources and record the finding through the shelf:

```bash
cog research-shelf record --topic-tags "$TAGS" --source-json "$SOURCE_JSON" --summary "$SUMMARY" --revalidate-after "$DATE" --consuming-skills "review-plan-oneshot,executor-vetted,executor-vetted-codex,executor-prex" --json
```

Do not copy old web findings into the skill body as permanent facts.

## Phase 3: Review Axes

Review the plan adversarially before implementation. Actively verify high-risk claims against the
live repo and current official documentation; do not rely on memory for commands, APIs, package
names, model/runtime behavior, or security-sensitive guidance.

Evaluate all axes:

1. **Correctness** - Are APIs, commands, flags, paths, configurations, function signatures, and
   package names real and valid?
2. **Completeness** - Does the plan cover the full request, edge cases, rollback or migration needs,
   and expected verification?
3. **Feasibility** - Can the plan be executed as written, in the stated order, without hidden manual
   steps or impossible dependencies?
4. **Currency** - Are external tools, libraries, APIs, model/runtime facts, and docs current enough
   for this task?
5. **Security** - Does the plan avoid secrets leakage, unsafe defaults, excessive permissions,
   missing validation, and avoidable supply-chain risk?
6. **Idiomatic-fit** - Does it fit the repo's architecture, language conventions, command patterns,
   and surrounding design?
7. **Scope boundaries** - Does it stay inside the requested round and explicitly defer out-of-scope
   work?
8. **Missing dependencies** - Are prerequisite files, commands, configs, migrations, generated
   assets, or external services accounted for?
9. **Testability** - Does the plan include focused, runnable validation that matches the risk and
   blast radius?
10. **Deterministic/probabilistic-boundary compliance** - Are repeatable mechanics delegated to
    `cog` or deterministic tooling, while judgment remains in prose?
11. **Executor suitability** - Is the plan sized and ordered for the intended executor, with enough
    context for one focused implementation pass?

## Phase 4: Annotate The Plan

Use the `cog plan-review` scaffold vocabulary. Classify plan material under the matching headings:

- `APPROVED` - correct plan material that should remain.
- `MODIFIED` - plan material that should be changed before implementation.
- `REMOVED` - plan material that should not be implemented.
- `ADDED` - missing steps, checks, dependencies, or constraints that must be added.

Preserve every scaffold heading:

```markdown
# Annotated Plan Review

## Verdict

## Review Summary

## Research Shelf

## Annotated Plan

### APPROVED

### MODIFIED

### REMOVED

### ADDED

## Assumptions

## Risks
```

Judgment decides the annotations and severity. `cog plan-review validate` decides whether the
artifact shape is valid.

## Phase 5: Validate

Validate the final artifact:

```bash
cog plan-review validate "$OUTPUT_PATH" --json
```

If validation fails, fix the artifact headings or required vocabulary and validate again before
reporting completion.

## Guardrails

- Review one plan only; do not implement it.
- Keep deterministic scaffold, write, path, and validation mechanics behind `cog plan-review`.
- Do not run git commands.
