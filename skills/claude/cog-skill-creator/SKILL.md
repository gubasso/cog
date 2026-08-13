---
name: cog-skill-creator
description: >
  Delegates deterministic name validation, collision checks, scaffold path computation, draft
  validation, and skill linting to the cog CLI while preserving authoring interview and skill design
  judgment in prose. Drafts skills that already satisfy the full skill contract: prefix taxonomy,
  model/effort tier, plan-mode gate, context-brief gate, input-fidelity, producer-blindness,
  stage-agnostic identifiers, lean-positive prose, twin naming, and the per-class skill-class
  contract. Use when the user says "cog-skill-creator", "create a skill", "new skill", "author a
  skill", or "scaffold a skill".
---

<!-- trigger-tests: "cog-skill-creator", "create a skill", "author a skill" -->

# Cog Skill Creator

Create or update skills for the shipped payload trees. The default target is project scope:

```text
skills/claude/<name>/SKILL.md
skills/codex/<name>/SKILL.md
```

Use `--personal` only when the user explicitly asks for a personal skill. Keep Claude and Codex skill bodies runtime-native; Codex frontmatter supports only `name` and `description`.

## Reference Resolution

The authoring references ship with `cog` and resolve through `cog skill-refs path <rel>`; resolve each at point of use. Read `$(cog skill-refs path skill-authoring/skill-script-extraction.md)` before drafting, and `$(cog skill-refs path skill-authoring/skill-class-contracts.md)` for the per-class contract. The `cog` surface is the authoritative, machine-checkable contract — query it rather than relying on any external doc:

- `cog skill-class list|show --class <c>` — the per-class required/forbidden markers, tier basis, and input/output obligations.
- `cog power-grade skill-tier --skill <name>` / `cog power-grade tier --name <tier>` — the expected model/effort tier and the registry escape hatch.
- `cog skill-refs path orchestration/plan-mode-gate.md` / `orchestration/context-brief-gate.md` — the canonical gate directives that orchestrators point to.
- `cog skill-class check --skill <path>` and `cog skill-lint <path>` — the draft gates.

## Inputs

`$ARGUMENTS` may contain:

- first positional token: `<skill-name>`;
- `--project`: target the `skills/<runtime>/<name>/` payload tree; this is the default;
- `--personal`: target `$HOME/.local/share/cog/skills/<runtime>/<name>/` through cog-owned staging;
- `--runtime claude|codex`: choose the runtime;
- `--codex-parity`: also draft a separate Codex skill when the user wants parity.

If no name is present, ask for it before proceeding. If a name is present but no purpose is clear, ask for purpose before running scaffold mechanics.

## Prefix taxonomy and skill class

A governed-intent skill's name must carry the prefix that matches what it does:

- `plan-*` emits implementation plans;
- `review-*` reviews code against the codebase plus plan, or reviews plans before implementation;
- `review-plan-*` is the `review-*` sub-namespace for plan-before-implementation review;
- `executor-*` executes one plan/prompt at a time;
- `runner-*` orchestrates executors over a queue;
- `bootstrap-*` scaffolds or reconciles one project domain, delegating deterministic detection and copying to cog (a template-shipping worker also runs the domain-worker routine for each domain it owns).

Classify the new skill's behavior during the interview and choose a name whose prefix matches. A skill that is none of these (an authoring or utility skill) takes a descriptive non-taxonomy name and is an ungoverned `other` class. For a governed class, read its full membership contract and scaffold against its exact prerequisites:

```bash
cog skill-class show --class <plan|review|review-plan|executor|runner|bootstrap> --json
```

The contract states the required markers, the forbidden markers, the expected tier, and the producer/consumer obligations for that class. `cog skill-lint`'s `skill-class-contract` rule fails a draft that misses any prerequisite or carries any prohibition.

## Twin naming

Native twin skills share one base name across `skills/claude/` and `skills/codex/`; platform-token suffixes (`-codex`) are reserved for delegation launchers that run the other platform under the hood. When drafting Codex parity, give the Codex twin the same base name.

## Cog Contract

`cog` must be installed and on `PATH`. Validate name, scope prerequisites, and collisions:

```bash
cog cog-skill-creator-validate --name "$NAME" --scope "$SCOPE" --json
```

Use `--project-root`, `--home`, or `--run-dir` only when overriding the default current directory, `$HOME`, or `$RUN_DIR`.

Compute scaffold paths after deciding runtime and companions:

```bash
cog cog-skill-creator-scaffold --name "$NAME" --scope "$SCOPE" --runtime "$RUNTIME" --json
```

For project scope, the scaffold destination is `<project-root>/skills/<runtime>/<name>`; for personal scope, the stage directory is `<run-dir>/staging/skills/<runtime>/<name>`. `cog-skill-creator-scaffold` computes paths only — it never creates directories, writes files, copies files, or installs anything.

Before presenting a draft, run all deterministic gates:

```bash
cog cog-skill-creator-validate --draft "$DRAFT_FILE" --json
cog skill-class check --skill "$DRAFT_FILE" --json
cog skill-lint "$DRAFT_FILE"
```

Fix every reported issue before presenting the draft.

## Workflow

1. Parse `$ARGUMENTS` for name, scope, runtime, and Codex parity. Ask only for missing required information. Do not infer purpose from a name alone.

2. Run `cog-skill-creator-validate`. If it fails, stop with the helper's reason and the actionable fix. Do not mangle an invalid name and continue.

