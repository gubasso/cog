# Migrate Skill-Source Content, Package the XDG Deploy, and Land Governance

> Plan: cog-self-contained-skill-refs | Round: 2 of 3 | Complexity: L | Generated: 2026-06-19 |
> Repo: /workspaces/cog

## Context

`cog`'s skills load load-bearing "skill-source" reference docs from an external repo
(`$DOCS_NOTES_REPO`, on this machine `/home/gbasso/DocsNNotes`) via literal
`$DOCS_NOTES_REPO/tech/tools/claude-code/...` paths, so a fresh install depends on a repo the user
never installed. The project is making cog self-contained: skill-source docs move in-repo into a
dedicated `skill-refs/` tree, ship at install time to an XDG location, and resolve via a
deterministic `cog` command; external general-knowledge docs stay external as optional enhancers.

Round 1 already added the deterministic plumbing: `cog skill-refs path <rel>` / `cog skill-refs root`
(resolving `$XDG_DATA_HOME/cog/skill-refs` first, then the repo-source `${LIB_DIR}/../skill-refs`
fallback) and `cog codex-runner orientation <read-only|write>` / `cog codex-runner explain-status
<status>` (the Codex preambles and quota/status guidance, now cog-owned data).

This round creates the **content and packaging**: it populates the in-repo `skill-refs/` tree with
the 10 skill-source files, moves `codex-conventions.md` into `docs/` as a maintenance reference,
teaches the installer to deploy `skill-refs/` to XDG, and lands the governing rule (a new ADR plus
`AGENTS.md`/`CLAUDE.md`). No skills are rewired here and nothing is deleted from DocsNNotes — that is
Round 3.

## Previous Rounds

Round 1 (`cog-command-foundations`) added: `lib/functions/fn_skill_refs.sh`
(`cog::fn::skill_refs_root`, XDG-first/repo-fallback), `lib/commands/cmd_skill_refs.sh`
(`cog skill-refs path|root`, sourced via `bin/cog`), and new `cog codex-runner orientation` /
`explain-status` subcommands in `lib/commands/cmd_codex_runner.sh` + `lib/functions/fn_codex.sh`,
with unit tests and completion/man entries. The resolver returns the repo-source fallback
`${LIB_DIR}/../skill-refs` when no XDG deploy exists — so once this round creates `skill-refs/` at the
repo root, `cog skill-refs path ...` resolves it for dev checkouts immediately.

## Scope of This Round

IN scope:

- Create the top-level `skill-refs/` tree and populate it with the 10 skill-source files (content
  lifted from the current DocsNNotes copies).
- Move `codex-conventions.md` content into `docs/` as a maintenance reference (trim the parts now
  owned by `cog codex-runner`).
- Extend `install.sh` to deploy `skill-refs/` to `$XDG_DATA_HOME/cog/skill-refs` (pre-clean +
  `copy_tree` + manifest), and document it in `docs/guides/install.md`.
- Governance: a new self-containment ADR; repoint `docs/decisions/0007-in-session-subagent-delegation.md`
  to the in-repo skill-ref; add a "Reference Self-Containment" guard to `AGENTS.md` and a
  non-negotiable line to `CLAUDE.md`.
- Update `docs/README.md` index, `docs/reference/cli-commands.md` (the new commands from Round 1), and
  `docs/reference/skills.md` (skill-refs note).

OUT of scope (Round 3):

- Repointing any `SKILL.md` from `$DOCS_NOTES_REPO/...` to `cog skill-refs path` and removing
  codex-conventions injection from skills.
- Full verification sweep and the gated DocsNNotes clean-delete.

## Current State

### Key Files

- Source content (read-only inputs; copy their content into the repo) under
  `/home/gbasso/DocsNNotes/tech/tools/claude-code/`:
  - `plan-rounds/plan-lifecycle.md`, `plan-rounds/complexity-heuristic.md`,
    `plan-rounds/round-templates.md`
  - `orchestration/in-session-vs-headless-delegation.md`, `orchestration/orchestration-patterns.md`,
    `orchestration/verdict-model.md`
  - `skill-authoring/skill-script-extraction.md`
  - `implementation-review/report-template.md`, `implementation-review/severity-levels.md`
  - `skills-and-orchestration.md`
  - `codex-conventions.md` (→ goes to `docs/`, not `skill-refs/`)

