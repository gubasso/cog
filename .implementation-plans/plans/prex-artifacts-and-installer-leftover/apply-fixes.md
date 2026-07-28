# Fix `/prex` migration artifacts, stale skill-name refs, and make the installer self-cleaning

> Plan: prex-artifacts-and-installer-leftover | Round: 1 of 1 | Complexity: M | Generated: 2026-06-22T19:44:56Z | Repo: /workspaces/cog

## Context

`cog` migrated its executor skill from `/prex` to `/executor-prex`, and ADR-0018 (`docs/decisions/0018-remove-tsk-and-prex-converge-executor-prex.md`) then **removed `/prex` entirely** — there is no `/prex` alias and no `/prex` compatibility form anymore. A later mechanical search-and-replace converted the _surviving_ `/prex` compatibility-language to `/executor-prex` without reading the sentences, producing **self-referential nonsense** such as "`/executor-prex` is supported only as an alias for `/executor-prex`". These are false statements: they imply a compatibility layer that ADR-0018 deleted.

Separately, the orchestration skill was renamed `plan-queue-runner` → `runner-queue` (its directory is now `skills/claude/runner-queue/`). Several `skill-refs/` reference docs still name the old `plan-queue-runner`, and one **deployed** copy of the pre-rename skill still sits in the user's home at `~/.claude/skills/plan-queue-runner/` (carrying the old `/prex` frontmatter text).

Root cause of the deployed leftover: `install.sh` hard-clears the cog-owned **app payload** before recopy, but deliberately does **not** clear the user-home skill/agent roots (they may hold user-authored skills). `copy_tree` only overlays, so a renamed/removed cog skill leaves its old directory behind forever. This round fixes the three prose artifacts, renames the stale skill-refs references, removes the existing deployed orphan, and makes `install.sh` self-cleaning via a manifest-diff prune so this class of leftover cannot recur.

The repo's _functional_ state is already correct — no live code invokes `/prex`. Everything here is a documentation-truth, deployed-artifact, and installer-hygiene fix.

## Previous Rounds

This is the first round — no prior rounds.

## Scope of This Round

IN scope:

1. Remove three self-referential `/executor-prex` "alias / compatibility form" clauses in two `SKILL.md` files.
2. Rename the five stale `plan-queue-runner` references in `skill-refs/` to `runner-queue`.
3. Delete the orphaned deployed skill directory `~/.claude/skills/plan-queue-runner/`.
4. Make `install.sh` self-cleaning: extract shared bootstrap helpers into a new repo-root `install-common.sh`, source it from both `install.sh` and `uninstall.sh`, and add a manifest-diff stale-prune step to `install.sh`.
5. Validate: `cog skill-lint` on the touched skills, verification greps, and a disposable-prefix install/uninstall test.

OUT of scope:

- Editing ADRs `docs/decisions/0007-*` and `docs/decisions/0018-*` — they mention `/prex` and `plan-queue-runner` as **historical record**; accepted ADRs are never rewritten (per `AGENTS.md`).
- Any git operations (staging, committing, branching). Committing is the user's separate `/gc` step.
- Renaming `plan-queue-runner` anywhere outside `skill-refs/`.

## Current State

### Key Files

- `/workspaces/cog/skills/claude/runner-queue/SKILL.md` — two botched lines. Quote the current text (line numbers drift; match by content):
  - The parenthetical inside the resolver paragraph currently reads: `hardcoded list (`/executor-prex`stays an alias for`/executor-prex`) — maps it to the plan directory's inner`
  - A bullet under `## Rules` currently reads: `- Use queued prompts verbatim. Do not reconstruct executor commands. Any`/executor-*`prompt is accepted (matched by the prefix taxonomy);`/executor-prex`is supported only as an alias for`/executor-prex`.`

- `/workspaces/cog/skills/claude/plan-writer/SKILL.md` — one botched bullet that currently spans two lines:

  ```text
  - Exact execution commands (`/executor-prex -ar` per-round or full-directory; `/executor-prex` remains a
    supported compatibility form for existing queues).
  ```

- `/workspaces/cog/skill-refs/skill-authoring/skill-script-extraction.md` — two `plan-queue-runner` references:
  - `vocabulary: a parent (`/plan-queue-runner`) parses the last non-empty line of a child's output`
  - `multi-line parsers (executor-prex, plan-writer-multi, plan-queue-runner) earn a subcommand.`

