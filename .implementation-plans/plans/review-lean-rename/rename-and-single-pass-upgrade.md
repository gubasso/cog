# Rename review-code-deep → review-lean and apply single-pass upgrade

> Plan: review-lean-rename | Round: 1 of 1 | Complexity: M | Generated: 2026-06-22 | Repo: /workspaces/cog

## Context

The skill `review-code-deep` is a thin orchestrator that runs a deep review of the live git diff, delegating deterministic mechanics (scope, tech detection, findings normalization, PR comments) to `cog` subcommands while keeping review judgment in prose. It ships as native twins: `skills/claude/review-code-deep/SKILL.md` and `skills/codex/review-code-deep/SKILL.md`.

The skill contradicts itself: its description and triggers say **"multi-pass review,"** but the workflow is a single pass (Phase 0 setup → Phase 1 review → Phase 2 findings, one `decision`, no loop). Iterative multi-pass review is owned by the separate `review-loop` skill, which calls this one in rounds.

This round (1) **renames** the skill to **`review-lean`** everywhere it is referenced, and (2) **upgrades** its content to a faithful single-pass review skill: single-pass identity in prose, an explicit thicker Phase 1, direct loading of the review-discipline references, optional schema metadata, a tightened Codex orchestrator-output contract, and updated guardrails. Both twins move together (twin parity, `docs/decisions/0021-twin-skill-naming-and-delegation-hints.md`); the Codex frontmatter stays `name` + `description` only per `docs/reference/skill-contract.md`.

Repo non-negotiables that constrain this work (from `CLAUDE.md` / `AGENTS.md`): lean, positive skill prose (ADR 0019) with no source-repo cross-references in runtime skills; `skill-refs/` as the single SoT for skill-external resources (ADR 0023); deterministic mechanics stay in `cog` (ADR 0008). Run no git commands.

## Previous Rounds

This is the first round — no prior rounds.

## Scope of This Round

IN scope:

- Rename the two skill directories `review-code-deep` → `review-lean` and update their frontmatter `name:`, H1 title, triggers (Claude), and `cog review-init` label.
- Apply the single-pass content upgrade to both twins (description, Phase 0 `Load:`, Phase 1 rewrite with Fuller inline blocks, Phase 2 schema metadata + decision semantics, guardrails; Codex orchestrator-output contract).
- Update every load-bearing caller and reference: `review-loop`, `executor-prex` (SKILL + stage-4 reference), `review-findings` (both twins), `skill-refs/code-review/review-process.md`, `skill-refs/orchestration/verdict-model.md`, `lib/commands/cmd_skill_lint.sh` comment, `docs/reference/skills.md`, `docs/reference/model-effort-claude.toml`, `docs/reference/model-effort-codex.toml`, and `test/integration/skills_claude.bats`.
- Verify with `cog skill-lint`, a repo-wide grep, and `just test`.

OUT of scope (do NOT touch — these are intentional leave-as-is):

- `skill-refs/code-review/SOURCES.md` (external upstream attribution path).
- `test/integration/cmd_skill_lint.bats` synthetic fixture string (arbitrary name testing path detection).
- Anything under `.implementation-plans/plans/*` (historical plan artifacts; do not rewrite history).
- Any `cog` command logic or `lib/functions/` (schema metadata is pass-through; the severity ladder stays canonical in `cog::fn::review::severity_rank`).

## Current State

### Key Files

- `skills/claude/review-code-deep/SKILL.md` — Claude twin. Current frontmatter and relevant lines:

  ```text
  name: review-code-deep
  description: >
    Performs deep multi-pass review of any language or framework detected in the
    diff. ...
  ...
  <!-- trigger-tests: "review-code-deep", "deep code review", "multi-pass review", "review this code" -->
  # Review Code Deep
  Run a deep review of the live diff. ...
  ```

  Phase 0 setup line and `Load:` list:

  ```bash
  RUN_DIR="$(cog review-init review-code-deep | sed -n 's/^RUN_DIR=//p')"
  ```

  ```text
  Load:
  - `$(cog skill-refs path code-review/reviewer-prompt.md)`
  - every relative path in `$TECH_SCOPE_JSON` `available_refs[]`, resolved with `cog skill-refs path`
  ```

  Current Phase 1 (the 3-line block to replace):

  ```text
  ## Phase 1: Review

  Use the reviewer prompt. Review correctness, security, performance, reliability, maintainability,
  tests, and plan conformance. Do not restate the diff. Drop lint/format findings and speculative
  claims; downgrade uncertain external-behavior claims to questions.
  ```

  Current guardrails:

  ```text
  ## Guardrails

  - Review-only. The orchestrator-mode output file is the only write.
  - No fabricated citations; use official sources for external claims.
  - If the diff is empty, stop.
  - If the diff is over 2000 lines of non-generated code, suggest splitting before reviewing.
  ```

