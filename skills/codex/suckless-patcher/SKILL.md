---
name: suckless-patcher
description: >
  Delegates deterministic tree checks, patch application, build verification,
  and conflict artifact listing to cog while preserving patch research
  and conflict judgment in prose. Use when the user says "suckless-patcher",
  "apply a patch", "patch dwm/st/dmenu", "apply suckless patch", or "patch and
  build".
---

# Suckless Patcher — Codex Twin

The shared mechanical contract is identical to the Claude `suckless-patcher` skill.

## Reference Resolution

Shared references ship with `cog` and resolve through `cog skill-refs path <rel>`. The resolver always succeeds for shipped references. `REFS/patch-strategies.md` means `$(cog skill-refs path tools/suckless/patch-strategies.md)`.

## Inputs

The user provides:

1. Patch file - a `.diff` file, local path or to be downloaded.
2. Patch URL - the suckless.org page for this patch, such as `https://dwm.suckless.org/patches/vanitygaps/`.

## Cog Contract

`cog` must be on `PATH`; a bare call fails legibly if it is missing. Create the run directory and output paths:

```bash
RUN_DIR="$(cog rundir suckless-patcher-codex | sed -n 's/^RUN_DIR=//p')"
PREFLIGHT_JSON="$RUN_DIR/preflight.json"
APPLY_JSON="$RUN_DIR/apply.json"
CONFLICTS_JSON="$RUN_DIR/conflicts.json"
```

Mechanical commands:

```bash
cog suckless-preflight "$PREFLIGHT_JSON"
cog suckless-apply --patch "$PATCH_FILE" "$APPLY_JSON"
cog suckless-conflicts "$CONFLICTS_JSON"
```

`suckless-preflight` checks tree shape and clean git state:

```json
{
  "ok": true,
  "repo_root": "/absolute/path",
  "is_suckless_tree": true,
  "detected_project": "dwm",
  "signals": {"has_config_mk": true, "has_makefile": true, "c_files": ["dwm.c"]},
  "clean_tree": true,
  "status": {"root": "/absolute/path", "branch": "main", "files": []},
  "reason": null
}
```

`suckless-apply` checks/apply the patch and runs `make clean && make`:

```json
{
  "ok": true,
  "repo_root": "/absolute/path",
  "patch": "/absolute/path/patch.diff",
  "method": "git-apply",
  "check": {"ok": true, "exit_code": 0, "log": "/path/check.log"},
  "three_way_check": {"ok": false, "exit_code": null, "log": "/path/three_way_check.log"},
  "apply": {"ok": true, "exit_code": 0, "log": "/path/apply.log"},
  "build": {"ok": true, "exit_code": 0, "log": "/path/build.log"},
  "needs_conflict_resolution": false,
  "reason": null
}
```

Any non-zero plain `git apply --check` is treated as conflict evidence. The helper may attempt `--3way`; if both checks fail, conflict resolution remains prose work.

`suckless-conflicts` lists reject artifacts:

```json
{
  "ok": true,
  "repo_root": "/absolute/path",
  "rejects": [{"path": "dwm.c.rej", "target": "dwm.c", "lines": 42}],
  "orig_files": ["dwm.c.orig"],
  "count": 1
}
```

## Workflow

1. Resolve the source tree and patch file. Run `suckless-preflight`. If the tree is not recognized or is dirty, stop and report the helper's reason. Do not create branches in this skill; repository orchestration remains outside the helper.

2. Research the patch URL with Codex web tools. Extract description, latest available version, dependencies, and compatible suckless versions. If the user's patch appears stale, explain the difference and ask whether to proceed or download the latest. Codex does not use `AskUserQuestion`; use normal message-channel prompting for confirmations.

3. Run `suckless-apply`. If it succeeds, inspect the build status and summarize method, files changed, and build result.

4. If `suckless-apply` reports `needs_conflict_resolution=true`, run `suckless-conflicts`, then read the referenced `.rej` files. Use `REFS/patch-strategies.md` for the conflict-resolution playbook.

5. Resolve conflicts in prose and with targeted edits, preferring `apply_patch` for manual conflict edits. For each rejected hunk, identify the intended behavior, apply the intent manually, and explain the edit to the user.

6. Protect `config.h`. Never blindly overwrite it. If the patch changes `config.def.h`, explain which changes may need to be merged into `config.h` and offer selective help.

7. If the build fails, read the compiler errors and cross-reference the patch description and source layout. Apply trivial fixes directly; for non-trivial fixes, explain the issue and proposed fix before editing.

8. Final report:
   - patch name, version, and URL;
   - method used or manual resolution summary;
   - files modified;
   - build status;
   - conflicts resolved and how;
   - suggested commit message.

## Codex-Specific Notes

- No `AskUserQuestion`; prompt through normal messages when confirmation is required.
- Prefer `apply_patch` for manual source edits.
- Keep this workflow twin-equivalent to the Claude `suckless-patcher` skill; helper contract drift is a bug.

## Guardrails

- Apply one patch at a time and verify builds between stacked patches.
- When a patch targets a specific commit or version tag, flag ahead/behind risks.
- Do not treat helper output as conflict resolution. It identifies mechanics; interpretation stays in this skill.
