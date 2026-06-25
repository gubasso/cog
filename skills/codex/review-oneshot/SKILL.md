---
name: review-oneshot
description: >
  Performs a thorough single-pass review of any language or framework detected in the
  diff. Delegates deterministic scope, technology detection, findings normalization,
  and PR-comment mechanics to cog while keeping review judgment in prose. For
  iterative review with triage and fixes, use review-loop.
---

# Review Lean

Run a deep, single-pass review of the live diff. When a reviewed plan is supplied, treat plan
conformance as an explicit review dimension.

## Inputs

Parse `[--scope <glob>] [--severity <min>] [--format markdown|json] [--comment]` from the prompt.
Default severity is `praise`, the permissive floor for deterministic filtering. Default format is
`markdown`.

## Phase 0: Mechanical Setup

```bash
RUN_DIR="$(cog review-init review-oneshot | sed -n 's/^RUN_DIR=//p')"
. "$RUN_DIR/paths.env"
cog review-scope "$SCOPE_JSON"
cog review-tech-scope --scope "$SCOPE_JSON" "$TECH_SCOPE_JSON"
```

If the scope has no changed files and no status files, stop. If `--scope <glob>` is present, limit
the review judgment to matching paths while leaving the deterministic scope artifact intact.

Load:

- `$(cog skill-refs path code-review/reviewer-prompt.md)`
- `$(cog skill-refs path code-review/llm-review-discipline.md)`
- `$(cog skill-refs path code-review/review-process.md)`
- every relative path in `$TECH_SCOPE_JSON` `available_refs[]`, resolved with `cog skill-refs path`

When a reviewed plan is supplied, load it from the task/context input and check that required plan
phases are materially present in the diff; record gaps as `important` or `question` findings.

For every `research_targets[]` entry, verify current behavior against primary sources before
reviewing: official docs, language specs, RFCs, man pages, changelogs, or project repositories.
Prefer version-specific sources when the project pins or implies a version.

## Phase 1: Review

Core principle: do not restate the diff — the reader has `git diff`; the value is interpretation.

Perform exactly one complete review pass:

1. Establish intent from task context, diff scope, and any reviewed plan.
2. Inspect architecture/design fit before line-level issues.
3. Read every changed line plus the surrounding context needed to judge it.
4. Validate each candidate finding against evidence and primary sources.
5. Emit only findings that survive validation; demote uncertainty to question.

Review correctness, security, performance, reliability, maintainability, tests, and plan conformance.
Drop lint/format findings and speculative claims.

Confidence and severity coupling:

- high → provable (spec citation, exact trace, type guarantee); keep declared severity.
- medium → version/context-dependent; keep severity but offer alternatives.
- low → cannot be determined from the diff alone; record as question.

External-behavior verification: for any claim about an external API, language, library, tool, or
spec, verify against primary sources and cite the source in evidence; otherwise record it as
question.

Finding aggregation: when one anti-pattern recurs across files, emit one finding citing a
representative location and list the others; severity equals the highest individual instance.

## Phase 2: Findings

For JSON output, write candidate findings to `$FINDINGS_JSON` using this schema:

```json
{
  "schema_version": 1,
  "scope": { "mode": "live-diff", "paths": [] },
  "external_sources": ["https://..."],
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

`schema_version`, `scope`, and `external_sources` are optional metadata; cog normalization passes
them through unchanged.

Decision:

- approve: only answered-question or praise findings remain.
- comment: contains nit, suggestion, or an open question; non-blocking.
- request-changes: contains blocking or important findings.

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
2. `<output-path>`: the orchestrator's capture target for the normalized JSON findings.

Force JSON output, skip prompts, run Phases 0-2, and emit the normalized JSON document as the final
message; the orchestrator persists it to `<output-path>`.

## Markdown Output

Return a short summary, findings grouped by file and severity, strengths, and a decision line:
`[approve]`, `[comment]`, or `[request-changes]`.

## Guardrails

- Review-only. Do not modify code.
- Single pass: produce one review pass; do not loop, re-review after fixes, or modify code or tests.
- One finding per root cause.
- No fabricated citations; use official sources for external claims.
- If the diff is empty, stop.
- If the diff is over 2000 lines of non-generated code, suggest splitting before reviewing.
