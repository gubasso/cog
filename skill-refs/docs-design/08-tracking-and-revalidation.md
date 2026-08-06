# 08 — Tracking and Revalidation

Documentation often holds perishable facts: benchmarks, prices, model and tool rosters, external API shapes, security advisories. A tracking file keeps those facts honest by recording what must be re-checked, how often, and how.

## Tracking files

A tracking file is a machine-readable registry with one entry per perishable artifact. It does not replace the artifact; it records enough metadata for a human or agent to know when the artifact needs attention and how to revalidate it without rediscovering the process. Each entry records:

- `path`: the artifact being tracked.
- `last_checked`: the date the artifact was last revalidated.
- `cadence`: how often the artifact should be re-verified.
- `why`: why the fact perishes.
- `revalidate`: the procedure or authoritative source to use.
- `dependents`: downstream files or workflows that rely on the artifact.

Keep the registry descriptive. It answers what is stale and how to check it; it does not become a second copy of the fact it tracks. The tracked artifact remains the source of truth, and if the two disagree, update one of them so there is still a single owner.

A temporary-workaround revert ledger is a tracking artifact of the same shape, recording the exact condition under which a workaround must be removed. That ledger lives with its case; see [09 — Known Issues](./09-known-issues.md).

## When to track

Track facts that drift from external reality: benchmark results, vendor pricing, model and tool availability, external API shapes, security advisories, dependency lifecycle dates, platform support matrices. These may be correct when written and wrong a month later without any local code change.

Do not track stable conceptual docs just because they are old. Durable rationale belongs in ADRs and conceptual background in explanation; a decision is superseded or rejected, it does not expire on a timer. Tracking is for facts whose truth depends on a source outside the document.

## Revalidation

Revalidation should be boring and explicit:

1. Scan the tracking file.
2. Pick overdue entries.
3. Re-research from authoritative sources.
4. Update the artifact and its own verified date.
5. Bump the entry's `last_checked`.

If the drift is uncertain, surface it. Do not silently overwrite a claim you could not re-verify — open a follow-up, leave a clear note, or ask for review when the source is ambiguous, unavailable, or contradicted.

The primary audience is coding agents sweeping a repo during normal work. Agents are good at deterministic scans and vulnerable to stale authoritative-looking docs, so a registry gives them a specific path to inspect instead of inferring freshness from filenames. The split that makes this work: overdue computation is deterministic tooling, and revalidation is judgment — fetch the current source, compare it, decide whether the claim changed, and report uncertainty. A tool can say a roster is due; a maintainer must decide what the new truth is.

## Minimal schema

An adopting project owns the exact field names. Start with the smallest schema that supports a scan, a revalidation pass, and downstream impact review.

```yaml
# docs/reference/<your>-tracking.yaml
tracked:
  - path: docs/reference/model-pricing.md
    last_checked: 2026-06-20
    cadence: 30d            # re-verify at least this often
    why: provider prices change without notice
    revalidate: re-fetch from the provider's official pricing page
    dependents:
      - docs/guides/cost-estimation.md
```
