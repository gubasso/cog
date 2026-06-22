---
name: review-findings
description: >
  Triage code review findings, validate them against code and current docs, apply
  appropriate fixes, and emit structured triage plus followups. Use for review
  reports, structured findings JSON, review comments, or triage from any review pass.
model: opus
effort: low
---

<!-- trigger-tests: "review findings", "address findings", "fix review", "review report", "handle feedback" -->

# Review Findings

`review-findings` is the triage source of truth for review findings. It accepts freeform findings
and the shared structured-findings contract:

- `severity`: `blocking|important|nit|suggestion|question|praise`
- `file`, `line_start`, `line_end`, `category`, `headline`, `evidence`, `reasoning`, `suggestion`,
  `confidence`

## Reference Resolution

Load review discipline from `$(cog skill-refs path code-review/llm-review-discipline.md)`. When
severity wording needs the shared output contract, load
`$(cog skill-refs path implementation-review/severity-levels.md)`.

## Workflow

1. Parse the findings and task context. If the task context is missing and affects triage, ask one
   focused question before editing.
2. Classify each finding as `Issue`, `Suggestion`, or `Question`.
3. Verify issues and suggestions against the current code, local docs, and official sources when the
   claim depends on API behavior, library semantics, configuration, or an external specification.
4. Assign status:
   - `blocking` or `important` with `high`/`medium` confidence: `FIXED` when the fix is minor and
     clear; otherwise `NEEDS_DISCUSSION`.
   - `nit` or `suggestion`: `ACKNOWLEDGED` unless the user explicitly asks for cleanup.
   - `question`: `QUESTION`.
   - `praise`: omit from actionable output.
   - low-confidence findings that fail independent re-check: `DISMISSED`.
5. Apply minimal code edits for `FIXED` findings. Keep unrelated refactors out of scope.
6. Record decisions, deferrals, and open questions as followups.

## Output

```markdown
# Findings Triage

## Summary

- Fixed: N
- Acknowledged: N
- Dismissed: N
- Needs discussion: N
- Questions: N

## Findings

### Finding N: <headline>

- **Type**: Issue | Suggestion | Question
- **Status**: FIXED | ACKNOWLEDGED | DISMISSED | NEEDS_DISCUSSION | QUESTION
- **Source**: <file:line_start-line_end or freeform source>
- **Reasoning**: <brief validation and task-scope reasoning>
- **Doc check**: <source checked, or "not needed">
- **Action taken**: <change, answer, or skip rationale>

## Followups

### Decisions

- <decision or "None">

### Deferrals

- <deferral or "None">

### Open Questions

- <question or "None">
```

## Guardrails

- Fix only findings that pass relevance and verification checks.
- Cite changed files in the report when edits are made.
- Use official docs as primary sources for external API or spec claims.
- Preserve the input order unless dependencies between findings require grouping.
