# Skills and resources

Runtime skills coordinate judgment around deterministic cog operations. [ADR-0006](../decisions/ADR-0006-runtime-skill-trees-and-taxonomy.md), [ADR-0007](../decisions/ADR-0007-skill-and-cli-responsibility-boundary.md), [ADR-0008](../decisions/ADR-0008-self-contained-resource-homes.md), [ADR-0017](../decisions/ADR-0017-skill-authoring-and-lint.md), and [ADR-0021](../decisions/ADR-0021-lean-deploy-payloads.md) own the durable choices.

## Components and boundaries

Native skill trees live under `skills/claude/` and `skills/codex/`. Shared runtime prose lives under `skill-refs/`; deploy payloads live under `skill-refs/templates/`; CLI-owned structured registries live under `data/`.

Skills own sequencing, evidence interpretation, and judgment. Commands and shared functions own deterministic parsing, validation, repeated shell mechanics, and filesystem state transitions.

The shared plan-review fold protocol therefore lives as load-bearing prose in `skill-refs/plan-quality/plan-review-fold.md`: authoring a replacement plan is judgment. Manifest comparison and hashing live in CLI code because they are deterministic. Marker requirements live in `data/skill-class/contracts.yaml` because class policy is structured data consumed by lint.

## Current constraints

Skill prefixes describe roles, native twins share a base name, consumers are producer-blind, machine identifiers are stage-agnostic, and scratch artifacts use cog run directories. `cog skill-lint` enforces the governed contract.

`data/` is YAML, split one file per top-level table, and resolves through `cog::fn::data_root` so an install reads from `$XDG_DATA_HOME/cog/data`. Append-only streams such as `data/research-shelf/index.jsonl` are the documented exception.

## Unresolved

- New skill classes require both a structural contract and a demonstrated recurring need.
