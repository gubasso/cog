# ADR-0061: Skills obtain scratch space via cog rundir, never the project tree

## Context and Problem Statement

`skills/claude/bootstrap/SKILL.md` referenced an undefined `<run>` placeholder for its brief and
intermediate files but never bound it to a run directory. At runtime the model improvised
`RUN="$(pwd)/.bootstrap-run"` and wrote scratch into the target project's working tree, polluting the
repo and then hitting a write error. The canonical idiom — `RUN_DIR="$(cog rundir <prefix> | sed -n
's/^RUN_DIR=//p')"`, resolving under `$XDG_STATE_HOME/cog/runs` through `cog::fn::rundir_base`
([`lib/functions/fn_rundir.sh`](../../lib/functions/fn_rundir.sh)) — is already used by `gc`,
`jira-ticket-creator`, `runner-all`, and ~10 other skills, but the convention was never written down or
enforced, so a skill could ship without it and drift into writing scratch in-repo. Nothing distinguished
**scratch/intermediate artifacts** (which must stay out of the project) from **deliverables** (which
belong in the project).

## Considered Options

- Fix `bootstrap` only and rely on review to catch the pattern in future skills.
- Document the convention in the skill contract and teach it in `cog-skill-creator`, but no enforcement.
- Document it, teach it, **and** enforce it with a `cog skill-lint` rule — matching how every other
  non-negotiable in this repo is enforced (producer-blindness, input-fidelity, plan-mode-gate).

## Decision Outcome

Chosen option: **document + teach + enforce.** A skill that needs scratch or intermediate space obtains
a run directory via `cog rundir <prefix>` and writes every scratch/intermediate artifact under it;
scratch never lands in the project tree or the current working directory. Deliverables — the files a
skill exists to produce in the user's project (`.editorconfig`, `flake.nix`, a rendered plan) — are
explicitly out of scope and go to their real destination. The convention is:

- recorded as a skill-contract section ("Run directory (scratch artifact convention)") and a
  non-negotiable in `CLAUDE.md`/`AGENTS.md`;
- taught by `cog-skill-creator` — the authoring interview asks whether the skill needs scratch and
  requires wiring it through `cog rundir`;
- enforced by the `scratch-in-project` rule in `cog skill-lint`, which fails a skill that assigns a
  run/scratch/temp/work directory from `$(pwd)`, `${PWD}`, or a `./`-relative path, honoring an inline
  `<!-- cog-skill-lint: allow-scratch-in-project <reason> -->` suppression.

`bootstrap` is repaired to bind `$RUN_DIR` from `cog rundir bootstrap`.

## Consequences

- Good: scratch pollution of user projects is prevented mechanically; the runtime improvisation that
  produced `.bootstrap-run/` can no longer ship from a skill file.
- Good: one greppable idiom across all skills; run directories are uniformly locatable under
  `$XDG_STATE_HOME/cog/runs` and share the existing `cog rundir` lifecycle.
- Bad: a skill that genuinely must write a working file into the project (rare) records an explicit
  suppression; the lint signal is deliberately narrow, so a novel scratch-in-repo shape it does not
  match is caught by review rather than lint.

## Status

Implemented. `cog bootstrap-audit` supplies the deterministic domain matrix `bootstrap` now audits;
`bootstrap` binds `$RUN_DIR` via `cog rundir`; the `scratch-in-project` rule lives in
`lib/commands/cmd_skill_lint.sh`; `cog-skill-creator` carries the authoring step and guardrail.
