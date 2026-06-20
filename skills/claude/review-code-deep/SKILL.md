---
name: review-code-deep
description: >
  Performs deep multi-pass code
  review across Rust, Python, Bash, TypeScript, JavaScript, Go, Lua, R, React,
  Svelte, Django, C, and CSS/Less/Sass. Delegates Phase-0 scope, CLI-signal,
  docs-n-notes refs, and findings validation mechanics to cog
  review-* commands while keeping review judgment in this skill.
argument-hint: "[--cli] [--no-cli] [--lang <lang>] [--scope <glob>] [--severity blocking|important|nit] [--format markdown|json] [--comment]"
allowed-tools: Bash, Read, Write, Grep, Glob, WebSearch, WebFetch
---

<!-- trigger-tests: "review-code-deep", "deep code review", "multi-pass review", "review this code" -->

# Review Code Deep

Multi-language, multi-pass code review. Loads only the language guides and cross-cutting themes the
current diff actually touches. Deterministic Phase-0 mechanics are delegated to `cog`; the
review judgment remains here. `review-code-deep` is the canonical Stage-4 implementation-review
surface for orchestrators such as prex; when a reviewed plan is supplied, compare the live
implementation diff against that plan as well as generic code-quality criteria.

## Inputs

Parse
`[--cli] [--no-cli] [--lang <lang>] [--scope <glob>] [--severity <min>]
[--format markdown|json] [--comment]`
from `$ARGUMENTS`. All flags optional.

- `--cli` — explicitly opt in to CLI-design references.
- `--no-cli` — skip CLI refs entirely.
- `--lang <lang>` — force a single-language audit.
- `--scope <glob>` — limit review to matching files.
- `--severity <min>` — suppress findings below this severity. Order: `blocking` < `important` <
  `nit`. Default: `nit`.
- `--format markdown|json` — output shape. Default: `markdown`.
- `--comment` — post findings as inline PR comments via `gh pr comment`.

Unrecognised flag tokens -> STOP and report; do not silently ignore.

## Phase 0 — Mechanical Setup Via Agent Helper

Create the run directory and resolve every helper output path with one call.
`cog` must be installed and on `PATH`; a bare call fails
legibly if it is missing. Capture `RUN_DIR` once; shell state does not persist
between Bash calls, so re-source `$RUN_DIR/paths.env` in any later block that needs
the path variables:

```bash
RUN_DIR="$(cog review-init review-code-deep | sed -n 's/^RUN_DIR=//p')"
. "$RUN_DIR/paths.env"
```

`review-init` sets `SCOPE_JSON`, `CLASSIFICATION_JSON`, `CLI_JSON`, `REFS_JSON`, and
`FINDINGS_JSON`. Detect review scope:

```bash
cog review-scope "$SCOPE_JSON"
```

If the scope has no changed files and no status files, STOP; there is nothing to review.

Classify the project and derive CLI signals:

```bash
cog classify-project "$CLASSIFICATION_JSON"
cog review-cli-signals --classification "$CLASSIFICATION_JSON" "$CLI_JSON"
```

Resolve docs-n-notes references. This mirrors the former `claude-preflight agents` finalization
without calling `claude-preflight`:

```bash
cog review-refs --classification "$CLASSIFICATION_JSON" "$REFS_JSON"
```

If `$REFS_JSON` exists, read `docs_notes_repo.relevant_agents_md[]` and load those files from
`docs_notes_repo.path`. If docs-n-notes is unavailable, warn and continue with code context alone.
Do not pre-load reference files outside the matched set.

## Phase 0.5 — CLI Routing

If `--cli` was passed, load `$DOCS_NOTES_REPO/tech/programming/cli-design/AGENTS.md` when present.
If `--no-cli` was passed, skip CLI refs. Otherwise, use `review-cli-signals` output:

- If `.is_cli == true`, load CLI-design `AGENTS.md` from `review-refs` output when present.
- If unavailable, continue without an interactive prompt.

Further CLI chapters load on demand when the diff touches their domain.

## Reference Loading Rules

Always prefer the refs resolved by `cog review-refs`; they are existing-files-only,
sorted-unique, and derived from classification. Load cross-cutting guides on demand:

