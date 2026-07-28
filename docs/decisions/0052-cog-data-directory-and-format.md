# ADR-0052: Cog Data Directory and Format

Date: 2026-06-29

## Status

Accepted

## Context

`cog` has structured reference data that is consumed by CLI commands and shared `cog::fn::*` helpers. Those datasets previously lived under `docs/reference/` as monolithic TOML, YAML, or JSONL files. The installer does not ship `docs/`, so installed commands that resolved those paths from the application root could miss their data.

`skill-refs/` already has a separate purpose: resources that runtime skills load, plus deploy payload templates. CLI-owned policy and registry data needs its own install-aware home without blurring that boundary.

## Decision

Top-level `data/` is the source of truth for structured reference data consumed by the `cog` CLI. The installer ships it to `$XDG_DATA_HOME/cog/data`, and runtime code resolves it through `cog::fn::data_root` / `cog::fn::data::path`, with the same XDG-first then source-checkout fallback shape used by `cog::fn::skill_refs_root`.

CLI datasets use YAML. A dataset directory is split one file per top-level table, array-of-tables, or map-of-subtables. Loose scalar metadata and small configuration objects may collect in `meta.yaml` when they are part of the dataset header rather than a separate independently maintained table. Append-only record streams remain JSONL; the research shelf stays at `data/research-shelf/index.jsonl`.

`cog::fn::data::load_dir` accepts either a dataset directory or a single YAML file. Directory loading parses sorted `*.yaml`/`*.yml` files, requires each non-empty document to be an object, rejects duplicate top-level keys, and deep-merges disjoint top-level keys into the same JSON shape consumers received from the previous single-file parsers.

The merge preserves byte-identical JSON for all code-read fields; descriptive-only fields (e.g. `named_profiles[].source_refs`) were repointed to the new `data/` paths rather than preserved verbatim, to avoid dangling references to the relocated files.

The installer refreshes read-only data subtrees during install. The append-only research shelf index is copied only when absent so records appended in installed mode survive upgrades.

## Consequences

The Power Grade matrix source of truth named in ADR-0032 is relocated from `docs/reference/power-grade-matrix.toml` to `data/power-grade/matrix`. This is a storage and format relocation, not a reversal of the Power Grade model decision.

`skill-refs/` remains the source of truth for skill-loaded references and templates. `data/` is for CLI-consumed structured reference data. External documentation remains optional runtime context, not a load-bearing data dependency.

`yq` is a core runtime dependency for data loading. `taplo` is no longer required for the relocated runtime datasets.