- `install.sh` — copies the app payload and skills, and deploys data to XDG. Relevant excerpts:

  ```bash
  xdg_data_home="${XDG_DATA_HOME:-$home/.local/share}"
  app_root="$prefix/lib/cog"
  comp_dir="$xdg_data_home/bash-completion/completions"
  man_dir="$xdg_data_home/man/man1"
  ...
  rm -rf -- "${app_root:?}/bin" "${app_root:?}/lib" "${app_root:?}/templates" "${app_root:?}/VERSION"
  copy_tree "$repo_root/bin" "$app_root/bin"
  copy_tree "$repo_root/lib" "$app_root/lib"
  ...
  copy_tree "$repo_root/skills/claude" "$home/.claude/skills"
  copy_tree "$repo_root/skills/codex" "$home/.agents/skills"
  ...
  install -m 0644 "$repo_root/completions/cog.bash" "$comp_dir/cog"
  ```

  `copy_tree` (defined near the top) copies a tree and records every copied path into the install
  manifest (`record_path`), so uninstall is manifest-driven. The XDG `skill-refs` deploy follows the
  same `copy_tree` + pre-clean pattern as the app payload.

- `docs/guides/install.md` — documents the payload and XDG layout (PREFIX, XDG_DATA_HOME defaults,
  what the installer copies). Add the new `skill-refs` deploy here.

- `docs/decisions/0007-in-session-subagent-delegation.md` — line ~40 cites the external
  `docs-n-notes/tech/tools/claude-code/orchestration/in-session-vs-headless-delegation.md` as canon.
  Repoint to the in-repo skill-ref.

- `docs/decisions/0009-machine-facing-output-contract.md` — line ~27 cites the general external
  `cli-design/00-architecture.md`. This stays external (general knowledge); only add a note that it
  is an external provenance citation, not an internal runtime dependency.

- `docs/decisions/` — accepted ADRs are never deleted; changed decisions get a superseding ADR. Use
  the next free ADR number (0009 is the current highest; confirm by listing the directory). Follow the
  existing ADR/MADR format used by `0007`/`0008`/`0009`.

- `docs/README.md` — index only; `docs/reference/cli-commands.md` — the command reference table
  (review-refs is listed there at line ~74; add the new commands); `docs/reference/skills.md` — notes
  that skills may point to references.

- `AGENTS.md` — has an "Orchestration Guards" bullet list and a "Skill and Script Responsibility
  Boundary" section. Add a "Reference Self-Containment" guard. `CLAUDE.md` — carries a non-negotiable
  line pointing at `docs/decisions/0008-skill-script-boundary.md` and `docs/reference/skill-contract.md`;
  add a companion non-negotiable line for reference self-containment.

### Existing Patterns

- Documentation follows Diátaxis: `docs/decisions/` (ADRs), `docs/guides/` (runbooks),
  `docs/reference/` (lookup), `docs/explanation/` (mental models); `docs/README.md` is an index only.
  Markdown fenced code blocks must declare a language (use `text` when none applies).
- The codex-conventions maintenance doc documents cog internals for maintainers → place under
  `docs/reference/` (lookup facts for `fn_codex.sh`) or `docs/explanation/` (mental model); pick the
  Diátaxis bucket that fits and index it in `docs/README.md`.
- `install.sh` uses `copy_tree <src> <dest>` + `record_path` for manifest tracking and a `rm -rf --`
  pre-clean for cog-owned trees before re-copy.

## Implementation Steps

### First Step: Mark this round as started

In this plan's `QUEUE.yaml`, set this round's (`item: migrate-content-and-packaging`) `status` to
`doing`.

### Step 1: Create the `skill-refs/` tree

Create the repo-root `skill-refs/` directory mirroring the meaningful structure (dropping the
redundant `tech/tools/claude-code/` prefix), and copy each file's content from its DocsNNotes source:

```text
skill-refs/
  plan-rounds/plan-lifecycle.md
  plan-rounds/complexity-heuristic.md
  plan-rounds/round-templates.md
  orchestration/in-session-vs-headless-delegation.md
  orchestration/orchestration-patterns.md
  orchestration/verdict-model.md
  skill-authoring/skill-script-extraction.md
  implementation-review/report-template.md
  implementation-review/severity-levels.md
  skills-and-orchestration.md
```

Copy content verbatim except for adjusting any internal cross-references that pointed at sibling
`tech/tools/claude-code/...` paths so they read as `skill-refs/...` relative references. Ensure every
fenced code block declares a language (markdownlint MD040).

### Step 2: Move codex-conventions into `docs/` as a maintenance reference

Create the codex-conventions maintenance doc under `docs/` (Diátaxis `reference/` or `explanation/`).
Carry the rationale and the maintenance guidance for `fn_codex.sh` / `cog codex-runner`; trim or
clearly mark the sections whose behavior is now owned by cog (exec construction, sandbox modes,
status classification, and the orientation/quota text now emitted by `cog codex-runner orientation` /
`explain-status`). Add a header noting it is maintenance-time only and NOT loaded at runtime.

