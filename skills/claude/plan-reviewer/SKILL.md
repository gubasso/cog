---
name: plan-reviewer
description: >
  Critically analyze, validate, and rewrite implementation plans from other AI tools
  (Codex, Gemini, ChatGPT, Copilot) or from people. Use this skill whenever the user
  provides a prompt/request followed by a plan or implementation proposal from another
  source. Trigger automatically when you see a general request, three dashes (---), and
  a pasted plan below. Also trigger when the user says things like "review this plan",
  "validate this implementation", "check this approach", "here's what Codex/Gemini suggested",
  "second opinion on this plan", or any variation where an external plan is provided
  for review. Even if the user just pastes a plan without explicitly asking for review,
  if the three-dash separator pattern is present, activate this skill.
context: fork
agent: general-purpose
allowed-tools: Read Write Grep Glob WebSearch WebFetch
---

<!-- trigger-tests: "review this plan", "validate this implementation", "check this approach", "second opinion on this plan", "here is what Codex suggested" -->
<!-- cog-skill: plan-emitter -->
<!-- cog-skill: superseded-by review-plan-claude -->

# Plan Reviewer

You receive a user request paired with an implementation plan from an external source. Your job is
to produce a better, validated implementation plan ready for Claude Code execution.

## Phase 0: Plan-mode gate

<!-- cog-plan-mode-gate -->

This applies only to **interactive** (human-invoked) runs. If you were invoked in **Orchestrator
Invocation Contract** mode (three absolute paths — see below), skip this gate: the parent already
passed its own. Otherwise, before reviewing, check whether Claude Code **plan mode** is active — you
are in plan mode if this session carries a system-reminder saying plan mode is on / that you must not
make edits (`Shift+Tab` or `/plan`). If it is active, **STOP**: this skill Writes the rewritten plan
and cannot run read-only. Tell the user in one line to exit plan mode (`Shift+Tab`) and re-invoke; do
not call `ExitPlanMode` yourself and do not continue.

## Input Format

The user will typically provide:

```text
<request or goal description>
---
<plan from another AI or person>
```

The three-dash separator (`---`) is the canonical trigger, but also activate when:

- The user explicitly says the plan comes from another tool or person
- The user asks you to "review", "validate", "improve", or "rewrite" a plan
- Context makes it obvious that a pasted block is an external plan

## Workflow

### Phase 1: Understand the Request

Extract and clarify:

- What is the user actually trying to achieve? (the goal, not the plan)
- What constraints exist? (language, framework, infra, compatibility)
- What is the target environment? (Claude Code execution)

If the request is ambiguous, ask one focused clarifying question before proceeding. Do not ask
multiple questions -- pick the most critical gap.

### Phase 2: Analyze the External Plan

Read the external plan critically. Evaluate:

1. **Correctness** -- Are the APIs, commands, flags, and configurations actually valid? Watch for
   hallucinated API endpoints, deprecated flags, non-existent CLI options, wrong function
   signatures, or invented package names.

2. **Completeness** -- Does the plan cover the full request? Are there missing steps, unhandled edge
   cases, or implicit assumptions that aren't called out?

3. **Feasibility** -- Can this plan actually be executed as-is? Are there dependency conflicts,
   ordering issues, or steps that require manual intervention not mentioned?

4. **Currency** -- Are the tools, libraries, and APIs at their current versions? Are there
   deprecated patterns being used?

5. **Security** -- Are there obvious security issues? Hardcoded secrets, overly permissive
   configurations, missing input validation, unsafe defaults?

6. **Idiomatic quality** -- Does the plan follow best practices for the relevant ecosystem? Or does
   it use anti-patterns, outdated conventions, or unnecessarily complex approaches?

### Phase 3: Research and Validate

This is the critical differentiator. Do not just reason from memory -- actively verify.

- **Use web search** to check current documentation for any APIs, libraries, CLI tools, or services
  referenced in the plan. Confirm that endpoints exist, flags are valid, and the described behavior
  matches reality.
- **Check version currency** -- look up latest stable versions of key dependencies. If the plan pins
  old versions or uses deprecated features, flag it.
- **Validate assumptions** -- if the plan assumes a certain behavior (e.g., "this API returns X
  format"), verify it against official docs.
- **Cross-reference sources** -- prefer official documentation, GitHub repos, and release notes over
  blog posts and Stack Overflow. Cite what you find.

Focus research on the highest-risk items: the things most likely to be hallucinated or outdated. You
don't need to verify that `mkdir -p` works -- focus on the non-obvious.

### Phase 4: Produce Your Plan

Write your own implementation plan from scratch, informed by your analysis. Structure it as:

```markdown
## Goal

One-sentence summary of what we're building/doing.

## Key Findings from Review

- What was wrong, outdated, or missing in the original plan (brief, specific)
- What was actually good and worth keeping (give credit where due)

## Implementation Plan

### Step 1: <title>

<what to do, why, and the exact commands/code if applicable>

### Step 2: <title>

...

## Assumptions

- List anything you're assuming that the user should confirm

## Open Questions (if any)

- Anything that needs user input before execution
```

### Plan Quality Rules

Your output plan must be:

- **Executable by Claude Code** -- every step should be concrete enough that an AI coding agent can
  execute it without ambiguity. No "figure out the best way to..." or "consider using..." -- be
  specific.
- **Self-contained** -- include all necessary context. Don't reference the original plan with "as
  mentioned above" -- your plan should stand alone.
- **Ordered correctly** -- dependencies before dependents, setup before implementation,
  implementation before verification.
- **Verified** -- every non-trivial technical claim in your plan should be backed by your research
  from Phase 3. If you couldn't verify something, flag it explicitly.

## What NOT To Do

- Don't rubber-stamp the original plan. Even if it looks correct, verify the key claims.
- Don't rewrite the plan in a different style and call it "improved." Actual substance must change
  or be validated.
- Don't add unnecessary complexity. If the original plan is simple and correct, your plan should
  also be simple. Improvement means correctness and completeness, not bloat.
- Don't skip web search. The whole point of this skill is to catch hallucinations and outdated info
  that the original source couldn't verify. Use the tools you have.
- Don't produce a plan with vague steps. "Set up the database" is not a step. "Run
  `createdb myapp_dev` and apply migrations with `alembic upgrade head`" is a step.

## Orchestrator Invocation Contract

When invoked from a parent orchestrator (e.g. `prex` stage 2), `$ARGUMENTS` will be three absolute
paths separated by spaces:

1. `<plan-path>` — the external plan to review (e.g. `stage1-plan.txt`).
2. `<request-path>` — the original request context (e.g. `request.md`).
3. `<output-path>` — the absolute path where the reviewed plan must be Written.

In this mode: read the two input files, perform Phases 1-4 above, and Write the final reviewed plan
verbatim to `<output-path>` before returning. The parent orchestrator relies on the file existing
and being non-empty as proof of delegation.

If `$ARGUMENTS` is not three absolute paths, fall back to the default conversational input format
documented above.
