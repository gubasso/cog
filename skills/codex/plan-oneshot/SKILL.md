---
name: plan-oneshot
description: >
  Build one lean implementation plan with Codex, using the persisted research
  shelf for reusable context and saving the final plan through cog plan-doc.
---

# Plan Codex

Build one lean, self-contained implementation plan. This skill researches reusable context through
the persisted shelf, reasons over the current codebase, emits the plan to screen, and saves one
markdown artifact through `cog plan-doc`.

## Invocation

When an orchestrator invokes this skill through `cog codex-runner`, it must pass native effort
`high`, `--access write`, `--state <file>`, and never a legacy `--profile`. `run-exec` launches a
durable job; the orchestrator polls-and-classifies it with one verb, `cog codex-runner finalize
--max-wall <secs>`. The exit code is the signal (0 = ok · 1 = failed · 75 = still running); it
re-runs finalize while it exits 75. Duration is never judged.

```bash
cog codex-runner run-exec --mode danger --access write --effort high --prompt <file> --output <file> --events <file> --state <file> [--stderr <file>]
```

## Inputs

- `$ARGUMENTS` - required orientation, focus, or goal for the plan.
- Optional leading `--output <abs.md>` - save to this absolute markdown path instead of the default
  cog runtime artifact path.
- Optional leading `--research-root <dir>` - use this research shelf root. It is passed to
  `cog research-shelf` as `--root <dir>` and to `cog plan-doc save` as `--research-root <dir>`.

If the orientation is missing or materially ambiguous, ask the user one focused clarification before
doing deeper work. If the user cannot answer, pick a conservative default and record it in the plan.

## Phase 1: Research Shelf

Read the persisted shelf before repeating research. Reuse-or-refresh is a judgment call: a shelf
entry is reusable only when its `topic-tags`, `consuming-skills`, sources, and `revalidate-after`
date fit the current task. The shelf command does not select entries for you.

Use these commands for shelf mechanics. There is no `research-shelf read` mode; READ by listing IDs
and getting entries:

```bash
cog research-shelf init --json
cog research-shelf validate --json
cog research-shelf list --json
cog research-shelf get "$ID" --json
```

When `--research-root <dir>` was supplied, pass it to every `research-shelf` call as `--root "$RESEARCH_ROOT"` (research-shelf's flag is `--root`, not `--research-root`).

When relevant research is missing, stale, or too broad for the task, refresh it from appropriate
current sources and record the finding through the shelf:

```bash
cog research-shelf record --topic-tags "$TAGS" --source-json "$SOURCE_JSON" --summary "$SUMMARY" --revalidate-after "$DATE" --consuming-skills "plan-oneshot,plan-oneshot-codex" --json
```

The optional `--id <id>` and `--recorded-date <date>` flags may be used when deliberately recording a
specific dated shelf entry. Do not copy old web findings into the skill body as permanent facts.

## Phase 2: Codebase Research

Read the code and docs needed to make the plan executable by a fresh implementer. Capture concrete
file paths, command surfaces, relevant signatures, existing patterns, constraints, and risks. Keep
the research scoped to the orientation; do not inventory unrelated areas.

The plan must cite current repo facts from files actually read in this phase or from shelf entries
judged reusable in Phase 1. Do not fabricate paths, APIs, commands, or line-specific behavior.

## Phase 3: Generate One Lean Plan

Generate exactly one self-contained markdown plan. It must not use the heavy directory-plan or queue
format. The saved artifact must preserve the headings required by `cog plan-doc validate`:

```markdown
# <Plan Title>

> Artifact: plan-doc | Generated: <YYYY-MM-DD> | Repo: <absolute repo root>

## Goal

## Context

## Research Shelf

## Implementation Plan

1. ...

## Acceptance Criteria

- [ ]

## Assumptions

## Risks
```

The body must include concrete files and commands where known, dependencies and ordering, acceptance
criteria, assumptions, unresolved questions, risks, and the shelf entries reused or refreshed. Keep it
implementable by a fresh session with no access to the prior conversation.

## Phase 4: Save And Validate

Derive or validate the title slug when needed through `cog`; the helper owns slug normalization and
reserved-name checks:

```bash
cog plan-slug --text "$ORIENTATION" --json
```

Use the slug result only to detect a reserved name and sanity-check the title; the human-readable
title (not the slug) is the value passed to `cog plan-doc save --title`.

Delegate path, run-dir, output-path, and scaffold mechanics to `cog plan-doc save`. Use the default
runtime path unless the user supplied `--output <abs.md>`.

```bash
cog plan-doc save --title "$TITLE" --repo-root "$REPO_ROOT" --json
cog plan-doc save --title "$TITLE" --repo-root "$REPO_ROOT" --output "$OUTPUT" --json
```

When `--research-root <dir>` was supplied, pass it through to `cog plan-doc save`:

```bash
cog plan-doc save --title "$TITLE" --repo-root "$REPO_ROOT" --research-root "$RESEARCH_ROOT" --json
```

`cog plan-doc save` creates the scaffold and returns `output_path`; it does not accept generated plan
content on stdin. After it returns, write the generated plan content into that returned absolute path,
then validate:

```bash
cog plan-doc validate "$PLAN_DOC_PATH" --json
```

If validation fails, fix the generated plan headings and validate again before reporting completion.

## Final Response

Print the full plan to screen, then report the saved absolute path. Include any assumptions,
remaining ambiguities, and shelf entries reused or refreshed. Do not display or create any
`.implementation-plans/` directory, queue, or multi-round artifacts.

## Guardrails

- This skill writes only the one lean plan artifact returned by `cog plan-doc save`.
- Do not run git commands.
- Do not implement the plan.
- Do not create `.implementation-plans/`, `queue-rounds.yaml`, `queue-plans.yaml`, or plan
  directories.
- Keep deterministic mechanics behind `cog` commands; prose owns sequencing, judgment, and planning
  decisions.