### Step 3: Deploy `skill-refs/` from the installer

In `install.sh`:

- Define a data dir, e.g. `data_dir="$xdg_data_home/cog"`.
- Pre-clean: `rm -rf -- "${data_dir:?}/skill-refs"` (alongside the existing app-payload pre-clean) so
  a re-install drops removed refs.
- Deploy: `copy_tree "$repo_root/skill-refs" "$data_dir/skill-refs"` (records into the manifest, so
  uninstall removes it automatically).
- Keep ordering consistent with the other `copy_tree` calls.

Update `docs/guides/install.md` to document the new `$XDG_DATA_HOME/cog/skill-refs` deploy.

### Step 4: New self-containment ADR + repoint ADR 0007

- List `docs/decisions/` to confirm the next free ADR number; author a new ADR (e.g.
  `0010-reference-self-containment.md`) stating: runtime skill sources live in `skill-refs/` and ship
  in the install payload (XDG); project docs live in `docs/`; external general docs are runtime-only
  optional enhancers that must degrade gracefully and must never be load-bearing internal
  implementation. Reference `0008-skill-script-boundary.md` and the new `cog skill-refs` mechanism.
- Edit `docs/decisions/0007-in-session-subagent-delegation.md` to cite the in-repo
  `skill-refs/orchestration/in-session-vs-headless-delegation.md` instead of the external
  `docs-n-notes/...` path. Do not delete or rewrite the decision itself.
- Add a one-line note to `docs/decisions/0009-machine-facing-output-contract.md` clarifying its
  `cli-design/00-architecture.md` citation is an external provenance reference, not a runtime
  dependency.

### Step 5: Governance rules in AGENTS.md and CLAUDE.md

- Add a "Reference Self-Containment" guard to `AGENTS.md` (near "Orchestration Guards" / the
  responsibility-boundary section): everything required to run ships in-repo (`skill-refs/`, deployed
  to XDG, resolved via `cog skill-refs`); external docs are runtime-only optional enhancers with
  graceful degrade; never make an external doc a load-bearing internal dependency.
- Add a companion non-negotiable line to `CLAUDE.md` pointing at the new ADR.

### Step 6: Update doc indexes and command reference

- Add the new `skill-refs` and `codex-runner` `orientation`/`explain-status` commands to
  `docs/reference/cli-commands.md`.
- Index the new `skill-refs/` corpus location and the codex-conventions maintenance doc in
  `docs/README.md`.
- Update `docs/reference/skills.md` to describe the `cog skill-refs` resolution for skill-source refs.

### Step 7: Verify resolver against new content

Run `cog skill-refs path plan-rounds/round-templates.md` from the repo checkout — it must resolve via
the repo-source fallback to the new `skill-refs/` file. Run `cog skill-refs path
skills-and-orchestration.md`. Run `just lint` (markdownlint will check the new docs) and `just test`.

### Final Step: Update the queue

1. In this plan's `QUEUE.yaml`, set this round's (`item: migrate-content-and-packaging`) `status` to
   `done`.

## Acceptance Criteria

- [ ] `skill-refs/` exists at the repo root with all 10 files; `cog skill-refs path
      plan-rounds/round-templates.md` resolves to it from a dev checkout.
- [ ] The codex-conventions maintenance doc exists under `docs/` (Diátaxis), marked maintenance-only,
      and is indexed in `docs/README.md`. It is NOT under `skill-refs/`.
- [ ] `install.sh` deploys `skill-refs/` to `$XDG_DATA_HOME/cog/skill-refs` with pre-clean and
      manifest tracking; `docs/guides/install.md` documents it.
- [ ] A new self-containment ADR exists (next free number); ADR 0007 cites the in-repo skill-ref;
      ADR 0009 has the provenance-citation note.
- [ ] `AGENTS.md` has a Reference Self-Containment guard and `CLAUDE.md` has the companion
      non-negotiable line.
- [ ] `docs/reference/cli-commands.md` lists the Round-1 commands; `docs/README.md` and
      `docs/reference/skills.md` are updated.
- [ ] No `SKILL.md` is modified in this round; DocsNNotes is untouched. `just lint` and `just test`
      pass.
- [ ] This plan's `QUEUE.yaml` shows round `migrate-content-and-packaging` as `done`.

## Next Round

Round 3 (`rewire-skills-and-cleanup`) repoints the ~12 consuming `SKILL.md` files from
`$DOCS_NOTES_REPO/tech/tools/claude-code/...` to `$(cog skill-refs path ...)`, removes the
codex-conventions runtime injection in favor of `cog codex-runner orientation`/`explain-status`, runs
the full verification sweep, and — only once cog is verified self-contained — clean-deletes the
migrated files from DocsNNotes.
