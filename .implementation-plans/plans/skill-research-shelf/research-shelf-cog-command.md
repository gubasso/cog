# Round 1: cog research-shelf command family + schema

> Plan: skill-research-shelf | Round: 1 of 3 | Complexity: M | Generated: 2026-06-19 |
> Repo: /workspaces/cog | Executor: prex (EF 1.5)

## Context

Build the deterministic store first so the research rounds have somewhere to write. All shelf
mechanics belong in `cog` (ADR-0008); the actual research is judgment done in later rounds.

## Previous Rounds

None (first round).

## Scope of This Round

**IN scope:**

- New command module `lib/commands/cmd_research_shelf.sh` (handler `cog::cmd::research_shelf`, line-2
  `: 'desc: ...'` sentinel) + `cog::fn::research::*` helpers in `lib/functions/`, owning:
  - `init` — create the shelf dir (`docs/reference/research-shelf/`) + index file.
  - `record` — append one dated, sourced finding with a stable id (fields: id, topic-tags, sources[]
    with title/url/publisher/access-date, stable-summary, revalidate-after, consuming-skills[]).
  - `list` / `get` — read findings back for reuse across calls.
  - `validate` — assert the shelf is well-formed and every entry is dated/sourced.
- Define the shelf index + entry format mirroring `model-effort-policy-and-rename`'s dated-evidence
  docs. Machine-facing output + file-first (ADR-0009).
- Register surfaces: `docs/reference/cli-commands.md`, `man/cog.1.scd`, completions, root help
  snapshots; add `test/integration/cmd_research_shelf.bats`.

**OUT of scope:**

- Performing any web research (Rounds 2–3).
- The tracking-registry entry (Round 3; `cog tracking-scan` is owned by `repo-update-tracking`).

## Deterministic vs Probabilistic

- Deterministic (cog): the entire command family + schema + validation — this whole round.
- Judgment: command/subcommand naming consistent with repo conventions; index schema field set.

## Validation

- `cog research-shelf` bats green; `cog research-shelf init` then `record`/`list`/`validate`
  round-trips. Completion drift, man summary, help snapshots in sync. `just lint` + `just test` green.

## Execution Discipline

One round per `/prex` session; flip `done` and stop. Commit with `/gc -a` afterward.
