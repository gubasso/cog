---
name: plan-claude
description: >
  Build one lean implementation plan interactively with Claude, using the
  persisted research shelf for reusable context and saving the final plan
  through cog plan-doc.
model: opus
effort: high
argument-hint: "[--output <abs.md>] [--research-root <dir>] <orientation/focus/goal>"
disable-model-invocation: true
allowed-tools: Bash Read Write Grep Glob AskUserQuestion
---

<!-- trigger-tests: "plan-claude", "build a lean implementation plan", "save one plan through plan-doc" -->
<!-- cog-skill: plan-emitter -->

# Plan Claude

Build one lean, self-contained implementation plan. This skill behaves like native planning:
research reusable context, interview until the shape is clear, emit the plan to screen, and save one
markdown artifact through `cog plan-doc`.

<!-- cog-plan-mode-gate -->
**Phase 0: Plan-mode gate.** If Claude Code **plan mode** is active (a system-reminder says plan mode
is on / that you must not edit; `Shift+Tab` or `/plan`), **STOP** before parsing args, researching,
interviewing, or writing. Tell the user in one line to exit plan mode (`Shift+Tab`) and re-invoke; do
not call `ExitPlanMode` yourself.

## Inputs

- `$ARGUMENTS` - required orientation, focus, or goal for the plan.
- Optional leading `--output <abs.md>` - save to this absolute markdown path instead of the default
  cog runtime artifact path.
- Optional leading `--research-root <dir>` - use this research shelf root. It is passed to
  `cog research-shelf` as `--root <dir>` and to `cog plan-doc save` as `--research-root <dir>`.

If the orientation is missing or materially ambiguous after reading the current conversation, ask one
focused clarification with `AskUserQuestion` before doing deeper work.

## Phase 1: Parse Intent

Interpret only the two supported optional flags: `--output <abs.md>` and `--research-root <dir>`.
Reject unknown leading flags with a short error. The text left after supported flags is the
orientation. Use the current workspace as `REPO_ROOT`.

Derive or validate the title slug through `cog`; the helper owns slug normalization and reserved-name
checks:

```bash
cog plan-slug --text "$ORIENTATION" --json
```

Use the slug result only to detect a reserved name and sanity-check the title; the human-readable
title (not the slug) is the value passed to `cog plan-doc save --title`.

## Phase 2: Research Shelf

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
cog research-shelf record --topic-tags "$TAGS" --source-json "$SOURCE_JSON" --summary "$SUMMARY" --revalidate-after "$DATE" --consuming-skills "plan-claude,plan-codex" --json
```

The optional `--id <id>` and `--recorded-date <date>` flags may be used when deliberately recording a
specific dated shelf entry. Do not copy old web findings into the skill body as permanent facts.

## Phase 3: Codebase Research

Read the code and docs needed to make the plan executable by a fresh implementer. Capture concrete
file paths, command surfaces, relevant signatures, existing patterns, constraints, and risks. Keep
the research scoped to the orientation; do not inventory unrelated areas.

The plan must cite current repo facts from files actually read in this phase or from shelf entries
judged reusable in Phase 2. Do not fabricate paths, APIs, commands, or line-specific behavior.

## Phase 4: Interview

Use `AskUserQuestion` for the interview loop. Reuse the `plan-writer` interview pattern:

- Start with an adaptive batch of 2-3 important questions when unresolved scope, approach, or testing
  choices materially affect the plan.
- Present concrete options with trade-offs instead of open-ended prompts when alternatives are known.
- Skip questions already settled by the conversation, shelf, or repo research.
- Treat "you decide" as valid; pick the best default and record it as a skill-chosen default.
- Ask follow-ups one at a time only where they change the plan.
- Summarize the decisions and ask for final "ready to generate?" confirmation before saving.

If the task is already fully specified, note that no interview is needed and proceed.

## Phase 5: Generate One Lean Plan

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

## Phase 6: Save And Validate

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
- Keep deterministic mechanics behind `cog` commands; prose owns sequencing, judgment, and
  interview decisions.
