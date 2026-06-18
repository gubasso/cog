---
name: tsk-impl
description: >
  Delegates deterministic issue fetching to the cog CLI while preserving
  completeness assessment and implementation judgment in prose. Use when the
  user says "tsk-impl", "implement this issue", "implement the task", "work on
  issue <id>", or "implement the tsk issue".
---

<!-- trigger-tests: "tsk-impl", "implement this issue", "implement the task", "work on issue", "implement the tsk issue" -->

# Tsk Impl

Implement a `tsk` issue directly in the current Claude session. The issue body
is the implementation prompt unless it is too thin, vague, or incomplete.

## Non-Negotiable Rules

- Never fabricate an issue id.
- Never substitute assumptions for what the issue body says.
- Do not mutate, close, reopen, or edit the issue.
- Do not run git commit, stage, push, branch, reset, checkout, or stash
  commands.
- Do not dispatch implementation to Codex or another external agent.
- Always preserve the issue body through a staging file before implementation.

## Agent-Helper Contract

Mechanical commands:

```bash
cog tsk-store-init --json
cog tsk-fetch-issue --id "$TSK_ID" --json
cog tsk-fetch-issue --title "$TITLE" --body-file "$BODY_FILE" --json
cog tsk-snapshot --json
```

`tsk-store-init` emits:

```json
{
  "store": "/absolute/or/resolved/path",
  "config_path": "/path/config.yaml",
  "template_path": "/path/templates/task.md",
  "config_exists": true,
  "template_exists": true,
  "initialized": false,
  "doctor_repo": "/path/from/doctor-or-null"
}
```

`tsk-fetch-issue` emits:

```json
{
  "mode": "fetch",
  "id": "tsk-123",
  "path": "/path/to/issue.md",
  "remote_url": null,
  "title": null,
  "issue": "raw tsk show output"
}
```

`path`, `remote_url`, and `title` can be `null`. The `issue` field is raw
`tsk show` output and is the source material for the implementation prompt.

`tsk-snapshot` emits:

```json
{
  "repo_root": "/absolute/path",
  "branch": "main",
  "status": {
    "root": "/absolute/path",
    "branch": "main",
    "files": [
      {
        "xy": " M",
        "path": "file.txt",
        "orig_path": null,
        "staged": false,
        "unstaged": true,
        "untracked": false
      }
    ]
  },
  "staged_files": ["staged.txt"],
  "unstaged_files": ["changed.txt"],
  "diff_stats": {
    "staged": {"mode": "staged", "files": []},
    "unstaged": {"mode": "unstaged", "files": []}
  },
  "recent_log": [{"sha": "abc1234", "subject": "initial"}]
}
```

## Workflow

1. Resolve the issue id.

   If `$ARGUMENTS` contains a non-flag first token, use it as `TSK_ID`. If it is
   blank or starts with `-`, resolve branch-to-issue id directly with `tsk id`.
   Branch id resolution stays outside this round's helper scope; do not invent
   an `cog` command for it.

   If `tsk id` fails, report the captured output and stop. Do not guess and do
   not continue from session context.

2. Fetch the issue through the helper.

   ```bash
   cog tsk-fetch-issue --id "$TSK_ID" --json
   ```

   If the helper fails, stop and report the failure. Do not run `tsk init`
   silently; fetch mode intentionally does not initialize the store.

3. Persist the issue body.

   Create a staging directory, then write `.issue` from the helper output into
   it:

   ```bash
   _SKILL_RUNS="${XDG_STATE_HOME:-$HOME/.local/state}/claude-session/skill-runs"
   STAGE_DIR="$_SKILL_RUNS/tsk-impl-$(date -u +%Y%m%dT%H%M%S)-$$"
   mkdir -p "$STAGE_DIR"
   # Write the helper's .issue field to $STAGE_DIR/issue.md with the Write tool.
   ```

   Read `$STAGE_DIR/issue.md` into the session before assessment. If a
   consolidated plan is needed later, write it to `$STAGE_DIR/plan.md`.

4. Assess completeness in prose.

   Classify the issue body:

   - Well-specified: concrete requirements, relevant code references, explicit
     steps, and/or acceptance criteria. Copy it to `plan.md` and proceed.
   - Thin, vague, or incomplete: short, unreferenced, or missing actionable
     steps. Ask whether to complement the spec, implement anyway, or abort.

   If the user chooses to complement the spec, ask focused questions, merge the
   answers with the original issue body into `plan.md`, display the consolidated
   plan, and wait for explicit approval before editing files.

5. Capture a pre-change repository snapshot.

   ```bash
   cog tsk-snapshot --json
   ```

   Run this once, before editing any file, to record a read-only baseline of
   staged, unstaged, untracked, and recent-log state. If the helper fails, stop
   and report its error rather than implementing without a baseline. The
   snapshot is read-only and never mutates git state.

6. Implement directly in this session.

   Treat `plan.md` as the full implementation prompt. Follow repository
   instructions for every touched file. Pause for material tradeoffs or
   ambiguous requirements.

7. Report completion.

   Include the tsk id, a one-sentence summary of the requested work, files
   changed with intent, tests or manual checks run, and acceptance criteria the
   user should verify or close.

## Guardrails

- If the user answers `abort`, stop immediately.
- If the issue references files that do not exist, ask whether scope shifted
  before proceeding.
- If implementation requires live Claude skill changes, follow the repository's
  staging-and-install rule rather than writing live files directly.
- Keep completeness and implementation judgment in prose; keep deterministic
  issue fetching in `cog`.
