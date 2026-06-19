# Rewire Skills onto cog, Decouple codex-conventions, Verify, and Clean DocsNNotes

> Plan: cog-self-contained-skill-refs | Round: 3 of 3 | Complexity: L | Generated: 2026-06-19 |
> Repo: /workspaces/cog

## Context

`cog` is being made self-contained: skill-source reference docs that used to load from an external
repo (`$DOCS_NOTES_REPO`, on this machine `/home/gbasso/DocsNNotes`) via literal
`$DOCS_NOTES_REPO/tech/tools/claude-code/...` paths now live in-repo under `skill-refs/`, ship to
`$XDG_DATA_HOME/cog/skill-refs` at install, and resolve via `cog skill-refs path <rel>`. The Codex
orientation/quota guidance that skills used to copy out of `codex-conventions.md` is now emitted by
`cog codex-runner orientation <read-only|write>` and `cog codex-runner explain-status <status>`.

This final round flips the **consumers**: it repoints every skill that referenced the migrated docs
onto the new cog resolver, removes the runtime injection of `codex-conventions.md` in favor of the
cog orientation/status surface, runs the full verification sweep (lint, tests, smoke, degrade,
install), and — only once cog is verified self-contained — clean-deletes the migrated files from
DocsNNotes. General external docs and the borderline tool/discipline refs are left exactly as they
are.

## Previous Rounds

- Round 1 (`cog-command-foundations`) added `cog skill-refs path|root` (XDG-first, repo-source
  fallback) and `cog codex-runner orientation`/`explain-status`, with tests and completion/man.
- Round 2 (`migrate-content-and-packaging`) created the repo-root `skill-refs/` tree (10 files), moved
  `codex-conventions.md` into `docs/` as a maintenance reference, taught `install.sh` to deploy
  `skill-refs/` to `$XDG_DATA_HOME/cog/skill-refs`, and landed the self-containment ADR plus
  `AGENTS.md`/`CLAUDE.md` rules. So `cog skill-refs path <rel>` resolves the migrated content now.

## Scope of This Round

IN scope:

- Repoint every `SKILL.md` (and skill reference file) that uses
  `$DOCS_NOTES_REPO/tech/tools/claude-code/<path>` to `$(cog skill-refs path <rel>)`, and drop the
  now-unnecessary `DOCS_NOTES="${DOCS_NOTES_REPO:-}"` / "if unset, degrade" prose **for migrated refs
  only**.
- Decouple codex-conventions: in skills that inject it (prex, review-loop, plan-writer-multi,
  codex/plan-writer), remove "read codex-conventions.md before any Codex call"; obtain preambles from
  `cog codex-runner orientation <mode>`; branch on `cog codex-runner explain-status` / the runner's
  structured status.
- Run `cog skill-lint` on every touched `SKILL.md`; full verification sweep.
- Gated clean-delete of the migrated files from DocsNNotes (only after verification is green).
- Final-round queue updates.

OUT of scope:

- Any change to external general refs (`tech/programming/*`, `tech/languages/*`) and the borderline
  tool/discipline refs (`tech/tools/{ast-grep,suckless,osc-obs,riptask}/*`,
  `code-review/llm-review-discipline.md`) — their existing `$DOCS_NOTES_REPO` references and
  graceful-degrade prose stay.
- `lib/functions/fn_refs.sh` and `lib/commands/cmd_review_refs.sh` (the dynamic general-ref path).

## Current State

### Key Files (skills referencing migrated `tech/tools/claude-code/...` paths)

Repoint these to `$(cog skill-refs path <rel>)` (rel = path under `skill-refs/`, e.g.
`plan-rounds/round-templates.md`):

- `skills/claude/plan-writer/SKILL.md` — plan-rounds refs (`plan-lifecycle`, `complexity-heuristic`,
  `round-templates`) at many lines (resolution block ~40-46, body citations throughout). NOTE: this
  is the same skill family used to generate this very plan; it must resolve in-repo before the
  DocsNNotes delete.
