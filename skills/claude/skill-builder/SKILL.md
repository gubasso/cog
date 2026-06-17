---
name: skill-builder
description: >
  Delegates deterministic name validation, collision checks, scaffold path
  computation, and install path planning to the cog CLI while preserving
  authoring interview and skill design judgment in prose. Use when the user
  says "skill-builder", "create a skill", "new skill", "author a skill", or
  "scaffold a skill".
model: opus
effort: low
---

# Skill Builder

Create a new Claude Code Agent Skill from an intent description. Produce a single-file `SKILL.md` by
default and add companion files under `references/` only when the skill genuinely needs them. Match
the cog-skill house style: YAML-folded descriptions with a trigger trailer, phased or stepped bodies,
`## Rules` and `## Guardrails` sections, imperative tone, no emojis, and code fences with language
tags.

## Reference Resolution

Shared references live in `$DOCS_NOTES_REPO`. Resolve at skill start:

```bash
DOCS_NOTES="${DOCS_NOTES_REPO:-}"
```

If `$DOCS_NOTES_REPO` is unset, warn and continue without skill-authoring references. When it is
set, read the skill-authoring references before drafting:

- `$DOCS_NOTES_REPO/tech/tools/claude-code/skill-authoring/REFS/spec.md`
- `$DOCS_NOTES_REPO/tech/tools/claude-code/skill-authoring/REFS/style.md`

The reference files remain prose context. Do not move their interpretation into the helper.

## Inputs

`$ARGUMENTS` may contain:

- first positional token: `<skill-name>`;
- `--project`: target `./.claude/skills/<name>/` in the current repo;
- `--personal`: target `$HOME/.local/share/cog/skills/claude/<name>/` through the cog-owned personal skill
  staging discipline. This is the default.

If no name is present, ask for it before proceeding. If a name is present but no purpose is clear,
ask for purpose before running scaffold mechanics.

## Cog Contract

`cog` must be installed and on `PATH`; a bare call fails legibly if it is
missing. Validate name, scope prerequisites, and collisions:

```bash
cog skill-builder-validate --name "$NAME" --scope "$SCOPE" --json
```

Use `--project-root`, `--home`, or `--run-dir` only when the caller needs to override the default
current directory, `$HOME`, or `$RUN_DIR`.

The validation helper emits:

```json
{
  "ok": true,
  "name": "demo-skill",
  "scope": "personal",
  "project_root": "/repo",
  "home": "/home/user",
  "run_dir": "/tmp/run",
  "valid_name": true,
  "invalid_characters": [],
  "collisions": [],
  "reason": null
}
```

If `ok` is not `true`, stop. For invalid names, report the offending characters and the allowed
pattern: `^[a-z0-9-]{1,64}$`. For collisions, report each path and ask the user for a different
name. For personal scope without a run dir, report that personal-scope skills must stage under
`$RUN_DIR/staging/dotclaude/...`.

Compute scaffold paths:

```bash
cog skill-builder-scaffold --name "$NAME" --scope "$SCOPE" --json
```

Pass `--companion <relative-path>` once for each planned companion file after the references split is
known.

The scaffold helper emits:

```json
{
  "ok": true,
  "name": "demo-skill",
  "scope": "personal",
  "write_mode": "stage-then-install",
  "stage_dir": "/tmp/run/staging/dotclaude/skills/demo-skill",
  "dest_dir": "/home/user/.local/share/cog/skills/claude/demo-skill",
  "files": [
    {
      "relative_path": "SKILL.md",
      "stage_path": "/tmp/run/staging/dotclaude/skills/demo-skill/SKILL.md",
      "dest_path": "/home/user/.local/share/cog/skills/claude/demo-skill/SKILL.md"
    }
  ],
  "install_commands": ["install -d \"$DEST\"", "cp -a \"$STAGE/.\" \"$DEST/\""],
  "performs_install": false,
  "reason": null
}
```

