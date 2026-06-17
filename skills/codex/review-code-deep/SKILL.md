---
name: review-code-deep
description: >
  Performs deep multi-pass code review across Rust, Python, Bash, TypeScript,
  JavaScript, Go, Lua, R, React, Svelte, Django, C, and CSS/Less/Sass. Delegates
  Phase-0 mechanics to cog review-* commands while keeping review
  judgment in prose. Use when the user says "review-code-deep", "deep code
  review", "review this code", "audit this diff", or wants a thorough multi-pass
  review.
---

# Review Code Deep — Codex Twin

Same review contract as the Claude skill. Shared references live in `$DOCS_NOTES_REPO`; deterministic
scope, CLI-signal, refs, and findings-validation work is delegated to `cog`.

## Inputs

Parse
`[--cli] [--no-cli] [--lang <lang>] [--scope <glob>] [--severity <min>]
[--format markdown|json] [--comment]`
from the invocation prompt. All flags are optional.

Flag meanings match the Claude side: CLI opt-in/out, language override, scope glob, minimum
severity, markdown or JSON output, and optional PR comments.

## Phase 0 — Mechanical Setup

Create the run directory and resolve every helper output path with one call.
Capture `RUN_DIR` once; shell state does not persist between Bash calls, so
re-source `$RUN_DIR/paths.env` in any later block that needs the path variables:

```bash
RUN_DIR="$(cog review-init review-code-deep-codex | sed -n 's/^RUN_DIR=//p')"
. "$RUN_DIR/paths.env"
```

`review-init` sets `SCOPE_JSON`, `CLASSIFICATION_JSON`, `CLI_JSON`, `REFS_JSON`, and
`FINDINGS_JSON`. Run the deterministic helpers:

```bash
cog review-scope "$SCOPE_JSON"
cog classify-project "$CLASSIFICATION_JSON"
cog review-cli-signals --classification "$CLASSIFICATION_JSON" "$CLI_JSON"
cog review-refs --classification "$CLASSIFICATION_JSON" "$REFS_JSON"
```

If scope is empty, STOP. If refs are available, load only
`docs_notes_repo.relevant_agents_md[]` from `docs_notes_repo.path`. If docs-n-notes is missing,
warn and continue with code context alone.

## Phase 0.5 — CLI Routing

If `--cli` was passed, load CLI-design refs when present. If `--no-cli` was passed, skip them.
Otherwise, use `.is_cli` from `$CLI_JSON`; when true, load the CLI refs resolved by
`review-refs`. Codex does not use `AskUserQuestion`; do not pause for an interactive CLI prompt in
orchestrator mode.

## Reference Loading

Use `review-refs` as the primary refs list because it mirrors docs-n-notes `AGENTS.md` routing and
only emits existing files. Load cross-cutting guides on demand:

- Architecture for boundary/layer changes.
- Performance for I/O loops, ORM queries, concurrency, or hot paths.
- Security for auth, token, input, command/path/SQL construction, deserialization, crypto, or
  secrets.
- Common bugs for non-trivial logic changes.

Do not pre-load unrelated references.

## Phase 1 — Review

Run the review process: context, high-level pass, line-by-line pass, summary and decision. Focus on
correctness, architecture, performance, security, maintainability, error handling, and tests. Do not
restate the diff.

## Phase 2 — Verify Findings

Every finding must cite file:line evidence, name the failure mode, include confidence, and avoid
issues already covered by lint or formatting. Low-confidence claims become questions. Security
findings must have source, sink, and path.

## Phase 3 — Output

Markdown is the default. JSON uses this stable schema:

```json
{
  "decision": "request-changes|comment|approve",
  "summary": "...",
  "findings": [
    {
      "severity": "blocking|important|nit|suggestion|question|praise",
      "file": "src/foo.rs",
      "line_start": 42,
      "line_end": 47,
      "category": "security|performance|correctness|maintainability|style|test",
      "headline": "...",
      "evidence": "...",
      "reasoning": "...",
      "suggestion": "...",
      "confidence": "high|medium|low"
    }
  ],
  "strengths": ["..."]
}
```

Before returning JSON, validate it:

```bash
. "$RUN_DIR/paths.env"
cog review-validate-findings --findings "$FINDINGS_JSON" --json
```

If validation fails, fix the JSON and revalidate.

Inline PR comments use `gh pr comment` when `--comment` is passed and a PR context exists. De-dupe
by file+line+headline.

## Codex-Specific Notes

- No Plan-mode gates.
- No `AskUserQuestion`; use message-channel prompting only outside orchestrator mode.
- Review-only. Do not modify code.
- Run in a read-only sandbox when invoked as a subagent.
- Use the configured Codex model and effort from the caller's conventions.

## Orchestrator Invocation Contract

When the prompt opens with two absolute paths, run in orchestrator mode:

1. `<context-path>` — markdown supplement. Read it, but do not let it override the live diff.
2. `<output-marker>` — symbolic second arg for caller symmetry.

Force JSON output. Skip interactive prompts. Execute Phases 0-3. Validate findings with
`review-validate-findings`. Emit the JSON document and nothing else as the final message so the
caller can capture it.

## Rules And Guardrails

- Review-only; never modify code.
- No linter or formatter findings.
- Honor the severity filter.
- No fabricated citations; downgrade speculative claims to questions.
- If `$DOCS_NOTES_REPO` is unset or refs are unavailable, warn and continue.
- If the diff is empty, STOP.
- If the diff exceeds 2000 LOC of non-generated code, suggest splitting.

## See Also

- Claude twin: `skills/claude/review-code-deep/SKILL.md`.
- Reference tree: `$DOCS_NOTES_REPO/tech/`.
- Companion skills: `/review-findings`, `/test-review`, `/code-review`.