3. Read the authoring references via `cog skill-refs path`. Classify the skill's behavior into a class (or `other`), then read its contract with `cog skill-class show --class <c> --json`.

4. Interview for intent. Cover purpose, triggers, argument shape, side effects, preflight state, expected outputs, scratch/intermediate-artifact needs, and trigger tests.

5. Fix the name's taxonomy prefix to match the class. If the user's chosen name conflicts with what the skill does, propose a compliant name before drafting.

6. Run the deterministic-extraction interview:
   - identify every deterministic routine the skill would need;
   - reuse an existing `cog` subcommand or `cog::fn::*` helper when one exists;
   - when no helper exists, plan the new `cog` command before embedding any shell;
   - when the skill needs scratch or intermediate space, bind a run directory with `RUN_DIR="$(cog rundir <prefix> | sed -n 's/^RUN_DIR=//p')"` and write every scratch/intermediate artifact under `$RUN_DIR`; scratch never lands in the project tree or CWD, and deliverables go to their real destination;
   - keep only sequencing, judgment, escalation, and runtime orchestration in the skill body.

7. For orchestration skills, run the orchestration interview:
   - choose Skill-inline when same-context chaining is enough;
   - choose Agent-delegate only at true isolation boundaries;
   - include env-preflight requirements when foreground execution matters.

8. Apply the class contract's markers and gates:
   - `executor-*`/`runner-*` carry a Phase 0 plan-mode gate pointer (see Plan-mode gate).
   - A brief-building delegator at a fresh-context boundary carries the input-fidelity marker and a context-brief gate pointer to `$(cog skill-refs path orchestration/context-brief-gate.md)`.
   - A `plan-*` emitter carries the plan-emitter marker.
   - A consumer is producer-blind: it names only its structural input contract, never the producer.
   - Artifact/field/flag names are stage-agnostic (role, not stage number).

9. Run the DRY/SoT check. Do not duplicate command logic already present in `lib/commands/` or shared mechanics already present in `lib/functions/`.

10. Set `model:`/`effort:` to the class's expected tier (`cog power-grade skill-tier --skill <name>`). Default to no override for exploration/design skills so they ride the session default; pin the procedural tier (`model: opus` + `effort: low`) only for thin orchestration over deterministic mechanics; never select Sonnet.

11. Draft frontmatter and body together. Include only frontmatter fields justified by the interview and allowed by the runtime contract. Use a folded `description` when the trigger text is long. Keep prose lean, objective, and positively framed.

12. Decide whether companions are needed. Prefer a single `SKILL.md`; propose a `references/` split when the body would exceed roughly 300 lines. Do not create unreferenced companions.

13. Run `cog-skill-creator-scaffold` with the final companion list. Use its JSON as the mechanical plan for writing after approval.

14. Validate, class-check, and lint the draft:

    ```bash
    cog cog-skill-creator-validate --draft "$DRAFT_FILE" --json
    cog skill-class check --skill "$DRAFT_FILE" --json
    cog skill-lint "$DRAFT_FILE"
    ```

15. Present the proposed tree in fenced blocks, one block per file, labeled with the relative path. Wait for `approve`, `approve with changes: <notes>`, or `abort`. Never auto-apply.

16. After approval, write files according to the scaffold JSON. Personal scope writes to stage paths first, then installs from `$STAGE` to `$DEST`. Project scope writes directly to `skills/<runtime>/<name>/`.

17. On success, report written paths and the invocation hint.

## Plan-mode gate

The plan-mode gate lives on the executor-_/runner-_ orchestrator layer, not on plan/review workers. If the new skill is a Claude `executor-*` or `runner-*` skill, give it a short Phase 0 pointer that keeps the STOP imperative in the body and defers the full protocol to the shared source of truth:

```text
**Phase 0 — Plan-mode gate.** If Claude Code plan mode is active, STOP before any other work and
follow `$(cog skill-refs path orchestration/plan-mode-gate.md)`.
```

The caller gates once at entry (plan mode is read-only and blocks writes), then delegates to gate-free workers. The canonical directive — do not call `ExitPlanMode`, do not silently continue — lives in `skill-refs/orchestration/plan-mode-gate.md`; the skill body carries only the pointer. Codex skills are exempt.

## Rules

- Never overwrite an existing skill. Name collision means abort.
- Never invent frontmatter fields absent from the runtime contract.
- Never give a governed-intent skill a name whose prefix does not match its behavior.
- Never ship a Claude executor-*/runner- skill without its Phase 0 plan-mode gate pointer.
- Never select Sonnet; use `model: opus` + `effort: low`, or no override.
- Never skip the approval gate.
- Never treat `cog-skill-creator-scaffold` output as permission to write. It is path computation only.
- Never embed deterministic shell when a `cog` subcommand or shared helper should own it.
- Never write scratch or intermediate artifacts into the project tree or CWD; obtain a run directory with `cog rundir <prefix>` and keep scratch under it.

## Guardrails

- If the user's intent is vague, stop and ask instead of guessing.
- If the skill needs scratch space, wire it through `cog rundir <prefix>` and keep every scratch/intermediate artifact under the returned directory.
- If Codex parity is requested, draft a separate `skills/codex/<name>/SKILL.md` with Codex-only frontmatter and the same base name.
- If a references split is needed, propose it before drafting companion files.
- If validation, class-check, or linting fails twice in a row, stop and ask how to proceed.
- If staged install fails, do not retry with `sudo` or force flags. Report the error and stop.