- `/workspaces/cog/skill-refs/orchestration/in-session-vs-headless-delegation.md` — three `plan-queue-runner` references:
  - `` `plan-queue-runner`) dispatch each unit to it via the **Agent tool**. ``
  - ``SIGTERM-reaped (observed 2026-06-17, `plan-queue-runner` → `claude-delegate` → `executor-prex` stage 3). The``
  - `` `claude/.claude/agents/claude-delegate.md`, `claude/.claude/skills/plan-queue-runner/SKILL.md`, and ``

- `/workspaces/cog/install.sh` — installer. Relevant structure:
  - `resolve_repo_root()` (lines ~5-18) computes `repo_root`.
  - The app-payload hard-clear and copy (lines ~99-120):

    ```bash
    install -d "$app_root"
    rm -rf -- "${app_root:?}/bin" "${app_root:?}/lib" "${app_root:?}/VERSION"
    rm -rf -- "${data_dir:?}/skill-refs"
    copy_tree "$repo_root/bin" "$app_root/bin"
    ...
    copy_tree "$repo_root/skills/claude" "$home/.claude/skills"
    copy_tree "$repo_root/agents/claude" "$home/.claude/agents"
    copy_tree "$repo_root/skills/codex" "$home/.agents/skills"
    ```

  - The manifest finalize (lines ~128-130):

    ```bash
    sort -u "$manifest_tmp" >"$manifest_tmp.sorted"
    mv -f "$manifest_tmp.sorted" "$manifest"
    rm -f "$manifest_tmp"
    ```

  - Root vars defined ~76-87: `home`, `prefix`, `xdg_data_home`, `xdg_state_home`, `app_root`, `bin_link`, `data_dir`, `comp_dir`, `man_dir`, `state_dir`, `manifest`.

- `/workspaces/cog/uninstall.sh` — currently defines these helpers **inline** (to be moved to the shared file): `path_under`, `valid_manifest_path`, `rmdir_empty`, `prune_empty_tree`, `prune_manifest_skill_dir`. Its root vars (`home`, `prefix`, `app_root`, `data_dir`, `comp_dir`, `man_dir`, `state_dir`, `manifest`) are defined ~67-76, before the first helper call.

- `/workspaces/cog/justfile` — `install:` target runs `./install.sh`; `uninstall:` runs `./uninstall.sh`. No changes needed unless the scripts move.

### Existing Patterns

- `install.sh` and `uninstall.sh` are **standalone bootstrap scripts** that run from the repo checkout (before `cog` is on PATH), so they cannot use `cog::fn::*` helpers. They CAN source a sibling repo-root file resolved relative to `BASH_SOURCE`.
- Both scripts start with `set -euo pipefail` and `shopt -s inherit_errexit 2>/dev/null || true`.
- Bash resolves globals at **call time**, so a sourced helper that reads `app_root`/`home`/etc. works as long as those vars are assigned before the helper is _called_ (sourcing the helper file before the var block is fine).
- The install manifest at `${XDG_STATE_HOME:-$HOME/.local/state}/cog/install-manifest` records one absolute path per cog-owned deployed file, `sort -u`. User-authored files are never recorded.
- `valid_manifest_path` (in `uninstall.sh`) is the canonical "is this path a cog-owned root" gate; the install-time prune must reuse the exact same function for safety.

### Important fact

The current manifest does **not** list `plan-queue-runner` (the last install post-dated the rename), so the new manifest-diff prune alone cannot remove the existing orphan — Step 3's explicit `rm` is required on this machine. The prune prevents _future_ renamed/removed skills from leaking.

## Implementation Steps

### First Step: Mark this round as started

In this plan's `queue-rounds.yaml` (`/workspaces/cog/.implementation-plans/plans/prex-artifacts-and-installer-leftover/queue-rounds.yaml`), set this round's (`item: apply-fixes`) `status` to `doing`. Use `cog queue-status-set --queue <path> --schema rounds --item apply-fixes --from todo --to doing <out.json>` rather than hand-editing YAML.

### Step 1: Remove the self-referential `/prex` artifacts (two SKILL.md files)

These clauses describe a `/prex` alias/compatibility form that ADR-0018 deleted. Delete the clause, leaving the clean canonical statement (consistent with ADR-0019 lean, positive prose — describe what the skill IS, no dead guardrails).

In `/workspaces/cog/skills/claude/runner-queue/SKILL.md`:

