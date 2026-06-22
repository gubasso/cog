---
name: cog-skill-creator
description: >
  Delegates deterministic name validation, collision checks, scaffold path
  computation, draft validation, and skill linting to the cog CLI while preserving
  authoring interview and skill design judgment in prose. Drafts skills that already
  satisfy this repo's contract: prefix taxonomy, model/effort policy, and the
  plan-mode gate. Use when the user says "cog-skill-creator", "create a skill",
  "new skill", "author a skill", or "scaffold a skill".
---

<!-- trigger-tests: "cog-skill-creator", "create a skill", "author a skill" -->

# Cog Skill Creator

Create or update skills for this repository's shipped payload trees. The default target is project
scope:

```text
skills/claude/<name>/SKILL.md
skills/codex/<name>/SKILL.md
```

Use `--personal` only when the user explicitly asks for a personal skill. Keep Claude and Codex
skill bodies runtime-native; Codex frontmatter supports only `name` and `description`.

## Reference Resolution

Shared references ship with `cog` and resolve through `cog skill-refs path <rel>`. Read
`$(cog skill-refs path skill-authoring/skill-script-extraction.md)` before drafting. Treat
`docs/reference/skill-contract.md` in this repo as the authoritative local contract, and apply its
governing decisions while authoring:

- prefix taxonomy (`docs/decisions/0016-skill-prefix-taxonomy.md`);
- model/effort policy (`docs/reference/model-effort-policy.md`, `docs/decisions/0013-model-effort-policy.md`);
- plan-mode gate (`docs/decisions/0015-plan-skills-not-in-plan-mode.md`).

When the skill will spawn Codex, delegate, queue work, or orchestrate nested execution, also read
`docs/reference/orchestration-contract.md`.

## Inputs

`$ARGUMENTS` may contain:

- first positional token: `<skill-name>`;
- `--project`: target this repo's `skills/<runtime>/<name>/` payload tree; this is the default;
- `--personal`: target `$HOME/.local/share/cog/skills/<runtime>/<name>/` through cog-owned staging;
- `--runtime claude|codex`: choose the runtime;
- `--codex-parity`: also draft a separate Codex skill when the user wants parity.

If no name is present, ask for it before proceeding. If a name is present but no purpose is clear,
ask for purpose before running scaffold mechanics.

## Prefix taxonomy

A governed-intent skill's name must carry the prefix that matches what it does
(`docs/decisions/0016-skill-prefix-taxonomy.md`):

- `plan-*` emits implementation plans;
- `review-*` reviews code against the codebase plus plan, or reviews plans before implementation;
- `review-plan-*` is the `review-*` sub-namespace for plan-before-implementation review;
- `executor-*` executes one plan/prompt at a time;
- `runner-*` orchestrates executors over a queue.

Classify the new skill's behavior during the interview and choose a name whose prefix matches. A
skill that is none of these (an authoring or utility skill) takes a descriptive non-taxonomy name.
`cog skill-lint` fails a governed-intent skill whose prefix does not match its behavior.

## Cog Contract

`cog` must be installed and on `PATH`. Validate name, scope prerequisites, and collisions:

```bash
cog cog-skill-creator-validate --name "$NAME" --scope "$SCOPE" --json
```

Use `--project-root`, `--home`, or `--run-dir` only when overriding the default current directory,
`$HOME`, or `$RUN_DIR`.

Compute scaffold paths after deciding runtime and companions:

```bash
cog cog-skill-creator-scaffold --name "$NAME" --scope "$SCOPE" --runtime "$RUNTIME" --json
```

For project scope, the scaffold destination is:

```text
<project-root>/skills/<runtime>/<name>
```

For personal scope, the stage directory is:

```text
<run-dir>/staging/skills/<runtime>/<name>
```

`cog-skill-creator-scaffold` computes paths only. It never creates directories, writes files, copies
files, or installs anything.

Before presenting a draft, run both deterministic gates:

```bash
cog cog-skill-creator-validate --draft "$DRAFT_FILE" --json
cog skill-lint "$DRAFT_FILE"
```

Fix every reported issue before presenting the draft.

## Workflow

1. Parse `$ARGUMENTS` for name, scope, runtime, and Codex parity. Ask only for missing required
   information. Do not infer purpose from a name alone.

2. Run `cog-skill-creator-validate`. If it fails, stop with the helper's reason and the actionable
   fix. Do not mangle an invalid name and continue.

3. Read `docs/reference/skill-contract.md`. Load external authoring references when available.

4. Interview for intent. Cover purpose, triggers, argument shape, side effects, preflight state,
   expected outputs, and trigger tests.