`skill-builder-scaffold` computes paths only. It never creates directories, writes files, copies
files, or installs anything. The skill remains responsible for presenting the draft, receiving user
approval, writing staged files, and running the approved install in the later live workflow.

Before presenting a draft, run the deterministic draft checks against the candidate `SKILL.md`:

```bash
cog skill-builder-validate --draft "$DRAFT_FILE" --json
```

Draft mode emits:

```json
{
  "ok": true,
  "mode": "draft",
  "file": "/tmp/run/SKILL.md",
  "line_count": 212,
  "under_500": true,
  "name": "demo-skill",
  "valid_name": true,
  "has_trigger_tests": true,
  "emojis": [],
  "untagged_fences": [],
  "reason": null
}
```

If `ok` is not `true`, the command exits non-zero. `emojis` and `untagged_fences` list the offending
line numbers. Fix each before presenting the draft.

## Workflow

1. Parse `$ARGUMENTS` for name and scope. Ask only for missing required information. Do not infer a
   purpose from a name alone.

2. Run `skill-builder-validate`. If it fails, stop with the helper's reason and the actionable fix.
   Do not mangle an invalid name and continue.

3. Load the authoring references when available. Use the official spec for frontmatter fields and
   the style reference for this repository's skill house style.

4. Interview for intent. Ask only questions not already answered by `$ARGUMENTS`, visible context,
   or an obvious inference. Cover purpose, triggers, argument shape, side effects, preflight state,
   body shape, and trigger tests. Confirm inferences before committing to them.

5. Ask opt-in metadata questions only when the answers signal the need: `allowed-tools`, `context`,
   `model`, `effort`, or `paths`.

6. Draft frontmatter and body together. Include only frontmatter fields justified by the interview
   and present in the spec. Use a YAML-folded description with a trigger trailer. Match the chosen
   lightweight, mid, or heavy template from the style reference.

7. Decide whether companions are needed. Prefer a single `SKILL.md`; propose a `references/` split
   when the body would exceed roughly 300 lines or when progressive disclosure makes the skill
   clearer. Do not create unreferenced companions.

8. Run `skill-builder-scaffold` with the final companion list. Use its paths as the mechanical plan
   for writing and installation after approval.

9. Validate the draft before presenting. Write the candidate `SKILL.md` to a file and run the
   deterministic checks:

   ```bash
   cog skill-builder-validate --draft "$DRAFT_FILE" --json
   ```

   The helper exits non-zero when any mechanical check fails and reports offending line numbers. It
   covers: name matches `^[a-z0-9-]{1,64}$`, `SKILL.md` under 500 lines, trigger-tests comment
   present, no emojis, and every fenced code block has a language tag. Fix every reported issue,
   then confirm the judgment-bound items the helper cannot check:
   - description and `when_to_use` combined stay within the spec limit;
   - trigger trailer contains at least two concrete phrases;
   - `argument-hint`, if present, matches the body;
   - every frontmatter field exists in the spec;
   - each companion is linked from `SKILL.md`.

10. Present the proposed tree in fenced blocks, one block per file, labeled with the relative path.
    Wait for `approve`, `approve with changes: <notes>`, or `abort`. Never auto-apply.

11. After approval, write files according to the scaffold JSON. Personal scope writes to the stage
    paths first, then installs from `$STAGE` to `$DEST`. Project scope writes directly to
    `./.claude/skills/<name>/`.

12. On success, report installed or written paths and the invocation hint.

## Rules

- Never overwrite an existing skill. Name collision means abort.
- Never invent frontmatter fields absent from the spec.
- Never skip the approval gate.
- Never silently fall back when `$RUN_DIR` is unset for personal scope.
- Never ask opt-in metadata questions by default.
- Never treat `skill-builder-scaffold` output as permission to write. It is path computation only.

## Guardrails

- If the user's intent is vague, stop and ask instead of guessing.
- If a references split is needed, propose it before drafting the companion files.
- If validation fails twice in a row, stop and ask how to proceed.
- If staged install fails, do not retry with `sudo` or force flags. Report the error and stop.