- `skills/codex/review-code-deep/SKILL.md` — Codex twin. Frontmatter is `name:` + `description:` only (no `argument-hint`/`allowed-tools`/`trigger-tests` — required by the contract). Same body shape as the Claude twin. Distinct current lines:

  ```bash
  RUN_DIR="$(cog review-init review-code-deep-codex | sed -n 's/^RUN_DIR=//p')"
  ```

  ```text
  # Review Code Deep
  ```

  Current Codex orchestrator contract (to tighten):

  ```text
  ## Orchestrator Invocation Contract

  When the prompt opens with two absolute paths, run in orchestrator mode:

  1. `<context-path>`: read task, prior review context, and any reviewed plan.
  2. `<output-path>`: symbolic caller-side capture target.

  Force JSON output, skip prompts, run Phases 0-2, and emit the normalized JSON document as the final
  message for the orchestrator to persist.
  ```

- Both twins document an identical findings JSON schema block (top-level `decision`, `summary`, `findings[]`, `strengths[]`; per-finding `severity`, `file`, `line_start`, `line_end`, `category`, `headline`, `evidence`, `reasoning`, `suggestion`, `confidence`).

- `skills/claude/review-loop/SKILL.md` — invokes the Codex twin. Relevant lines:

  ```text
  Each round invokes the Codex `review-code-deep` twin in orchestrator mode against the live diff.
  ...
  Build `$RUN_DIR/round-N-prompt.txt` with `$review-code-deep <context> <output-marker>` and a
  ```

- `skills/claude/executor-prex/SKILL.md:306` — `Delegate implementation review to`review-code-deep`via the **Agent tool**, ...`.

- `skills/claude/executor-prex/references/stage-4-review-implementation.md` — references `review-code-deep` at lines 3, 20, 30, 39, 79, 91, 105, including the installed runtime path:

  ```text
  Read the skill file at $HOME/.claude/skills/review-code-deep/SKILL.md and
  follow its "Orchestrator Invocation Contract" mode. ...
  ```

- `skills/claude/review-findings/SKILL.md` (`:6`, `:16`) and `skills/codex/review-findings/SKILL.md` (`:6`, `:12`) — both reference the `review-code-deep` JSON schema in prose.

- `skill-refs/code-review/review-process.md:3` — "The four-phase workflow every `review-code-deep` invocation follows."

- `skill-refs/orchestration/verdict-model.md:5` — references `review-code-deep`.

- `lib/commands/cmd_skill_lint.sh:254` — a comment mentioning `review-code-deep`.

- `docs/reference/skills.md` (`:81`, `:85`) — lists `skills/claude/review-code-deep` and `skills/codex/review-code-deep`.

- `docs/reference/model-effort-claude.toml:18` and `docs/reference/model-effort-codex.toml:21` — example skill lists containing `review-code-deep`.

- `test/integration/skills_claude.bats` (`:54`, `:80`) — hardcoded skill-name array entries `review-code-deep`.

### Existing Patterns

- Skills install by directory name: `skills/claude/<name>/` → `~/.claude/skills/<name>/`. Renaming the source directory drives the installed path that `executor-prex` reads.
- `cog skill-lint`'s `name` rule requires frontmatter `name:` to equal the parent directory.
- Codex skill invocation uses the `$<skill-name>` token (e.g. `$review-code-deep`).
- The `cog review-init <prefix>` argument is only a run-dir label prefix (run dirs are timestamp+pid-unique), not a skill identity.
- Markdown fenced code blocks must declare a language (MD040; use `text` when none applies).

## Implementation Steps

### First Step: Mark this round as started

In this plan's `queue-rounds.yaml`, set this round's (`item: rename-and-single-pass-upgrade`) `status` to `doing`.

### Step 1: Rename the two skill directories

Use filesystem `mv` (not `git mv`):

