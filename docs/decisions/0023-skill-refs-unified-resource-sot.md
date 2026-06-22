# ADR-0023: skill-refs is the unified SoT for skill-external resources

## Context and Problem Statement

[ADR-0017](0017-reference-self-containment.md) made `skill-refs/` the in-repo home for skill-source
*reference documents*, while deployable template payloads (the pre-commit configs) lived in a
separate top-level `templates/` tree. Adding an `editorconfig` template domain surfaced the question
of where new skill-external resources belong; two parallel shipped-resource roots invite drift and
asymmetry, and a skill must be able to rely on cog owning every artifact it needs.

## Considered Options

- Keep `templates/` and `skill-refs/` as two separate shipped-resource roots.
- Put new template domains under `skill-refs/` but leave pre-commit in `templates/`.
- Make `skill-refs/` the single SoT for all skill-external resources, with a `templates/` subdir for
  deploy payloads.

## Decision Outcome

Chosen option: **`skill-refs/` is the single SoT for all skill-external resources** — read-only
references stay in `skill-refs/<area>/`; deploy-payload templates live in
`skill-refs/templates/<domain>/` (e.g. `pre-commit`, `editorconfig`). Both ship in the one
`skill-refs` tree, install to `$XDG_DATA_HOME/cog/skill-refs`, and resolve via
`cog::fn::skill_refs_root`; `cog::fn::template::root <domain>` builds the per-domain template root.
This extends ADR-0017's scope (references remain self-contained; the resource root is now unified).

## Consequences

- Good: one owned, self-contained resource tree; symmetric domains; one install/resolve path.
- Good: new template domains drop in under `skill-refs/templates/` with no new deploy wiring.
- Bad: the read-vs-deploy distinction now lives in subdir convention, not separate top-level trees.

## Status

Implemented. Enacted by `lib/functions/fn_template.sh` (`cog::fn::template::root`), the relocated
`skill-refs/templates/{pre-commit,editorconfig}/` trees, and `install.sh`/`uninstall.sh` shipping and
pruning templates inside the `skill-refs` tree. Extends [ADR-0017](0017-reference-self-containment.md).
