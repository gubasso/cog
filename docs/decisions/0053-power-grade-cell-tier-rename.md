# ADR-0053: Power Grade cell/tier vocabulary rename

Date: 2026-06-30

## Status

Accepted

## Context

The Power Grade matrix (ADR-0032, relocated to `data/power-grade/matrix` by ADR-0052) stored two tables whose names were weak and collided on the word "profile":

- `profiles.yaml` (key `profiles`) — the flat registry of graded `(model, effort)` rows, each carrying a Power Grade.
- `named-profiles.yaml` (key `named_profiles`) — the five-rung named tier ladder (ADR-0041), each rung pairing one Claude row and one Codex row.

"profile" was overloaded. It named a graded row in some identifiers (`profiles`, `cell_json`'s `profile` output field, `profile_count`) and a named tier in others (`named_profiles`, the `cog power-grade profile` subcommand, `profile_json`). "profiles" also collided with "named_profiles", and neither name said what a row actually is.

## Decision

Split the overloaded "profile" vocabulary into two domain nouns and rename the two tables:

- A graded `(model, effort)` row is a **cell**. The registry table is `model_cells`, stored in `data/power-grade/matrix/model-cells.yaml`. `cell` was already the code's noun (`cell_json`, `def cell`).
- A named rung that pairs one Claude cell and one Codex cell is a **tier**. The ladder table is `model_tiers`, stored in `data/power-grade/matrix/model-tiers.yaml`.

The rename cascades through every derived identifier:

- Tier rows pair `claude_cell`/`codex_cell` (was `claude_profile`/`codex_profile`).
- Validation keys become `required_cell_keys`, `informational_cell_is_fatal`, and `unsupported_efforts_as_cells`.
- CLI output fields become `model_cell_count`/`model_tier_count`, and the `cell`/`cells` payloads on `cell`/`classify`/`compound`.
- Error kinds and codes become `missing_required_cell_keys`, `duplicate_cell_<field>`, `cell_grade_out_of_scale`, `unknown_cell`, `cell_not_executable`, and `model_tier_unknown_reference`.
- The public subcommand `cog power-grade profile --name <tier>` becomes `cog power-grade tier --name <name>`, with the result schema id `cog.power-grade.profile.v1` becoming `cog.power-grade.tier.v1`.

## Consequences

`cog::fn::data::load_dir` merges a dataset directory by top-level key (ADR-0052), so the file rename and the in-file key rename move together; no runtime consumer reads these tables by filename. The only filename-literal dependency is the install-roundtrip manifest assertion, repointed to `model-cells.yaml`.

This supersedes the naming surface of ADR-0041 (the `named_profiles` ladder) and ADR-0052 (which referenced `named_profiles[].source_refs`). Both remain accepted records of their original decisions; this ADR records the changed names rather than rewriting that history.

The `cell`/`tier` split makes filenames and the CLI/output vocabulary self-documenting and removes the `profiles`/`named_profiles` collision. It is a naming change only — the Power Grade model, the matrix schema shape, and the compound-pass math are unchanged.