- Change `hardcoded list (`/executor-prex`stays an alias for`/executor-prex`) — maps it to the plan directory's inner` to `hardcoded list — maps it to the plan directory's inner` (delete the `(`/executor-prex`stays an alias for`/executor-prex`)` parenthetical only; keep the surrounding em-dash sentence intact).

- Change the Rules bullet `- Use queued prompts verbatim. Do not reconstruct executor commands. Any`/executor-_`prompt is accepted (matched by the prefix taxonomy);`/executor-prex`is supported only as an alias for`/executor-prex`.` to `- Use queued prompts verbatim. Do not reconstruct executor commands. Any`/executor-_ `prompt is accepted (matched by the prefix taxonomy).` (delete the `;`/executor-prex`is supported only as an alias for`/executor-prex`` clause; keep the trailing period).

In `/workspaces/cog/skills/claude/plan-writer/SKILL.md`:

- Collapse the two-line bullet

  ```text
  - Exact execution commands (`/executor-prex -ar` per-round or full-directory; `/executor-prex` remains a
    supported compatibility form for existing queues).
  ```

  into a single line:

  ```text
  - Exact execution commands (`/executor-prex -ar` per-round or full-directory).
  ```

### Step 2: Rename stale `plan-queue-runner` references in `skill-refs/`

Replace the old skill name with the current one (`runner-queue`) in the five spots below. These are live references to the skill in reference docs; the dated 2026-06-17 line keeps its date — only the skill token changes.

In `/workspaces/cog/skill-refs/skill-authoring/skill-script-extraction.md`:

- `(`/plan-queue-runner`)` → `(`/runner-queue`)`
- `multi-line parsers (executor-prex, plan-writer-multi, plan-queue-runner) earn a subcommand.` → `multi-line parsers (executor-prex, plan-writer-multi, runner-queue) earn a subcommand.`

In `/workspaces/cog/skill-refs/orchestration/in-session-vs-headless-delegation.md`:

