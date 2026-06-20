---
name: plan-writer
description: >
  Codex twin of the Claude `plan-writer` skill. Single-pass generator that turns
  a self-contained context brief (or orientation) plus read-only repo research
  into directory-plan drafts for the directory-only, two-layer model, using the
  complexity heuristic and the prex Executor Factor as sizing signals. Read-only
  and non-interactive; emits the plan as its final message. Primarily driven by
  the `plan-writer-multi` coordinator as the parallel second engine. Triggers:
  "plan-writer", "write a plan", "draft an implementation plan".
---

<!-- trigger-tests: "plan-writer for this brief", "draft an implementation plan from this context", "plan-writer-multi codex worker" -->

# Plan Writer — Codex twin

Same contract as the Claude `plan-writer` skill: turn a self-contained context brief into an
executor-aware directory-plan draft. The adjusted grade is a sizing signal for directory rounds. The
plan-rounds references are shared via `$DOCS_NOTES_REPO`; this twin reads the same files. Canonical
semantics live in the Claude twin — see `skills/claude/plan-writer/SKILL.md`.

This twin is **read-only** and **non-interactive**: it never writes repo files, never bootstraps or
registers `.implementation-plans/`, and never asks the user questions. It emits exactly one plan
draft as its **final message**, for the caller to capture via `--output-last-message`.

## Reference resolution

The plan-rounds references ship with `cog` and resolve in-repo (or from the XDG deploy) via
`cog skill-refs path <rel>`; the resolver always succeeds, so no graceful-degrade fallback is needed.
Read all three plan-rounds references before sizing or generating:

- `$(cog skill-refs path plan-rounds/plan-lifecycle.md)` — directory structure,
  executor model, self-contained round contract.
- `$(cog skill-refs path plan-rounds/complexity-heuristic.md)` — the five scoring
  axes, the Executor Factor, the grade mapping, and round-splitting rules.
- `$(cog skill-refs path plan-rounds/round-templates.md)` — Templates A–F.

## Orchestrator Invocation Contract

The `plan-writer-multi` coordinator invokes this twin with a prompt that opens with the `$plan-writer`
mention, followed by a **self-contained raw context brief** inlined verbatim, followed by a short
orientation footer. In this mode:

1. Treat the inlined brief as your **sole context** — it carries the problem, requirements, resolved
   decisions, and the `Executor:`/EF line. Do NOT expect a conversation history.
2. Read the repo **read-only** to gather the code references the brief points at (open the files,
   quote signatures/lines). Do not modify anything.
3. Classify complexity **independently** against the five axes in `complexity-heuristic.md`. Sum the
   raw score (5–20), divide by the **EF stated in the brief**, and map the **adjusted** score to a
   grade (S/M/L/XL) per that file's grade table; never map the raw score.
4. Generate ONE plan draft and emit it as your **final message** (no file writes):
   - One or more **flat sibling** plan-directory drafts — every plan directory is a direct child of
     `plans/` (`plans/<slug>/`). **Never nest a plan directory inside another and never propose plan
     subdirectories**; express all relationships and ordering through `depends_on`, never through the
     filesystem (a shared slug prefix is a naming convention, not a parent directory).
   - For each directory, include the `README.md` body, round file bodies, and `queue-rounds.yaml`.
   - Include proposed `queue-plans.yaml` entries and `depends_on` wiring for Layer 1 sibling dirs.
   - Do NOT create directories — emit everything in the single final message for the coordinator to
     reconcile.
5. Do NOT create `.implementation-plans/`, do NOT register a queue entry, do NOT run collision checks
   — the coordinator owns all repo writes and reconciliation.

If invoked standalone (no inlined brief), treat the prompt's orientation text as the context and
follow the same steps, emitting the plan as the final message.

## Plan contract (shared with the Claude twin)

- Every plan is **self-contained** — no references to "the conversation", "as discussed", or "see
  README". A fresh executor session must be able to act on it with zero prior context.
- Always include an `Executor: <profile> (EF <factor>)` line in the decisions section.
- Use fenced code blocks with a language specifier for all code (markdownlint MD040; use `text` when
  no syntax applies). Quote existing code rather than citing bare line numbers.
- Order implementation steps by dependency; each step independently verifiable.
- Follow the directory-plan templates and lifecycle exactly as defined in the shared references.

## Coordinator-owned helper mechanics

This Codex twin is a worker. It must not create `.implementation-plans/`, register queues, run
collision checks, or imply that it directly mutates plan ledgers in orchestrator mode. The
coordinator that synthesizes the definitive plan owns those writes and delegates deterministic
mechanics to `cog`:

```bash
cog plan-slug --text "$ORIENTATION" --json
cog plan-init --repo-root "$REPO_ROOT" --json
cog queue-bootstrap --schema plans --queue "$PLAN_ROOT/queue-plans.yaml" --json
cog queue-append --schema plans --queue "$PLAN_ROOT/queue-plans.yaml" \
  --item "$QUEUE_ITEM" --status todo --depends-on "$DEPENDS_ON_CSV" \
  --prompt "$PROMPT" --notes "$NOTES" --json
```

The coordinator also bootstraps and appends each inner `rounds:` queue:

```bash
cog queue-bootstrap --schema rounds --queue "$PLANS_DIR/$SLUG/queue-rounds.yaml" --json
cog queue-append --schema rounds --queue "$PLANS_DIR/$SLUG/queue-rounds.yaml" \
  --item "$TOPIC" --status todo --depends-on "$DEPENDS_ON_CSV" \
  --prompt "/prex -ar .implementation-plans/plans/$SLUG/$TOPIC.md" \
  --notes "$NOTES" --json
```

The helper owns slug validation, reserved-name rejection (`readme`, `queue`, `strategy`), root
bootstrap, queue creation, and append-only registration. The Codex worker may describe these
mechanics in its draft, but final filesystem changes remain coordinator-owned.

## Codex-specific notes

- **No `AskUserQuestion`.** This twin never prompts the user; it resolves ambiguity with documented
  defaults noted in the draft.
- **No code modification.** Read-only sandbox — use `--sandbox read-only` (or the fallback
  `-c 'sandbox_permissions=["disk-full-read-access"]'`). The plan goes to the final message only.
- **Model / effort.** Planning is a full-effort task — the caller runs `--effort medium`. See
  the maintenance reference `docs/reference/codex-conventions.md` for the invocation pattern.

## See also

- Claude twin (canon): `skills/claude/plan-writer/SKILL.md`.
- Plan-rounds references: `$(cog skill-refs path plan-rounds/<file>.md)`.
- Codex invocation conventions: maintenance reference `docs/reference/codex-conventions.md`.
