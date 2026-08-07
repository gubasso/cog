# ADR-0025: Express step exclusion with needs rather than a sync marker

## Context and Problem Statement

The proposal marked a step that must not be parallelized with `sync:`, enforced through claim scope. Two shaped slices depended on that marker and no slice declared it: it appeared in no call-form key list and in no validator rule. Its exclusion scope was also undecided, between a boolean that serializes the whole run and a named lock that, under the no-TTL rule, is held forever by a crashed owner.

## Considered Options

- Declare a definition-only boolean with whole-run exclusion
- Declare a named lock with a lock table in run state
- Delete the marker and express exclusion with `needs:`

## Decision Outcome

Chosen option: `Delete the marker and express exclusion with needs:`. `needs:` is the only edge key and carries both order and exclusion: two steps that must not overlap get an edge between them. No new key, no run state, no lock table, and no exclusion scope to compute, because `next` already withholds a node until its edges are satisfied.

## Consequences

- Exclusion across a scope boundary is coarse. Two conflicting leaves inside different composites can only be separated by serializing the composites that contain them.
- A composite rewritten to touch shared state can break a caller who cannot see its interior. Workflow consistency is the author's responsibility, and a harder check waits for a real case rather than being built for a hypothetical one.
- An edge carrying no data reference is an ordering constraint, so deleting one changes behaviour while validation still passes.
- Q-003 dissolves rather than resolves, because with no marker there is no declaration site to fix and no exclusion scope to compute.

## Status

Accepted
