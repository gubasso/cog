# Documentation mechanics

This page owns only cog-specific documentation mechanics: how `cog docs-lint` works, how to read the migration ledger, and how the reviewed plan zone relates to machine-oriented implementation plans. The project-agnostic standard remains in `skill-refs/docs-design/`, and root `AGENTS.md` carries only routing and local exceptions.

## Components and boundaries

`cog docs-lint` scans shipped cog docs and the imported docs-design shelf for decorative emphasis, validates lean ADR shape and lifecycle, validates plan headings and milestone vocabulary, and resolves acceptance tests for active, done, or cut slices. Markdownlint owns fence-language and relative-link validation.

[Documentation migration](../reference/documentation-migration.md) is lookup history for the one-time reset, never current architecture. `docs/plan/` owns reviewed slice intent and status; `.implementation-plans/` and XDG plan vaults own generated execution queues.

## Tracking registry

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

## Reference-integrity checks

The one-time renumber moved every decision number, so two checks together prove no stale citation survives. Both are run from the repository root and both must produce no output.

Path-form citations must resolve to a file that exists:

```bash
rg -o --no-filename '(\.\./)*(docs/)?decisions/[0-9]{4}-[a-z0-9-]+\.md' \
  AGENTS.md CLAUDE.md data lib skills docs man completions test skill-refs \
  --glob '!docs/reference/documentation-migration.md' \
  --glob '!docs/explanation/documentation.md' \
  --glob '!skill-refs/templates/**' \
  --glob '!skills/claude/bootstrap-governance/SKILL.md' \
  --glob '!test/integration/cmd_governance_apply.bats' \
  --glob '!test/unit/cmd_docs_lint.bats' \
  | sed -E 's#^(\.\./)+##; s#^decisions/#docs/decisions/#' \
  | sort -u \
  | while IFS= read -r path; do
      [ -f "$path" ] || printf 'dangling ADR path: %s\n' "$path"
    done
```

Bare `ADR-NNNN` citations must name a number in cog's live domain, currently `0001`..`0022`:

```bash
rg -n --no-heading -o 'ADR-[0-9]{4}' \
  AGENTS.md CLAUDE.md data lib skills docs man completions test skill-refs \
  --glob '!docs/reference/documentation-migration.md' \
  --glob '!skill-refs/templates/**' \
  --glob '!skill-refs/languages/**' \
  --glob '!skill-refs/cli-design/**' \
  | awk -F'ADR-' '{n=substr($2,1,4)+0; if (n<1 || n>22) print "out-of-domain ADR reference: " $0}'
```

The exclusions are owners, independent namespaces, and constructed paths — not blind spots.

- [Documentation migration](../reference/documentation-migration.md) is the ledger and cites every old basename as historical inline code.
- This page names the excluded paths in order to document them.
- `skill-refs/templates/**` ships a deploy payload whose decision tree belongs to the consuming project, and the governance bootstrap skill names that same payload tree.
- `skill-refs/languages/**` and `skill-refs/cli-design/**` are project-agnostic specifications whose `ADR-NNNN` tokens are illustrative examples. Because those numbers sit inside cog's live range, a range check would pass a corruption there silently, so the exclusion is load-bearing rather than cosmetic.
- Two bats files build decision paths inside a temporary fixture tree rather than citing cog records: `test/integration/cmd_governance_apply.bats` asserts the governance deploy payload, and `test/unit/cmd_docs_lint.bats` builds `docs/decisions/0001-test-choice.md` under a scratch root. The rest of `test/**` stays inside both checks.

## Current constraints

[ADR-0001](../decisions/0001-adopt-documentation-architecture.md) records the architecture and one-time reset. Drafts remain in `.draft/` until promoted, and `.draft/safe-to-delete/` is only a manual-deletion hand-off buffer.

## Unresolved

- No known-issue directory exists until a real external-system case needs one.
