# Make cog Self-Contained: Ship Skill-Source Refs In-Repo

> Complexity: L | Rounds: 3 | Generated: 2026-06-19 | Repo: /workspaces/cog

## Problem Statement

`cog` is a Bash CLI plus shipped Claude/Codex skills. Several of those skills load reference
documents at runtime from an **external** sibling repository (`$DOCS_NOTES_REPO`, resolved on this
machine to `/home/gbasso/DocsNNotes`). Some of those documents are general knowledge (code-review
discipline, CLI design, language specs, tool guides) and are legitimately external, optional,
prompt-time enhancers. But a specific set under `tech/tools/claude-code/**` are **skill sources**:
load-bearing specs that define how cog's own skills plan, orchestrate, delegate, drive Codex, and
report findings. Because those live outside the repo, a fresh `cog` install on another machine has a
**loose-end dependency** — the skills degrade or misbehave without a repo the user never installed.

This plan makes cog self-contained: every document required for cog's skills/scripts to *run* lives
in-repo and ships with the install; external documents are referenced **only** at runtime as
optional general-knowledge enhancers, never as load-bearing internal implementation. The boundary is
captured as a governing rule (a new ADR plus `AGENTS.md`/`CLAUDE.md`).

These migrated specs are treated as **skill sources, not project documentation**. They get a
dedicated top-level `skill-refs/` source tree (renameable) — *not* the human-facing Diátaxis `docs/`
tree — deployed at install time to an XDG location and resolved by a deterministic `cog` command.

Separately, `codex-conventions.md` once taught skills how to invoke the `codex-session` CLI, but
that mechanic is now owned deterministically by `cog codex-runner` (`lib/commands/cmd_codex_runner.sh`
delegating to `lib/functions/fn_codex.sh`). Investigation confirmed ~70% of the doc is absorbed
(exec/resume construction, sandbox native/fallback, `--account` pinning, `</dev/null`,
`--output-last-message`, thread-id extraction, status/exit classification, SIGTERM detection,
preflight gate). Two pieces are still injected by skill prose at runtime: the **read-only/write
orientation blocks** prepended to every Codex prompt, and **quota semantics** (soft knees,
wait-vs-retry). Those are absorbed into cog here so the doc stops being loaded at runtime; it survives
in `docs/` as a maintenance reference.

## Strategy

Three dependency-ordered rounds, foundations first. Round 1 builds the deterministic cog plumbing
everything else consumes (the `cog skill-refs` resolver and the `cog codex-runner` orientation/status
surface), with tests and completion/man entries. Round 2 creates the in-repo content (the
`skill-refs/` tree and the codex-conventions maintenance doc), wires it into the installer's XDG
deploy, and lands the governance (new ADR + `AGENTS.md`/`CLAUDE.md` rule). Round 3 rewires the ~12
consuming skills onto the new resolver and the codex orientation/status surface, runs full
verification, and — only once cog is verified self-contained — clean-deletes the migrated files from
DocsNNotes.

## Rounds

1. `cog-command-foundations.md` — new `cog skill-refs` resolver + `cog codex-runner orientation`/status surface, with unit tests and completion/man registration.
2. `migrate-content-and-packaging.md` — create `skill-refs/` tree, move codex-conventions to `docs/`, add the installer XDG deploy, land governance ADR + rules + doc index updates.
3. `rewire-skills-and-cleanup.md` — repoint the consuming skills onto cog, decouple codex-conventions, full verification, and gated DocsNNotes clean-delete.

## Execution Commands

```bash
# Execute the next todo round (executor reads queue-rounds.yaml, runs the first `todo` round, then stops):
/prex -ar @.implementation-plans/plans/cog-self-contained-skill-refs/

# Or target a specific round file directly:
/prex -ar .implementation-plans/plans/cog-self-contained-skill-refs/cog-command-foundations.md
```

## Execution Discipline

**Rounds must be executed one at a time.** Each round is a self-contained unit of work designed for
a single `/prex` session. Do not implement multiple rounds in one session.

When `/prex` is pointed at this directory or this `README.md`, it MUST:

1. Read this plan's `queue-rounds.yaml`.
2. Find the first round with status `todo`.
3. Set that round's `status` to `doing`, execute ONLY that round, then set it to `done` and stop.
4. End the session — a fresh `/prex` session is launched for any subsequent round.

## Decisions & Constraints