```bash
mv /workspaces/cog/skills/claude/review-code-deep /workspaces/cog/skills/claude/review-lean
mv /workspaces/cog/skills/codex/review-code-deep /workspaces/cog/skills/codex/review-lean
```

### Step 2: Update both renamed SKILL.md headers (name, title, label, triggers)

In `skills/claude/review-lean/SKILL.md` and `skills/codex/review-lean/SKILL.md`:

- Frontmatter `name: review-code-deep` → `name: review-lean`.
- H1 `# Review Code Deep` → `# Review Lean`.
- Run-init label: Claude `cog review-init review-code-deep` → `cog review-init review-lean`; Codex `cog review-init review-code-deep-codex` → `cog review-init review-lean`.
- Claude only — replace the trigger-tests comment with:

  ```text
  <!-- trigger-tests: "review-lean", "single-pass review", "lean review", "deep code review", "review this code" -->
  ```

### Step 3: Update the description and intro (both twins)

Replace the `description:` body so it no longer says "multi-pass" and points to `review-loop`:

```text
description: >
  Performs a thorough single-pass review of any language or framework detected in the
  diff. Delegates deterministic scope, technology detection, findings normalization,
  and PR-comment mechanics to cog while keeping review judgment in this skill. For
  iterative multi-pass review with triage and fixes, use review-loop.
```

