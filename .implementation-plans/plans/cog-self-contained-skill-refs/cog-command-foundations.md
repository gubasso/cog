# cog Command Foundations: skill-refs Resolver + codex-runner Orientation/Status

> Plan: cog-self-contained-skill-refs | Round: 1 of 3 | Complexity: L | Generated: 2026-06-19 |
> Repo: /workspaces/cog

## Context

`cog` is a Bash CLI plus shipped Claude/Codex skills. Today several skills load load-bearing
"skill-source" reference docs at runtime from an external repo via literal
`$DOCS_NOTES_REPO/tech/tools/claude-code/...` paths, which makes a fresh install depend on a repo the
user never installed. The fix is to ship those docs in-repo and resolve them deterministically, and
to finish absorbing the `codex-conventions.md` runtime guidance into the cog CLI so skills stop
injecting it.

This round builds the **deterministic plumbing** that later rounds consume. Per the repo's
non-negotiable boundary (`CLAUDE.md`, `docs/decisions/0008-skill-script-boundary.md`,
`docs/reference/skill-contract.md`): deterministic mechanics live in `cog` subcommands and
`cog::fn::*` helpers; skills keep only judgment in prose. So the path resolution and the Codex
orientation/quota text become cog mechanics, not skill prose.

Two new surfaces are added here: (1) `cog skill-refs` — resolves the in-repo/installed skill-source
tree; (2) `cog codex-runner orientation` plus a documented status contract — emits the read-only/write
Codex preambles and the quota/status guidance that skills currently copy out of `codex-conventions.md`.
No skills are rewired in this round and no content is migrated yet — only the cog surfaces, their
tests, and their completion/man registration.

## Previous Rounds

This is the first round — no prior rounds.

## Scope of This Round

IN scope:

- New command module `lib/commands/cmd_skill_refs.sh` (`cog::cmd::skill_refs`) with subcommands
  `path <rel>` and `root`.
- New helper `lib/functions/fn_skill_refs.sh` (`cog::fn::skill_refs_root`) with XDG-first,
  repo-source-fallback resolution; sourced eagerly from `bin/cog`.