- `Executor: prex (EF 1.5)` — sized for the four-pass prex pipeline.
- **Skill-source home:** new top-level `skill-refs/` (renameable), deployed to
  `$XDG_DATA_HOME/cog/skill-refs/` (default `~/.local/share/cog/skill-refs`), resolved by
  `cog skill-refs path <rel>` (XDG deploy first, repo-source `${LIB_DIR}/../skill-refs` fallback for
  dev checkouts). NOT the Diátaxis `docs/` tree — these are runtime skill sources, not project docs.
- **codex-conventions:** absorb its remaining runtime pieces (orientation blocks + quota/status
  semantics) into `cog codex-runner`; stop injecting the doc at runtime; the human-readable doc moves
  to `docs/` as a maintenance reference for whoever maintains `fn_codex.sh`.
- **Borderline refs stay external:** `tech/tools/{ast-grep,suckless,osc-obs,riptask}/*` and
  `tech/programming/code-review/llm-review-discipline.md` are general tool/discipline knowledge — keep
  them external with the existing graceful-degrade. Do NOT migrate.
- **General dynamic refs untouched:** `tech/programming/*`, `tech/languages/*` flow through
  `cog::fn::refs_compute` / `cog review-refs` / `cmd_preflight.sh` and the refactor guidelines via
  `cmd_refactor_setup.sh`. This plan does not modify `lib/functions/fn_refs.sh` or
  `lib/commands/cmd_review_refs.sh`.
- **DocsNNotes cleanup is gated:** delete migrated files only after cog is verified self-contained
  (Round 3). The executor performs the file deletions; the human commits the DocsNNotes repo
  separately (AGENTS.md forbids git operations without explicit authorization).
- **Migrate set (skill sources, 10 files)** under `tech/tools/claude-code/`:
  `plan-rounds/{plan-lifecycle,complexity-heuristic,round-templates}.md`,
  `orchestration/{in-session-vs-headless-delegation,orchestration-patterns,verdict-model}.md`,
  `skill-authoring/skill-script-extraction.md`,
  `implementation-review/{report-template,severity-levels}.md`, `skills-and-orchestration.md`.
  Plus `codex-conventions.md` → `docs/` (maintenance).

## Rejected Alternatives

- **Strict Diátaxis split under `docs/`** (decisions/guides/reference). Rejected: these are skill
  sources, not project docs; and `docs/` is not part of the install payload, so installed skills
  could not load them. They belong in a dedicated, deployable structure.
- **App-payload deploy at `$PREFIX/lib/cog/skill-refs/`** (like `templates/`). Viable and simpler
  (single `${LIB_DIR}/..` resolution), but rejected in favor of the more XDG-idiomatic
  `$XDG_DATA_HOME/cog/skill-refs/`, matching how completions/man already deploy. The resolver keeps a
  repo-source fallback for dev.
- **Migrating the borderline tool/discipline refs in.** Rejected: they are general knowledge; keeping
  them external honors the "general → stays external" rule and avoids maintenance duplication.
- **Leaving codex-conventions injected at runtime.** Rejected: the CLI mechanics are already owned by
  cog; injecting ~593 lines of prose per Codex-driving skill is avoidable token cost once the
  orientation/quota pieces are absorbed.

## Risks & Edge Cases

- **Resolver must never silently return a stale/empty path.** It must fail closed with a legible
  error when neither the XDG deploy nor the repo-source fallback exists. Covered by Round 1 tests.
- **Ordering hazard:** skills must not be repointed to `cog skill-refs path` before the `skill-refs/`
  content exists. Round ordering (R1 plumbing → R2 content+deploy → R3 rewire) prevents this.
- **The plan-writer skill itself depends on the migrated `plan-rounds/` refs.** It is in the Round 3
  rewire set; the DocsNNotes delete happens after it (and all skills) resolve in-repo.
- **skill-lint env-first scanner** (added in commit b163d00) must still pass on every rewired
  `SKILL.md`. The `$(cog skill-refs path ...)` calls are synchronous foreground Bash — compatible.
- **Completion/man drift checks** depend on the line-2 `: 'desc: ...'` sentinel; new command modules
  must keep it.
- **Stale historical pointers:** `.implementation-plans/**` archival plans reference old DocsNNotes
  paths. Accepted — they are historical records, not live dependencies.

## Completion

When all rounds are done, set each round `done` in this plan's `queue-rounds.yaml` and set this plan `done`
in the top-level `.implementation-plans/queue-plans.yaml`. Nothing moves on disk.
