# Maintenance Tracking

`data/maintenance-tracking.yaml` is the registry of repository artifacts that contain perishable facts. It records which files need periodic revalidation, why they can drift, how to refresh them, and what downstream files depend on them.

## Registry Format

The registry has a top-level `schema_version` and an `entries` list. Each entry uses these fields:

- `id`: stable machine-readable identifier.
- `path`: tracked artifact path, relative to the repository root.
- `last_checked`: date the artifact was last researched or revalidated.
- `cadence_days`: number of days before the entry should be considered stale.
- `owner`: maintenance area responsible for the entry.
- `why`: reason the artifact is perishable.
- `revalidate_how`: concrete refresh procedure.
- `references`: downstream files that depend on the tracked artifact.

## Cadence

An entry is overdue when `last_checked + cadence_days` is earlier than today. The future `cog tracking-scan` command reports that calculation from this registry.

## Revalidation Workflow

1. Run `cog tracking-scan`.
2. Pick an overdue entry.
3. Follow the entry's `revalidate_how` instructions.
4. Update the tracked artifact, including its `Data collected` metadata where present.
5. Update any dependent files listed in `references`.
6. Bump the registry entry's `last_checked` date to the revalidation date.

## Adding an Artifact

Add an entry when a repository artifact depends on facts that can drift, such as model rosters, pricing, benchmarks, external API behavior, release channels, or security guidance. Prefer authoritative sources in `revalidate_how`, and list the downstream policy or data files in `references`.