(Keep the Codex twin's final clause as "in prose" if it currently differs; match the existing twin wording style — only the multi-pass→single-pass and the review-loop pointer are mandated.)

Update the intro line `Run a deep review of the live diff.` → `Run a deep, single-pass review of the
live diff.` in both twins.

### Step 4: Phase 0 — load the discipline refs + plan-conformance line (both twins)

Add two entries to the Phase 0 `Load:` list:

```text
- `$(cog skill-refs path code-review/llm-review-discipline.md)`
- `$(cog skill-refs path code-review/review-process.md)`
```

Add a plan-conformance line near the Phase 0 context load: when a reviewed plan is supplied, load it from the task/context input and check that required plan phases are materially present in the diff; record gaps as `important` or `question` findings.

### Step 5: Phase 1 — rewrite as an explicit single pass with inline blocks (both twins)

Replace the current 3-line Phase 1 block with:

```text
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

External-behavior verification: for any claim about an external API, language, library, tool, or spec,
verify against primary sources and cite the source in evidence; otherwise record it as question.

Finding aggregation: when one anti-pattern recurs across files, emit one finding citing a
representative location and list the others; severity equals the highest individual instance.
```

### Step 6: Phase 2 — add optional schema metadata + decision semantics (both twins)

In the findings JSON schema block, add three optional top-level fields (alongside the existing keys):

```json
{
  "schema_version": 1,
  "scope": { "mode": "live-diff", "paths": [] },
  "external_sources": ["https://..."],
  "decision": "request-changes|comment|approve",
  "summary": "...",
  "findings": [ ... ],
  "strengths": ["..."]
}
```

Add a prose line under the block: `schema_version`, `scope`, and `external_sources` are optional metadata; cog normalization passes them through unchanged.

Add a decision-semantics block:

```text
Decision:
- approve: only answered-question or praise findings remain.
- comment: contains nit, suggestion, or an open question; non-blocking.
- request-changes: contains blocking or important findings.
```

### Step 7: Codex twin — tighten the orchestrator-output contract

In `skills/codex/review-lean/SKILL.md`, replace the orchestrator contract body with precise, self-contained wording (no cross-twin reference):

```text
## Orchestrator Invocation Contract

When the prompt opens with two absolute paths, run in orchestrator mode:

1. `<context-path>`: read task, prior review context, and any reviewed plan.
2. `<output-path>`: the orchestrator's capture target for the normalized JSON findings.

Force JSON output, skip prompts, run Phases 0-2, and emit the normalized JSON document as the final
message; the orchestrator persists it to `<output-path>`.
```

### Step 8: Guardrails (both twins)

Add two guardrail bullets and keep the existing ones:

```text
- Single pass: produce one review pass; do not loop, re-review after fixes, or modify code or tests.
- One finding per root cause.
```

### Step 9: Update load-bearing caller references

- `skills/claude/review-loop/SKILL.md`: prose "Codex `review-code-deep` twin" → "Codex `review-lean` twin"; the Codex invocation token `$review-code-deep` → `$review-lean`.
- `skills/claude/executor-prex/SKILL.md:306`: `review-code-deep` → `review-lean`.
- `skills/claude/executor-prex/references/stage-4-review-implementation.md`: replace ALL `review-code-deep` occurrences with `review-lean`, including the installed path `$HOME/.claude/skills/review-code-deep/SKILL.md` → `$HOME/.claude/skills/review-lean/SKILL.md`.
- `skills/claude/review-findings/SKILL.md` and `skills/codex/review-findings/SKILL.md`: "the `review-code-deep` JSON schema" → "the `review-lean` JSON schema" (both occurrences in each).

### Step 10: Update reference docs, skill-refs, policy, and tests

- `skill-refs/code-review/review-process.md:3`: `review-code-deep` → `review-lean`.
- `skill-refs/orchestration/verdict-model.md:5`: `review-code-deep` → `review-lean`.
- `lib/commands/cmd_skill_lint.sh:254` (comment): `review-code-deep` → `review-lean`.
- `docs/reference/skills.md`: `skills/claude/review-code-deep` → `skills/claude/review-lean`; `skills/codex/review-code-deep` → `skills/codex/review-lean`.
- `docs/reference/model-effort-claude.toml:18` and `docs/reference/model-effort-codex.toml:21`: example list entry `review-code-deep` → `review-lean`.
- `test/integration/skills_claude.bats` (`:54`, `:80`): array entry `review-code-deep` → `review-lean`.

Do NOT touch `skill-refs/code-review/SOURCES.md`, `test/integration/cmd_skill_lint.bats`, or anything under `.implementation-plans/plans/`.

### Step 11: Verify

```bash
cd /workspaces/cog
cog skill-lint skills/claude/review-lean/SKILL.md skills/codex/review-lean/SKILL.md
grep -rln "review-code-deep" . --exclude-dir=.git
just test
```

`cog skill-lint` must pass for both files. The grep must return ONLY the intentional leave-as-is hits: `skill-refs/code-review/SOURCES.md`, `test/integration/cmd_skill_lint.bats`, and files under `.implementation-plans/plans/`. `just test` must be green (the `skills_claude.bats` skill list now finds `review-lean`; the review-normalize/validate/comment bats are unaffected by the optional pass-through schema fields).

### Final Step: Update the queue

1. In this plan's `queue-rounds.yaml`, set this round's (`item: rename-and-single-pass-upgrade`) `status` to `done`.
2. All rounds are now done, so in the top-level `.implementation-plans/queue-plans.yaml` set this plan's (`item: review-lean-rename`) `status` to `done`. Leave the plan directory in place.

## Acceptance Criteria

- [ ] `skills/claude/review-lean/SKILL.md` and `skills/codex/review-lean/SKILL.md` exist; the old `review-code-deep` directories are gone.
- [ ] Both twins' frontmatter `name:` is `review-lean` and the H1 is `# Review Lean`; the Claude trigger-tests comment lists `review-lean` triggers.
- [ ] Neither twin's description or triggers contain "multi-pass"; both point to `review-loop` for iterative review.
- [ ] Phase 0 `Load:` includes `code-review/llm-review-discipline.md` and `code-review/review-process.md`.
- [ ] Phase 1 is the explicit 5-step single pass with the confidence/coupling, external-verification, and aggregation inline blocks.
- [ ] Phase 2 schema documents optional `schema_version`, `scope`, `external_sources` plus the decision-semantics block; guardrails include the single-pass and one-root-cause bullets.
- [ ] Codex orchestrator contract uses the precise capture-target wording (no `<output-path>` "symbolic" phrasing).
- [ ] `review-loop` uses the `$review-lean` token; `executor-prex` stage-4 reads `$HOME/.claude/skills/review-lean/SKILL.md`; both `review-findings` twins cite the `review-lean` schema.
- [ ] `cog skill-lint` passes for both renamed files.
- [ ] `grep -rln "review-code-deep" . --exclude-dir=.git` returns only `SOURCES.md`, `cmd_skill_lint.bats`, and `.implementation-plans/plans/*`.
- [ ] `just test` is green.
- [ ] This plan's `queue-rounds.yaml` shows round `rename-and-single-pass-upgrade` as `done`.
- [ ] The top-level `.implementation-plans/queue-plans.yaml` shows this plan as `done`.

## Next Round

This is the final round.