- Architecture when the diff crosses module/package boundaries or adds a layer.
- Performance when the diff touches loops with I/O, ORM queries, concurrency, or hot paths.
- Security when the diff touches auth/session/token code, input handling, path/SQL/command
  construction, deserialization, cryptography, or secrets.
- Common bugs for any non-trivial logic change.

## Phase 1 — Run The Review Process

Use the code-review process from docs-n-notes when available: Context -> High-level -> Line-by-line
-> Summary & decision. Review for correctness, architecture, performance, security, maintainability,
error handling, and tests. When the context supplement (`<context-path>`) includes a reviewed or
approved plan, treat plan conformance as an explicit review dimension: read the plan as expected
implementation intent and compare each plan phase against the live diff. Do not restate the diff;
interpret it.

## Phase 2 — Verify Findings

Every finding gets the structured-record treatment:

- Cite file:line evidence.
- Name the failure mode in the reasoning.
- Confidence is `high`, `medium`, or `low`; low-confidence findings become questions.
- Security findings answer source, sink, and path.
- Drop anything the linter or pre-commit already covers.

Target false-positive rate below 20%. When in doubt, downgrade.

### Plan Conformance Findings

If `<context-path>` includes a reviewed plan, read it as expected implementation intent. Surface
missing or partial plan phases as ordinary findings in the existing JSON schema; add no fields and
no categories. Use `correctness` for missing required behavior or incomplete implementation, and
`test` for missing required tests or validation steps. Use `blocking` when required behavior is
entirely absent, `important` when a phase is materially incomplete, and `question` when the
plan-to-diff mapping is ambiguous. Cite the affected implementation file and line range when
possible. If no implementation file exists because the phase is entirely absent, cite the
`<context-path>` line range where the reviewed plan states the requirement. Put the plan
requirement, observed diff gap, and triage reasoning in `evidence` and `reasoning`.

## Phase 3 — Output

### Markdown

- TL;DR, one paragraph.
- Findings grouped by file, severity-ordered.
- Strengths section.
- Decision line: `[approve]`, `[comment]`, or `[request-changes]`.

### JSON

Stable schema:

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

Sort findings by `(severity_rank desc, file asc, line_start asc)`.

For JSON output, write the candidate JSON to `$FINDINGS_JSON`, validate it, then output it:

```bash
. "$RUN_DIR/paths.env"
cog review-validate-findings --findings "$FINDINGS_JSON" --json
```

If validation fails, fix the JSON and revalidate before returning it to the caller.

### Inline PR Comments

For each finding, run:

```bash
gh pr comment <pr> --body "<severity> <headline> -- <reasoning>"
```

Use the file:line range in the body. Skip duplicates by file+line+headline hash.

## Orchestrator Invocation Contract

When `$ARGUMENTS` is two absolute paths separated by a space, run in orchestrator mode. This is the
canonical Stage-4 implementation-review contract for JSON findings consumed by an orchestrator for
triage:

1. `<context-path>` — markdown supplement with task description, prior-review context, and
   optionally the reviewed plan. Read it, but do not let it override the live diff.
2. `<output-path>` — absolute path where the JSON findings artifact must be written.

In this mode, force JSON output, skip interactive prompts, run Phases 0-3, validate with
`review-validate-findings`, write the JSON document verbatim to `<output-path>`, and reply:

```text
WROTE <output-path>
```

## Rules And Guardrails

- Review-only. Never modify code. The orchestrator-mode write to `<output-path>` is the only write.
- No linter or formatter findings.
- Honor the severity filter.
- No fabricated citations; downgrade speculative findings to questions.
- If `$DOCS_NOTES_REPO` is unset or unresolved, warn and continue without domain-specific refs.
- If the diff is empty, STOP.
- If the diff is over 2000 lines of non-generated code, suggest splitting before reviewing.
- If a finding targets `claude/.claude/**`, flag the staging-then-install workflow as a precondition.

## See Also

- References: `$DOCS_NOTES_REPO/tech/`.
- Companion skills: `/review-findings`, `/test-review`, `/code-review`.