- Extend `lib/commands/cmd_codex_runner.sh` + `lib/functions/fn_codex.sh` with
  `cog codex-runner orientation <read-only|write>` (emits the exact preamble text, held as cog-owned
  data) and `cog codex-runner explain-status <status>` (emits quota/wait-vs-retry guidance keyed off
  the runner's existing status classes).
- Unit tests for the resolver (XDG hit, repo-source fallback, fail-closed when neither exists) and
  for orientation/explain-status output.
- Register both new command surfaces in `completions/cog.bash` and `man/cog.1.scd`, keeping the
  line-2 `: 'desc: ...'` sentinel in each command module.

OUT of scope (later rounds):

- Creating the actual `skill-refs/` content tree and moving `codex-conventions.md` → `docs/`
  (Round 2).
- The installer XDG deploy and governance docs (Round 2).
- Repointing any `SKILL.md` or removing codex-conventions injection from skills (Round 3).

## Current State

### Key Files

- `bin/cog` — resolves the real app root through symlinks, then eagerly sources core functions before
  dispatch. New helpers must be sourced here. Current source block ends with:

  ```bash
  # shellcheck source=../lib/functions/fn_codex.sh
  source "${LIB_DIR}/functions/fn_codex.sh"
  # shellcheck source=../lib/core.sh
  source "${LIB_DIR}/core.sh"

  cog::main "$@"
  ```

  `LIB_DIR` is `readonly LIB_DIR="${SCRIPT_DIR}/../lib"` and is visible to all sourced modules.

- `lib/core.sh` — establishes the `${LIB_DIR}/..` app-root anchor; line 4 resolves VERSION as
  `local version_file="${LIB_DIR}/../VERSION"`. The skill-refs repo-source fallback uses the same
  anchor: `${LIB_DIR}/../skill-refs`.

- `lib/loader.sh` — derives `cmd_<slug>.sh` / `cog::cmd::<slug>` from the requested command
  (dashes→underscores). `cog skill-refs` maps to `lib/commands/cmd_skill_refs.sh` /
  `cog::cmd::skill_refs`. No loader change needed; just add the module.

- `lib/commands/cmd_rundir.sh` — reference shape for a small path-producing command: line-2
  `: 'desc: ...'` sentinel, a `__cog_<cmd>_usage` helper, `-h|--help` handling, `cog::fn::ui_data`
  for machine output, and `cog::fn::error_raise` for failures. Mirror this shape.

- `lib/commands/cmd_codex_runner.sh` — `desc:` sentinel on line 2 (`Run codex-session orchestration
  helpers.`). Dispatch is a `case "$mode"` near the bottom routing `run-exec`, `run-resume`, `gate`,
  `verify-proof`. Add `orientation` and `explain-status` cases here, each with a usage line in the
  `__cog_codex_runner_usage` block (which already lists run-exec/run-resume/gate usages).

- `lib/functions/fn_codex.sh` — owns deterministic Codex mechanics already: exec/resume construction,
  sandbox native/fallback, `--account` pinning, `</dev/null`, `--output-last-message`, thread-id
  extraction (`jq 'select(.type=="thread.started")'`), and status/exit classification mapping exit
  codes to status classes (`ok`, quota knees, `resume-blocked`, `timeout`, `sigterm`). The
  orientation text and the status-explanation text become new cog-owned data here (e.g. heredoc
  emitters), so they ship inside cog and never read `$DOCS_NOTES_REPO`.

- `lib/functions/fn_refs.sh` — the EXTERNAL general-ref resolver (`cog::fn::refs_resolve_docs_path`
  searches `$DOCS_NOTES_REPO` and candidate dirs for a `tech/` subtree). Do NOT modify it and do NOT
  imitate its external-search behavior: `skill-refs` is an in-repo/installed tree, a different
  mechanism. Keep them separate.

- Source content for the orientation blocks and quota/status semantics currently lives in
  `/home/gbasso/DocsNNotes/tech/tools/claude-code/codex-conventions.md` (read-only/write orientation
  preambles; "Quota knees & out-of-quota errors"; "Wrapper Exit Codes"). Lift the exact preamble text
  and the quota guidance from there into the cog emitters.

- `man/cog.1.scd` + `completions/cog.bash` — must gain entries for the new commands. The repo runs
  completion/man drift checks that depend on each command module's line-2 `: 'desc: ...'` sentinel.

### Existing Patterns

- Commands: module `lib/commands/cmd_<slug_with_underscores>.sh`; handler
  `cog::cmd::<slug_with_underscores>`; user-facing names use dashes (loader maps to underscores).
- Shared helpers: `cog::fn::*` in `lib/functions/`, sourced from `bin/cog`.
- Machine-facing output is the default contract (file-first/machine output); use `cog::fn::ui_data`
  / JSON emit helpers, and `cog::fn::error_raise "<Class>" "<msg>" ...` for fail-closed errors with a
  legible message (see `cmd_codex_runner.sh` error_raise calls and `docs/decisions/0009-machine-facing-output-contract.md`).
- Tests live under the repo test tree exercised by `just test` (unit + integration hooks);
  `pre-commit` via `just lint` is the quality gate.

## Implementation Steps

### First Step: Mark this round as started

In this plan's `QUEUE.yaml`
(`.implementation-plans/plans/cog-self-contained-skill-refs/QUEUE.yaml`), set this round's
(`item: cog-command-foundations`) `status` to `doing`.

### Step 1: Add the `cog::fn::skill_refs_root` helper

Create `lib/functions/fn_skill_refs.sh` defining `cog::fn::skill_refs_root` that prints the absolute
skill-refs root and returns non-zero (no output) when none is found:

1. Compute the XDG deploy candidate: `"${XDG_DATA_HOME:-$HOME/.local/share}/cog/skill-refs"`.
2. Compute the repo-source fallback: `"${LIB_DIR}/../skill-refs"` (normalize with `cd -P`/`pwd` like
   `bin/cog` does for `SCRIPT_DIR`).
3. Return the first candidate that exists as a directory, XDG first.
4. If neither exists, return 1 with no stdout (callers fail closed).

Add a sibling `cog::fn::skill_refs_path <rel>` (or fold into the command) that joins the root with a
relative path and verifies the resulting file/dir exists, failing closed otherwise.

### Step 2: Source the helper from `bin/cog`

In `bin/cog`, add a `source "${LIB_DIR}/functions/fn_skill_refs.sh"` line alongside the other
`fn_*.sh` sources (e.g. immediately after the `fn_codex.sh` source), with the matching
`# shellcheck source=...` comment.

### Step 3: Add the `cog skill-refs` command module

Create `lib/commands/cmd_skill_refs.sh` with the line-2 sentinel
`: 'desc: Resolve in-repo/installed skill-source reference files.'` and `cog::cmd::skill_refs`:

- `cog skill-refs root` → print the resolved root (via `cog::fn::skill_refs_root`); fail closed with
  `cog::fn::error_raise` (e.g. class `NotFound`) and a legible message when unresolved.
- `cog skill-refs path <rel>` → print the absolute path to `<rel>` under the root; fail closed when
  the root is unresolved OR `<rel>` does not exist, with a message naming the missing path.
- `-h|--help` prints a `__cog_skill_refs_usage` line. Use `cog::fn::ui_data` for output. Follow
  `cmd_rundir.sh` for structure.

### Step 4: Add `cog codex-runner orientation` and `explain-status`

In `lib/functions/fn_codex.sh`, add emitters holding the data as cog-owned text:

- `cog::fn::codex_orientation <read-only|write>` — emits the exact preamble block (lifted verbatim
  from `codex-conventions.md`'s read-only / write orientation sections). Invalid mode → fail closed.
- `cog::fn::codex_explain_status <status>` — emits the quota/wait-vs-retry guidance for a given
  runner status class (`ok`, quota knees, `resume-blocked`, `timeout`, `sigterm`, …), lifted from the
  doc's quota + exit-code sections. Unknown status → fail closed with the list of known statuses.

In `lib/commands/cmd_codex_runner.sh`: add `orientation` and `explain-status` to the `case "$mode"`
dispatch, each validating its argument and delegating to the new `fn_codex` emitters; add their usage
lines to `__cog_codex_runner_usage`.

### Step 5: Unit tests

Add unit tests (in the repo's unit test tree, run by `just test`):

- `skill_refs_root`: XDG candidate present → returns it; XDG absent but repo-source present → returns
  the fallback; neither present → non-zero, empty stdout. Drive via temporary `XDG_DATA_HOME` and a
  temp fixture tree; for the fallback, point at a fixture acting as `${LIB_DIR}/../skill-refs`.
- `cog skill-refs path <rel>`: existing rel → absolute path; missing rel → fail closed; unresolved
  root → fail closed.
- `cog codex-runner orientation read-only|write` → non-empty expected preamble; invalid mode → fail
  closed.
- `cog codex-runner explain-status <known>` → non-empty; unknown → fail closed.

### Step 6: Completion + man registration

- Add `skill-refs` (with `path`/`root`) and the new `codex-runner` subcommands (`orientation`,
  `explain-status`) to `completions/cog.bash`.
- Add corresponding entries to `man/cog.1.scd`.
- Confirm the line-2 `: 'desc: ...'` sentinel exists in `cmd_skill_refs.sh` and remains intact in
  `cmd_codex_runner.sh`, so the completion/man drift checks and root help stay consistent.

### Final Step: Update the queue

Record completion in the queue — status lives in YAML; nothing moves on disk:

1. In this plan's `QUEUE.yaml`, set this round's (`item: cog-command-foundations`) `status` to
   `done`.

## Acceptance Criteria

- [ ] `cog skill-refs root` prints a directory when an XDG deploy or repo-source `skill-refs/` exists,
      and fails closed with a legible message when neither exists.
- [ ] `cog skill-refs path <rel>` prints the absolute path for an existing rel and fails closed for a
      missing rel or unresolved root.
- [ ] Resolution prefers `$XDG_DATA_HOME/cog/skill-refs` over `${LIB_DIR}/../skill-refs`.
- [ ] `cog codex-runner orientation read-only` and `... write` emit the expected preamble text;
      invalid mode fails closed.
- [ ] `cog codex-runner explain-status <status>` emits guidance for known statuses and fails closed
      for unknown ones.
- [ ] `fn_skill_refs.sh` is sourced from `bin/cog`; `cmd_skill_refs.sh` carries its line-2 `desc:`
      sentinel.
- [ ] New commands appear in `completions/cog.bash` and `man/cog.1.scd`; `just lint` and `just test`
      pass.
- [ ] `lib/functions/fn_refs.sh` and `lib/commands/cmd_review_refs.sh` are unchanged.
- [ ] This plan's `QUEUE.yaml` shows round `cog-command-foundations` as `done`.

## Next Round

Round 2 (`migrate-content-and-packaging`) creates the actual `skill-refs/` content tree (the 10
skill-source files), moves `codex-conventions.md` into `docs/` as a maintenance reference, wires the
installer to deploy `skill-refs/` to `$XDG_DATA_HOME/cog/skill-refs`, and lands the governance ADR +
`AGENTS.md`/`CLAUDE.md` rule. It relies on the `cog skill-refs` resolver and the `codex-runner`
orientation/status surface built here.