5. Classify behavior and fix the name's taxonomy prefix (see Prefix taxonomy). If the user's chosen
   name conflicts with what the skill does, propose a compliant name before drafting.

6. Run the deterministic-extraction interview:
   - identify every deterministic routine the skill would need;
   - reuse an existing `cog` subcommand or `cog::fn::*` helper when one exists;
   - when no helper exists, plan the new `cog` command before embedding any shell;
   - keep only sequencing, judgment, escalation, and runtime orchestration in the skill body.

7. For orchestration skills, run the orchestration interview:
   - choose Skill-inline when same-context chaining is enough;
   - choose Agent-delegate only at true isolation boundaries;
   - include env-preflight requirements when foreground execution matters;
   - never reintroduce the removed foreground hook.

8. Decide whether the new skill is a plan emitter (see Plan-mode gate). If its primary output is a
   plan document, plan the Phase 0 gate and the two markers now.

9. Run the DRY/SoT check. Do not duplicate command logic already present in `lib/commands/` or shared
   mechanics already present in `lib/functions/`.

10. Set `model:`/`effort:` per the model/effort policy. Default to no override for exploration and
    design skills so they ride the session default; pin the procedural tier (`model: opus` +
    `effort: low`) only for thin orchestration over deterministic mechanics; never select Sonnet.
    Ask other opt-in metadata questions (`allowed-tools`, `context`, `paths`, runtime-specific
    frontmatter) only when the answers signal the need.

11. Draft frontmatter and body together. Include only frontmatter fields justified by the interview
    and allowed by the runtime contract. Use a folded `description` when the trigger text is long.

12. Decide whether companions are needed. Prefer a single `SKILL.md`; propose a `references/` split
    when the body would exceed roughly 300 lines or when progressive disclosure makes the skill
    clearer. Do not create unreferenced companions.

13. Run `cog-skill-creator-scaffold` with the final companion list. Use its JSON as the mechanical
    plan for writing after approval.

14. Validate and lint the draft:

    ```bash
    cog cog-skill-creator-validate --draft "$DRAFT_FILE" --json
    cog skill-lint "$DRAFT_FILE"
    ```

15. Present the proposed tree in fenced blocks, one block per file, labeled with the relative path.
    Wait for `approve`, `approve with changes: <notes>`, or `abort`. Never auto-apply.

16. After approval, write files according to the scaffold JSON. Personal scope writes to stage paths
    first, then installs from `$STAGE` to `$DEST`. Project scope writes directly to
    `skills/<runtime>/<name>/`.

17. On success, report written paths and the invocation hint.

## Plan-mode gate

If the new skill's primary output is a plan document (writes under `.implementation-plans/`,
rewritten plans, or queue mutations), it must not run in Claude plan mode, which is read-only and
blocks those writes (`docs/decisions/0015-plan-skills-not-in-plan-mode.md`). Such a skill carries two
HTML-comment markers — a plan-emitter marker (`cog-skill: plan-emitter`) near the frontmatter and a
plan-mode-gate marker (`cog-plan-mode-gate`) on a Phase 0 stanza that runs before any other work and
tells the user to exit plan mode and re-invoke. The gate must not call `ExitPlanMode` and must not
silently continue. Copy the exact marker syntax and canonical gate wording from
`docs/reference/skill-contract.md` ("Plan-mode gate").

`cog skill-lint` fails a Claude plan-emitter that lacks the gate. Codex skills are exempt.

## Rules

- Never overwrite an existing skill. Name collision means abort.
- Never invent frontmatter fields absent from `docs/reference/skill-contract.md`.
- Never give a governed-intent skill a name whose prefix does not match its behavior.
- Never ship a plan-emitting skill without the plan-mode gate markers and Phase 0 stanza.
- Never select Sonnet; use `model: opus` + `effort: low`, or no override.
- Never skip the approval gate.
- Never silently fall back when `$RUN_DIR` is unset for personal scope.
- Never ask opt-in metadata questions by default.
- Never treat `cog-skill-creator-scaffold` output as permission to write. It is path computation only.
- Never embed deterministic shell when a `cog` subcommand or shared helper should own it.
- Never reintroduce the removed foreground hook.

## Guardrails

- If the user's intent is vague, stop and ask instead of guessing.
- If Codex parity is requested, draft a separate `skills/codex/<name>/SKILL.md` with Codex-only
  frontmatter.
- If a references split is needed, propose it before drafting companion files.
- If validation or linting fails twice in a row, stop and ask how to proceed.
- If staged install fails, do not retry with `sudo` or force flags. Report the error and stop.