- `` `plan-queue-runner`) dispatch each unit `` → `` `runner-queue`) dispatch each unit ``
- ``(observed 2026-06-17, `plan-queue-runner` → `claude-delegate`` → ``(observed 2026-06-17, `runner-queue` → `claude-delegate``
- `` `claude/.claude/skills/plan-queue-runner/SKILL.md` `` → `` `claude/.claude/skills/runner-queue/SKILL.md` ``

After editing, confirm none remain in `skill-refs/`: `rg -n 'plan-queue-runner' skill-refs/` must print nothing.

### Step 3: Remove the orphaned deployed skill (one-time, outside the repo)

The pre-rename skill is still deployed at `~/.claude/skills/plan-queue-runner/`. It is not in the repo and not in the install manifest, so only a manual removal clears it on this machine. Guard the delete by confirming the directory exists first:

```bash
ORPHAN="$HOME/.claude/skills/plan-queue-runner"
if [ -d "$ORPHAN" ]; then
  rm -rf -- "$ORPHAN"
  echo "removed orphan: $ORPHAN"
else
  echo "no orphan present: $ORPHAN"
fi
```

Do not touch `~/.claude/skills/runner-queue/` — that is the correct current deployment.

### Step 4: Make `install.sh` self-cleaning (shared helper + manifest-diff prune)

**4a. Create the shared helper `/workspaces/cog/install-common.sh`.** Move these five functions verbatim out of `uninstall.sh` into this new file (give it a `#!/usr/bin/env bash`-free body since it is sourced, but keep it self-documenting): `path_under`, `valid_manifest_path`, `rmdir_empty`, `prune_empty_tree`, `prune_manifest_skill_dir`. These functions read the caller's root vars (`app_root`, `data_dir`, `comp_dir`, `man_dir`, `state_dir`, `prefix`, `home`) as globals at call time, so the file defines functions only — no var assignments.

**4b. Source the helper from both scripts.** In each of `install.sh` and `uninstall.sh`, after the root-var block is assigned, add a source line that resolves the helper next to the script:

```bash
# Resolve this script's own directory to find the shared helper.
_self_dir="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=install-common.sh
. "$_self_dir/install-common.sh"
```

`install.sh` already has `resolve_repo_root()` returning `repo_root`; `install-common.sh` lives at `$repo_root/install-common.sh`, so `. "$repo_root/install-common.sh"` is equivalent and may be used instead of `_self_dir`. Pick one approach and use it consistently. `uninstall.sh` has no resolver today — add the `_self_dir` snippet there.

**4c. Delete the now-duplicated inline helpers from `uninstall.sh`** (the five functions moved in 4a). Its behavior must be unchanged: it still sources the helper, then runs the same manifest walk + prune.

**4d. Add the manifest-diff stale-prune to `install.sh`.** Insert it between the manifest sort and the `mv` finalize. Current code:

```bash
sort -u "$manifest_tmp" >"$manifest_tmp.sorted"
mv -f "$manifest_tmp.sorted" "$manifest"
rm -f "$manifest_tmp"
```

Becomes:

```bash
sort -u "$manifest_tmp" >"$manifest_tmp.sorted"

# Stale-prune: remove cog-owned files the previous install shipped that this
# install no longer ships (e.g. a renamed/removed skill directory). User-authored
# files are never recorded in a manifest, so they are never pruned. First-ever
# install has no prior manifest and prunes nothing. App-payload entries already
# removed by the hard-clear above make their `rm -f` a harmless no-op.
if [[ -e $manifest ]]; then
  while IFS= read -r stale; do
    valid_manifest_path "$stale" || continue
    rm -f -- "$stale"
    prune_manifest_skill_dir "$stale" "$home/.claude/skills"
    prune_manifest_skill_dir "$stale" "$home/.claude/agents"
    prune_manifest_skill_dir "$stale" "$home/.agents/skills"
  done < <(comm -23 <(sort -u "$manifest") "$manifest_tmp.sorted")
fi

mv -f "$manifest_tmp.sorted" "$manifest"
rm -f "$manifest_tmp"
```

Notes:

- `comm -23 OLD NEW` emits lines present only in OLD (the prior manifest) — i.e. paths no longer shipped. Both inputs must be sorted; `$manifest_tmp.sorted` is already `sort -u`, and the old `$manifest` is re-sorted defensively.
- Keep the existing app-payload hard-clear (lines ~106-107) as-is; the prune is additive and mainly matters for the user-home roots that are not hard-cleared.

**4e.** Run `bash -n install.sh uninstall.sh install-common.sh` to syntax-check all three.

### Final Step: Update the queue

Record completion — status lives in YAML; nothing moves on disk:

1. In this plan's `queue-rounds.yaml`, set this round's (`item: apply-fixes`) `status` to `done` via `cog queue-status-set --schema rounds --item apply-fixes --from doing --to done`.
2. This is the only round, so in the top-level `/workspaces/cog/.implementation-plans/queue-plans.yaml` set this plan's (`item: prex-artifacts-and-installer-leftover`) `status` to `done` via `cog queue-status-set --schema plans --item prex-artifacts-and-installer-leftover --from todo --to done`. Leave the plan directory in place.

## Acceptance Criteria

- [ ] `rg -n 'alias for`/executor-prex`|remains a' skills/` returns no self-referential matches; the three edited lines read as clean canonical statements.
- [ ] `rg -n 'plan-queue-runner' skill-refs/` returns nothing.
- [ ] `rg -n 'plan-queue-runner' . | grep -v '\.git/'` returns only `docs/decisions/0007-*` and `docs/decisions/0018-*` (historical ADRs, intentionally untouched).
- [ ] `~/.claude/skills/plan-queue-runner/` does not exist; `~/.claude/skills/runner-queue/` is untouched.
- [ ] `install-common.sh` exists and is sourced by both `install.sh` and `uninstall.sh`; the five helper functions are defined only there (not duplicated in `uninstall.sh`).
- [ ] `install.sh` contains the manifest-diff stale-prune between the manifest sort and `mv`.
- [ ] `bash -n install.sh uninstall.sh install-common.sh` passes.
- [ ] Disposable-prefix test: with `PREFIX`/`XDG_DATA_HOME`/`XDG_STATE_HOME` set to fresh temp dirs, `./install.sh` runs; after injecting a fake `<skills>/zzz-old/SKILL.md` plus its path into the manifest, a second `./install.sh` prunes `zzz-old/` while a non-manifest `user-authored/` skill survives; `./uninstall.sh` then removes all cog files and leaves user content.
- [ ] `cog skill-lint skills/claude/runner-queue/SKILL.md skills/claude/plan-writer/SKILL.md` passes.
- [ ] This plan's `queue-rounds.yaml` shows round `apply-fixes` as `done`.
- [ ] The top-level `.implementation-plans/queue-plans.yaml` shows this plan as `done`.

## Next Round

This is the final round.