- `skills/codex/plan-writer/SKILL.md` — plan-rounds refs + `codex-conventions.md`.
- `skills/claude/plan-writer-multi/SKILL.md` — `skills-and-orchestration.md`,
  `orchestration/orchestration-patterns.md`, `orchestration/verdict-model.md`, plan-rounds,
  `codex-conventions.md`.
- `skills/claude/prex/SKILL.md` + `skills/claude/prex/references/stage-2-through-5-details.md` —
  `skills-and-orchestration.md`, `skill-authoring/skill-script-extraction.md`,
  `orchestration/in-session-vs-headless-delegation.md`, `orchestration/` tree, and `codex-conventions.md`.
- `skills/claude/plan-queue-runner/SKILL.md` — `orchestration/in-session-vs-headless-delegation.md`.
- `skills/codex/implementation-reviewer/SKILL.md` — `implementation-review/` tree
  (`report-template.md`, `severity-levels.md`) and `orchestration/verdict-model.md`.
- `.claude/skills/skill-builder/SKILL.md` — generic `$DOCS_NOTES_REPO` resolution block; if it points
  at skill-authoring content (`skill-script-extraction.md`), repoint; otherwise leave its external
  block. Verify before editing.

Codex-conventions injectors to decouple: `skills/claude/prex/SKILL.md` (and
`references/stage-2-through-5-details.md`), `skills/claude/review-loop/SKILL.md`,
`skills/claude/plan-writer-multi/SKILL.md`, `skills/codex/plan-writer/SKILL.md`.

Leave external (do NOT touch their `$DOCS_NOTES_REPO` references):
`skills/claude/review-loop/SKILL.md` line ~254 (`code-review/llm-review-discipline.md`),
`skills/claude/ast-grep/SKILL.md`, `skills/codex/ast-grep/SKILL.md`,
`skills/claude/suckless-patcher/SKILL.md`, `skills/codex/suckless-patcher/SKILL.md`,
`skills/claude/osc-obs/SKILL.md`, and the riptask reference in `skills/claude/prex/SKILL.md` line ~228.

### Existing Patterns

- `cog skill-refs path <rel>` is a synchronous foreground Bash call — compatible with the env-first,
  no-backgrounding orchestration contract enforced by `cog skill-lint` (its env-first prose scanner
  was added in commit b163d00). Keep all new prose env-first; never background.
- `AGENTS.md` forbids git operations without explicit orchestrator authorization. This round performs
  file deletions in the external DocsNNotes repo but does NOT commit it — the human commits DocsNNotes
  separately.
- Skills that still consume external refs keep their `DOCS_NOTES="${DOCS_NOTES_REPO:-}"` + "warn and
  continue if unset" pattern. Only the migrated-ref blocks lose that pattern (the resolver always
  succeeds via XDG deploy or repo-source fallback).

### Migrated files in DocsNNotes (delete targets — only after verification)

Under `/home/gbasso/DocsNNotes/tech/tools/claude-code/`:
`plan-rounds/{plan-lifecycle,complexity-heuristic,round-templates}.md`,
`orchestration/{in-session-vs-headless-delegation,orchestration-patterns,verdict-model}.md`,
`skill-authoring/skill-script-extraction.md`,
`implementation-review/{report-template,severity-levels}.md`, `skills-and-orchestration.md`,
`codex-conventions.md`, plus now-orphaned `AGENTS.md` digests / emptied dirs under `claude-code/`.
KEEP everything else (`programming/`, `languages/`, `tools/{ast-grep,suckless,osc-obs,riptask}`).

## Implementation Steps

### First Step: Mark this round as started

In this plan's `QUEUE.yaml`, set this round's (`item: rewire-skills-and-cleanup`) `status` to
`doing`.

### Step 1: Repoint migrated skill-source refs

For each skill file listed above, replace literal `$DOCS_NOTES_REPO/tech/tools/claude-code/<path>`
references with `$(cog skill-refs path <rel>)` (e.g. `$(cog skill-refs path
plan-rounds/round-templates.md)`). Remove the migrated-ref `DOCS_NOTES="${DOCS_NOTES_REPO:-}"` /
"if unset, warn and continue" prose for those refs, since the resolver always succeeds. Keep prose
behavior otherwise identical. Verify each path resolves with `cog skill-refs path <rel>` while editing.

