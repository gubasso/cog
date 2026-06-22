---
name: review-code-deep
description: >
  Performs deep multi-pass review of any language or framework detected in the
  diff. Delegates deterministic scope, technology detection, findings
  normalization, and PR-comment mechanics to cog while keeping review judgment in
  prose.
---

# Review Code Deep

Run a deep review of the live diff. When a reviewed plan is supplied, treat plan conformance as an
explicit review dimension.

## Inputs

Parse `[--scope <glob>] [--severity <min>] [--format markdown|json] [--comment]` from the prompt.
Default severity is `praise`, the permissive floor for deterministic filtering. Default format is
`markdown`.

## Phase 0: Mechanical Setup

```bash
RUN_DIR="$(cog review-init review-code-deep-codex | sed -n 's/^RUN_DIR=//p')"
. "$RUN_DIR/paths.env"
cog review-scope "$SCOPE_JSON"
cog review-tech-scope --scope "$SCOPE_JSON" "$TECH_SCOPE_JSON"
```

If the scope has no changed files and no status files, stop. If `--scope <glob>` is present, limit
the review judgment to matching paths while leaving the deterministic scope artifact intact.

Load:

- `$(cog skill-refs path code-review/reviewer-prompt.md)`
- every relative path in `$TECH_SCOPE_JSON` `available_refs[]`, resolved with `cog skill-refs path`

For every `research_targets[]` entry, verify current behavior against primary sources before
reviewing: official docs, language specs, RFCs, man pages, changelogs, or project repositories.
Prefer version-specific sources when the project pins or implies a version.

## Phase 1: Review

Use the reviewer prompt. Review correctness, security, performance, reliability, maintainability,
tests, and plan conformance. Do not restate the diff. Drop lint/format findings and speculative
claims; downgrade uncertain external-behavior claims to questions.

## Phase 2: Findings

For JSON output, write candidate findings to `$FINDINGS_JSON` using this schema:

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

Normalize and validate before returning JSON:

```bash
cog review-normalize-findings --findings "$FINDINGS_JSON" --severity "$SEVERITY" --out "$FINDINGS_JSON"
```

If `--comment` is passed and a PR number is known, run:

```bash
cog review-comment --findings "$FINDINGS_JSON" --pr "$PR_NUMBER" --json
```

## Orchestrator Invocation Contract

When the prompt opens with two absolute paths, run in orchestrator mode:

1. `<context-path>`: read task, prior review context, and any reviewed plan.
2. `<output-path>`: symbolic caller-side capture target.

Force JSON output, skip prompts, run Phases 0-2, and emit the normalized JSON document as the final
message for the orchestrator to persist.

## Markdown Output

Return a short summary, findings grouped by file and severity, strengths, and a decision line:
`[approve]`, `[comment]`, or `[request-changes]`.

## Guardrails

- Review-only. Do not modify code.
- No fabricated citations; use official sources for external claims.
- If the diff is empty, stop.
- If the diff is over 2000 lines of non-generated code, suggest splitting before reviewing.
