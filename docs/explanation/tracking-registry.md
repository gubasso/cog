# Tracking registry mechanics

This page owns the registry of perishable repository facts: what `data/maintenance-tracking.yaml` records, what each field means, and how `cog tracking-scan` decides an entry is overdue.

## Registry fields

`data/maintenance-tracking.yaml` is the registry of perishable facts. `cog tracking-scan` reports an entry as overdue when `last_checked` plus `cadence_days` is in the past; it performs date arithmetic only and does not check that any path exists. The runbook is [maintenance tracking](../guides/maintenance-tracking.md).

| Field            | Meaning                                                                       |
| ---------------- | ----------------------------------------------------------------------------- |
| `schema_version` | Registry format version, at the top level rather than per entry.              |
| `id`             | Stable entry key. Required and non-empty.                                     |
| `path`           | The tracked artifact, repo-relative. Required and non-empty.                  |
| `last_checked`   | ISO date of the last revalidation. Bumped only when the fact was re-verified. |
| `cadence_days`   | Maximum age in days before the entry is overdue.                              |
| `owner`          | The policy or subsystem that consumes the fact.                               |
| `why`            | Why the fact perishes, so a reader can judge urgency.                         |
| `revalidate_how` | The procedure and the authoritative source to re-check against.               |
| `references`     | Downstream artifacts that must be updated with the tracked one.               |

An entry is admitted when its truth depends on a source outside the repository: vendor pricing, model or tool rosters, external API shapes, benchmark figures, dependency lifecycle dates. Durable rationale is not tracked; a decision is superseded, not expired.

Because `cog tracking-scan` never resolves paths, a rename can leave a dangling entry that scans clean. Sweep for that explicitly after any documentation move:

```bash
python3 - <<'PY'
import pathlib, sys, yaml
reg = yaml.safe_load(pathlib.Path("data/maintenance-tracking.yaml").read_text())
bad = [t for e in reg["entries"] for t in [e["path"], *e.get("references", [])]
       if not pathlib.Path(t).exists()]
print("\n".join(f"dangling registry target: {t}" for t in bad))
sys.exit(1 if bad else 0)
PY
```