### Step 2: Decouple codex-conventions from runtime skills

In prex (`SKILL.md` + `references/stage-2-through-5-details.md`), review-loop, plan-writer-multi, and
codex/plan-writer:

- Delete instructions to read `$DOCS_NOTES_REPO/tech/tools/claude-code/codex-conventions.md` before a
  Codex call.
- Replace the orientation-block copy with: obtain the preamble via `cog codex-runner orientation
  read-only` (or `write`) and prepend it to the Codex prompt.
- Replace quota/error prose dependencies with branching on the runner's structured status and/or
  `cog codex-runner explain-status <status>`.

After this step, `rg -n 'codex-conventions\.md' skills/` must show no runtime "read this doc"
instruction (only, at most, a maintenance pointer to the `docs/` copy).

### Step 3: skill-lint touched skills

Run `cog skill-lint` on every touched `SKILL.md`. Resolve any findings (especially env-first
orchestration prose). Validate the changes against `docs/reference/skill-contract.md` per CLAUDE.md.

### Step 4: Full verification sweep (gate for Step 5)

- `just lint` (pre-commit, all files) and `just test` (unit + integration) — both green.
- Resolver smoke: `cog skill-refs path plan-rounds/round-templates.md` and a couple more resolve.
- Orientation smoke: `cog codex-runner orientation read-only` and `... write` emit preambles.
- Self-containment smoke: with `DOCS_NOTES_REPO` unset, the migrated refs still resolve (in-repo);
  only general/tool refs degrade. Confirm no skill errors on the migrated paths.
- Install smoke: run `install.sh` into a temp `PREFIX`/`XDG_DATA_HOME`; confirm
  `$XDG_DATA_HOME/cog/skill-refs` exists and `cog skill-refs path ...` resolves under it.
- `rg -n 'tech/tools/claude-code' skills/` returns only intentionally-external matches (none for the
  migrated set).

### Step 5: Gated clean-delete from DocsNNotes

Only after Step 4 is fully green: delete the migrated files (list above) from
`/home/gbasso/DocsNNotes/tech/tools/claude-code/`, plus the now-orphaned `AGENTS.md` digests and any
emptied directories under `claude-code/`. Keep ALL general knowledge and the borderline tool refs. Do
NOT run any git command in DocsNNotes — leave it for the human to review and commit. Report exactly
which files were removed.

### Final Step: Update the queue

1. In this plan's `QUEUE.yaml`, set this round's (`item: rewire-skills-and-cleanup`) `status` to
   `done`.
2. All rounds are now done, so in the top-level `.implementation-plans/QUEUE.yaml` set this plan's
   (`item: cog-self-contained-skill-refs`) `status` to `done`. Leave the plan directory in place.

## Acceptance Criteria

- [ ] Every migrated `tech/tools/claude-code/...` reference in skills now uses `$(cog skill-refs path
      <rel>)`; the migrated-ref degrade prose is removed.
- [ ] No `SKILL.md` reads `codex-conventions.md` at runtime; Codex preambles come from
      `cog codex-runner orientation` and status handling from `cog codex-runner explain-status` / the
      runner status.
- [ ] `cog skill-lint` passes on every touched `SKILL.md`; `just lint` and `just test` pass.
- [ ] With `DOCS_NOTES_REPO` unset, migrated refs resolve in-repo and skills do not error on them;
      only general/tool refs degrade.
- [ ] `install.sh` into a temp PREFIX/XDG_DATA_HOME yields a working `cog skill-refs path` against the
      XDG deploy.
- [ ] The migrated files (10 skill-source + `codex-conventions.md` + orphaned digests) are removed
      from DocsNNotes; all general/tool refs remain; DocsNNotes is left uncommitted for the human.
- [ ] External refs (`fn_refs.sh`, `review-refs`, tool skills, `llm-review-discipline.md`) are
      unchanged.
- [ ] This plan's `QUEUE.yaml` shows round `rewire-skills-and-cleanup` as `done`.
- [ ] The top-level `.implementation-plans/QUEUE.yaml` shows this plan as `done`.

## Next Round

This is the final round.
