---
name: skill-builder
description: >
  Delegates deterministic name validation, collision checks, scaffold path
  computation, draft validation, and skill linting to the cog CLI while preserving
  authoring interview and skill design judgment in prose. Use when the user says
  "skill-builder", "create a skill", "new skill", "author a skill", or
  "scaffold a skill".
model: opus
effort: low
---

<!-- trigger-tests: "skill-builder", "create a skill", "author a skill" -->

# Skill Builder

Create or update skills for this repository's shipped payload trees. The default target is project
scope:

```text
skills/claude/<name>/SKILL.md
skills/codex/<name>/SKILL.md
```

Use `--personal` only when the user explicitly asks for a personal skill. Keep Claude and Codex
skill bodies runtime-native; Codex frontmatter supports only `name` and `description`.

## Reference Resolution

Shared references live in `$DOCS_NOTES_REPO`. Resolve at skill start:

```bash
DOCS_NOTES="${DOCS_NOTES_REPO:-}"
```

If `$DOCS_NOTES_REPO` is unset, warn and continue without external skill-authoring references. When
it is set, read the relevant skill-authoring references before drafting. Treat
`docs/reference/skill-contract.md` in this repo as the authoritative local contract.

## Inputs

`$ARGUMENTS` may contain:

- first positional token: `<skill-name>`;
- `--project`: target this repo's `skills/<runtime>/<name>/` payload tree; this is the default;
- `--personal`: target `$HOME/.local/share/cog/skills/<runtime>/<name>/` through cog-owned staging;
- `--runtime claude|codex`: choose the runtime;
- `--codex-parity`: also draft a separate Codex skill when the user wants parity.

If no name is present, ask for it before proceeding. If a name is present but no purpose is clear,
ask for purpose before running scaffold mechanics.

## Cog Contract

`cog` must be installed and on `PATH`. Validate name, scope prerequisites, and collisions:

```bash
cog skill-builder-validate --name "$NAME" --scope "$SCOPE" --json
```

Use `--project-root`, `--home`, or `--run-dir` only when overriding the default current directory,
`$HOME`, or `$RUN_DIR`.

Compute scaffold paths after deciding runtime and companions:

```bash
cog skill-builder-scaffold --name "$NAME" --scope "$SCOPE" --runtime "$RUNTIME" --json
```

For project scope, the scaffold destination is:

```text
<project-root>/skills/<runtime>/<name>
```

For personal scope, the stage directory is:

```text
<run-dir>/staging/skills/<runtime>/<name>
```

`skill-builder-scaffold` computes paths only. It never creates directories, writes files, copies
files, or installs anything.

Before presenting a draft, run both deterministic gates:

```bash
cog skill-builder-validate --draft "$DRAFT_FILE" --json
cog skill-lint "$DRAFT_FILE"
```

Fix every reported issue before presenting the draft.

## Workflow

1. Parse `$ARGUMENTS` for name, scope, runtime, and Codex parity. Ask only for missing required
   information. Do not infer purpose from a name alone.

2. Run `skill-builder-validate`. If it fails, stop with the helper's reason and the actionable fix.
   Do not mangle an invalid name and continue.

3. Read `docs/reference/skill-contract.md`. Load external authoring references when available.

4. Interview for intent. Cover purpose, triggers, argument shape, side effects, preflight state,
   expected outputs, and trigger tests.

5. Run the deterministic-extraction interview:
   - identify every deterministic routine the skill would need;
   - reuse an existing `cog` subcommand or `cog::fn::*` helper when one exists;
   - when no helper exists, plan the new `cog` command before embedding any shell;
   - keep only sequencing, judgment, escalation, and runtime orchestration in the skill body.

6. Run the DRY/SoT check. Do not duplicate command logic already present in `lib/commands/` or
   shared mechanics already present in `lib/functions/`.

7. Ask opt-in metadata questions only when the answers signal the need: `allowed-tools`, `context`,
   `model`, `effort`, `paths`, or runtime-specific frontmatter from the contract.

8. Draft frontmatter and body together. Include only frontmatter fields justified by the interview
   and allowed by the runtime contract. Use a folded `description` when the trigger text is long.

9. Decide whether companions are needed. Prefer a single `SKILL.md`; propose a `references/` split
   when the body would exceed roughly 300 lines or when progressive disclosure makes the skill
   clearer. Do not create unreferenced companions.

10. Run `skill-builder-scaffold` with the final companion list. Use its JSON as the mechanical plan
    for writing after approval.

11. Validate and lint the draft:

    ```bash
    cog skill-builder-validate --draft "$DRAFT_FILE" --json
    cog skill-lint "$DRAFT_FILE"
    ```

12. Present the proposed tree in fenced blocks, one block per file, labeled with the relative path.
    Wait for `approve`, `approve with changes: <notes>`, or `abort`. Never auto-apply.

13. After approval, write files according to the scaffold JSON. Personal scope writes to stage paths
    first, then installs from `$STAGE` to `$DEST`. Project scope writes directly to
    `skills/<runtime>/<name>/`.

14. On success, report written paths and the invocation hint.

## Rules

- Never overwrite an existing skill. Name collision means abort.
- Never invent frontmatter fields absent from `docs/reference/skill-contract.md`.
- Never skip the approval gate.
- Never silently fall back when `$RUN_DIR` is unset for personal scope.
- Never ask opt-in metadata questions by default.
- Never treat `skill-builder-scaffold` output as permission to write. It is path computation only.
- Never embed deterministic shell when a `cog` subcommand or shared helper should own it.

## Guardrails

- If the user's intent is vague, stop and ask instead of guessing.
- If Codex parity is requested, draft a separate `skills/codex/<name>/SKILL.md` with Codex-only
  frontmatter.
- If a references split is needed, propose it before drafting companion files.
- If validation or linting fails twice in a row, stop and ask how to proceed.
- If staged install fails, do not retry with `sudo` or force flags. Report the error and stop.
