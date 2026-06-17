---
name: tsk-new
description: >
  Delegates deterministic tsk store, issue creation, and git snapshot mechanics
  to the cog CLI while preserving issue authoring judgment in prose. Use when
  the user says "tsk-new", "create an issue", "new task", "file a tsk issue", or
  "capture this as an issue".
model: haiku
---

# Tsk New

Create a new `tsk` issue from three inputs: current repository state, the
session context, and the user's orientation. The title and body are authored by
the agent; deterministic mechanics go through `cog`.

## Non-Negotiable Rules

- Require a user orientation. If `$ARGUMENTS` is empty, ask before proceeding.
- The issue body must be self-contained. Do not refer to "the conversation" or
  "as discussed".
- Do not invent code references, decisions, requirements, or constraints.
- Do not run direct `tsk new`; use `cog tsk-fetch-issue`.
- Do not pass `--ai` or open an editor.
- Do not run mutating git commands.

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

`config_exists` is always `true` on success. `doctor_repo` is `null` when
`tsk doctor` did not expose a resolved store path. `template_exists:false` is a
warning signal, not a hard failure.

`tsk-fetch-issue` emits, for fetch or create:

```json
{
  "mode": "create",
  "id": "tsk-123",
  "path": "/path/to/issue.md",
  "remote_url": "https://example.test/issue/123",
  "title": "Add helper wrapper",
  "issue": "raw tsk show output"
}
```

Unused optional fields are `null`. Create mode parses the issue id from line 1
of `tsk new` output, optional remote URL from line 2, resolves `tsk path`, then
verifies the issue with `tsk show`.

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

1. Validate the orientation.

   Treat `$ARGUMENTS` as the user's requested angle, focus, or goal. If it is
   empty or too vague to shape a useful issue, ask one focused question before
   doing any issue creation work.

2. Initialize or verify the shared tsk store.

   ```bash
   cog tsk-store-init --json
   ```

   If the helper fails, stop and report its error. If `template_exists` is
   `false`, surface that as a warning but continue unless the user asked for a
   template-dependent body.

3. Capture repository state.

   ```bash
   cog tsk-snapshot --json
   ```

   Use this as the repo-state input. Read relevant untracked files or changed
   files when their content matters to the requested issue. Do not catalog the
   whole repository.

4. Synthesize the issue in prose.

   Combine the snapshot, session context, and orientation. Extract only
   information actually present in those inputs:

   - Problem statement and motivation.
   - Decisions made and the reasoning behind them.
   - Code explored, with absolute paths and relevant signatures or excerpts.
   - Current state, including staged, unstaged, and untracked work.
   - Functional and non-functional requirements.
   - Rejected alternatives.
   - Resolved questions.
   - Unresolved items the implementor must know are still open.

5. Compose the title.

   Write one imperative descriptive sentence, roughly 8-15 words. Do not emit a
   slug; `tsk` derives that.

6. Compose the body.

   Use this structure, omitting empty sections:

   ```text
   ## Problem Statement & Motivation
   ## Current State Analysis
   ### Key Files
   ### Existing Patterns
   ## Requirements & Constraints
   ### Functional Requirements
   ### Non-Functional Constraints
   ### Architectural Constraints
   ## Detailed Implementation Plan
   ## Dependencies & Prerequisites
   ## Rejected Alternatives
   ## Edge Cases & Risks
   ## Testing & Verification Strategy
   ## Acceptance Criteria
   ```

   Steps must be in dependency order and independently verifiable. Fenced code
   blocks inside the body must include a language.

7. Write the body to a staging file.

   ```bash
   _SKILL_RUNS="${XDG_STATE_HOME:-$HOME/.local/state}/claude-session/skill-runs"
   STAGE_DIR="$_SKILL_RUNS/tsk-new-$(date -u +%Y%m%dT%H%M%S)-$$"
   mkdir -p "$STAGE_DIR"
   BODY_FILE="$STAGE_DIR/body.md"
   # Write the composed body to $BODY_FILE with the Write tool before invoking the helper.
   ```

   Pass the file to the helper; do not inline multiline markdown in a shell
   argument yourself.

8. Create and verify the issue.

   ```bash
   cog tsk-fetch-issue --title "$TITLE" --body-file "$BODY_FILE" --json
   ```

   If the helper fails, report the failure and stop. Do not retry with altered
   arguments unless the cause is understood and safe.

9. Report the result.

   Include the issue id, path when non-null, approximate body line count, and a
   concise summary of the plan. Do not display the full body unless asked.

## Guardrails

- If the inputs are too thin to produce a useful implementation issue, say so
  and ask the user to provide more context.
- If the helper reports a missing template, mention it but do not repair the
  store manually.
- If relevant code references are uncertain, re-read files before citing them.
- Keep authoring judgment in prose; keep deterministic mechanics in
  `cog`.
