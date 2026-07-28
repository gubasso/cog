---
name: context-builder
description: >
  Assemble the best-constructed input for a fresh-context worker: a well-oriented
  objective, the raw request attached, and the full substantive context and artifacts
  of the session, validated against the shared context-brief contract. Runs inline in
  the caller's own context. Use when the user says "context-builder", "build a context
  brief", "assemble handoff context", or an orchestrator needs to hand structured
  context to a delegated skill, agent, or Codex worker.
argument-hint: "[--out <abs.md>] <objective / focus / original request>"
model: opus
effort: low
allowed-tools: Bash Read Write Edit Grep Glob AskUserQuestion
---

<!-- trigger-tests: "context-builder", "build a context brief", "assemble handoff context", "context brief for a worker" -->
<!-- cog-skill: input-fidelity -->

# Context Builder

Assemble one best-constructed context brief and return its validated path. The brief gives a fresh-context worker everything it needs to do its best work — a well-oriented objective, the raw request, and the full substance and artifacts of the session — while omitting the caller's own verdict so the worker stays neutral. The structural contract lives at `$(cog skill-refs path orchestration/context-brief-contract.md)`; `cog context-brief` owns the scaffold/build/validate mechanics.

This skill runs **inline in the caller's context** — it reads the live conversation to compose the brief, so it is invoked through the Skill tool, never delegated to an isolated subagent.

## Inputs

`$ARGUMENTS` accepts:

- Optional `--out <abs.md>`: where to write the finished brief.
- Required objective, focus, or original-request text identifying what the brief is for.

## Setup

Create scratch state and resolve paths:

```bash
cog rundir context-builder
```

Capture `RUN_DIR`. Use `$RUN_DIR/request.txt` for the raw request and `$RUN_DIR/body.md` for the authored sections. The finished brief goes to `--out` when given, otherwise `$RUN_DIR/context-brief.md`. Shell state does not persist between Bash calls; substitute literal paths.

## Step 1: Capture the raw request

Write the user's task prompt(s) for this work to `$RUN_DIR/request.txt`, attached as-is. `cog
context-brief build` injects this file byte-for-byte, so the raw ask is always present even after you craft an oriented objective.

## Step 2: Interview only if underspecified

Use `AskUserQuestion` only when the request is genuinely ambiguous in a way that would change the brief. When it is already clear, record that no interview was needed and proceed.

## Step 3: Gather the session substance

Research the repo and conversation with Read, Grep, and Glob. Capture the decisions and rationale, research, findings, and any generated plan or document the session produced. Capture absolute-path pointers and quoted excerpts. Reference large or external artifacts by absolute path; inline the generated plans and excerpts that are load-bearing.

## Step 4: Scaffold the body

```bash
cog context-brief template --out "$RUN_DIR/body.md"
```

This writes every authored section (everything except Original Request, which build injects).

## Step 5: Author the sections

Fill each section in `$RUN_DIR/body.md`, replacing its guidance comment with real content per the contract:

- **Objective** — a well-oriented statement of the goal, crafted from the whole session, not just the last message.
- **Output Format** — the exact result the worker must produce.
- **Boundaries / Scope** — what is in and out of scope; what not to re-litigate.
- **Context & Decisions** — decisions and rationale, research, and findings. Summarize narrative for clarity, but carry the full substance that bears on the work.
- **Artifacts & Pointers** — generated plans, documents, and code excerpts inline when load-bearing; absolute-path pointers for large or external artifacts.
- **Effort Guidance** — how much depth and effort the worker should spend.
- **Not Evaluated** — areas deliberately skipped or not yet evaluated; when none, say so.

Keep your own proposed approach, verdict, or solution out of every section. That single omission preserves the worker's independent judgment.

## Step 6: Build and validate

```bash
cog context-brief build --request "$RUN_DIR/request.txt" --body "$RUN_DIR/body.md" --out "$OUT"
```

`build` injects the raw request, assembles the brief, and fails closed unless every section is present and filled. Fix any reported section and rebuild.

## Output

Return the validated brief path as the terminal result — one line, the absolute path. The caller inlines this brief into its worker dispatch; this skill builds context and does not dispatch a worker.

## Guardrails

- The raw request is attached as-is; the objective is an oriented summary, not a paraphrase that drops requirements.
- Summarize narrative for clarity, but carry the full substance and artifacts where necessary.
- The caller's own verdict or proposed solution is the single deliberate omission.
- Reference large artifacts by absolute path; inline load-bearing plans and excerpts.
- Build and validate through `cog context-brief`; keep section judgment in this skill.
