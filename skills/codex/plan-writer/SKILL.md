---
name: plan-writer
description: >
  Codex twin of the Claude `plan-writer` skill. Single-pass generator that turns
  a self-contained context brief (or orientation) plus read-only repo research
  into an executor-aware implementation plan, sized S/M/L/XL with the complexity
  heuristic and the prex Executor Factor. Read-only and non-interactive; emits
  the plan as its final message. Primarily driven by the `plan-writer-multi`
  coordinator as the parallel second engine. Triggers: "plan-writer", "write a
  plan", "draft an implementation plan".
---

<!-- trigger-tests: "plan-writer for this brief", "draft an implementation plan from this context", "plan-writer-multi codex worker" -->

# Plan Writer — Codex twin

Same contract as the Claude `plan-writer` skill: turn a self-contained context brief into an
executor-aware implementation plan, sized S/M/L/XL. The plan-rounds references are shared via
`$DOCS_NOTES_REPO`; this twin reads the same files. Canonical semantics live in the Claude twin —
see `skills/claude/plan-writer/SKILL.md`.

This twin is **read-only** and **non-interactive**: it never writes repo files, never bootstraps or
registers `.implementation-plans/`, and never asks the user questions. It emits exactly one plan
draft as its **final message**, for the caller to capture via `--output-last-message`.

## Reference resolution

Shared references live in `$DOCS_NOTES_REPO` (the docs-n-notes repository). Resolve at skill start:

```bash
DOCS_NOTES="${DOCS_NOTES_REPO:-}"
[ -z "$DOCS_NOTES" ] && {
  echo "plan-writer: \$DOCS_NOTES_REPO not set." >&2
  echo "plan-writer: continuing without plan-rounds references (degraded sizing)." >&2
}
```

When set, read all three plan-rounds references before sizing or generating:

- `$DOCS_NOTES_REPO/tech/tools/claude-code/plan-rounds/plan-lifecycle.md` — directory structure,
  executor model, self-contained round contract.
- `$DOCS_NOTES_REPO/tech/tools/claude-code/plan-rounds/complexity-heuristic.md` — the five scoring
  axes, the Executor Factor, the grade mapping, and round-splitting rules.
- `$DOCS_NOTES_REPO/tech/tools/claude-code/plan-rounds/round-templates.md` — Templates A–F.

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
   grade (S/M/L/XL) per that file's grade table. Confirm the grade is reachable under that EF
   (`complexity-heuristic.md` § "EF is mandatory — reachable grades per executor"); never map the
   raw score.
4. Generate ONE plan draft and emit it as your **final message** (no file writes):
   - S/M → a single-file plan body (Template E shape).
   - L/XL → one structured document describing the directory plan inline: the `README.md` body, each
     round file (its `<topic>` slug + body), and the inner `QUEUE.yaml` round split. Do NOT create a
     directory — emit everything in the single final message for the coordinator to reconcile.
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
- Follow the templates and lifecycle exactly as defined in the shared references (Template E for S/M;
  Templates A–D for L/XL, with `STRATEGY.md`/Template C for XL).

## Coordinator-owned helper mechanics

This Codex twin is a worker. It must not create `.implementation-plans/`, register queues, run
collision checks, or imply that it directly mutates plan ledgers in orchestrator mode. The
coordinator that synthesizes the definitive plan owns those writes and delegates deterministic
mechanics to `cog`:

```bash
cog plan-slug --text "$ORIENTATION" --json
cog plan-init --repo-root "$REPO_ROOT" --json
cog queue-bootstrap --schema plans --queue "$PLAN_ROOT/QUEUE.yaml" --json
cog queue-append --schema plans --queue "$PLAN_ROOT/QUEUE.yaml" \
  --item "$QUEUE_ITEM" --status todo --depends-on "$DEPENDS_ON_CSV" \
  --prompt "$PROMPT" --notes "$NOTES" --json
```

For directory plans, the coordinator also bootstraps and appends the inner `rounds:` queue:

```bash
cog queue-bootstrap --schema rounds --queue "$PLANS_DIR/$SLUG/QUEUE.yaml" --json
cog queue-append --schema rounds --queue "$PLANS_DIR/$SLUG/QUEUE.yaml" \
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
- **Model / effort.** Planning is a full-effort task — the caller runs `--profile medium`. See
  `$DOCS_NOTES_REPO/tech/tools/claude-code/codex-conventions.md` for the invocation pattern.

## See also

- Claude twin (canon): `skills/claude/plan-writer/SKILL.md`.
- Plan-rounds references: `$DOCS_NOTES_REPO/tech/tools/claude-code/plan-rounds/`.
- Codex invocation conventions: `$DOCS_NOTES_REPO/tech/tools/claude-code/codex-conventions.md`.
