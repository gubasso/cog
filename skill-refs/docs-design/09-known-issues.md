# 09 — Known Issues

Projects that test or integrate external systems they do not own accumulate a special kind of finding: a bug that lives in the system under test, not in this codebase. These are diagnostics and case studies, and they need a durable home, a status, and a lifecycle that lets a directory of evidence expand while the issue is hot and collapse to one lean summary when it is resolved. Without that home the knowledge lives in chat logs, and the next time the symptom recurs someone re-derives the whole investigation instead of grepping one id.

## Where it lives

```text
<project>/docs/reference/known-issues/
```

Reference, because the reader need is lookup. Do not create a top-level `<project>/docs/known-issues/`; that is the topic-sibling anti-pattern in [01 — Diataxis Zones](./01-diataxis-zones.md).

## One case = one directory

Each tracked issue is its own directory, keyed on an internal id — not the upstream bug number, because the finding usually predates any filed bug and one finding can map to several upstream bugs. Use a sequential, zero-padded id so it mirrors the ADR scheme and reads cleanly in code and commit messages. Date-keyed ids are a fine alternative when chronological sorting matters more than ADR symmetry; pick one and keep it.

```text
 open ─► investigating ─┬─► mitigated ─┬─► monitoring ─► resolved
                        └─► masked ────┘                    │
                                                            ▼
   expand while hot                            collapse when cold

   KI-0007-<slug>/                             resolved/
     README.md          index card               KI-0007-<slug>.md
     issue.yaml         metadata                   1 issue: the symptom
     investigation.md   lab notebook               2 root cause
     escalation.md      upstream report            3 resolution + proof
     mask.md            revert ledger              4 recurrence signal
     evidence/          raw artifacts
     notes/             source-grounded refs     raw trail stays in VCS history
```

Alongside the cases, `README.md` is the registry index and an optional `registry.yaml` makes it machine-readable; a `TEMPLATE/` directory holds the copy-to-start skeleton.

The statuses:

- `open` and `investigating` — reproduced and being root-caused; the test fails honestly.
- `mitigated` — a permanent, legitimate guard exists, such as a readiness gate or a precondition check. Not a workaround; it stays after the bug is fixed.
- `masked` — a temporary workaround is in the tree and MUST be revert-tracked. `mitigated` and `masked` can co-exist on one case.
- `monitoring` — the upstream fix is believed deployed; watching for recurrence.
- `resolved` — fix confirmed deployed and any mask reverted. Triggers the collapse.

## Expand while hot, collapse when cold

While the issue is live the directory grows, and that sprawl is correct — it is a working lab notebook. When the issue is resolved, collapse it into a single `resolved/KI-<NNNN>-<slug>.md` summary and delete the hot directory. The summary keeps four things: the externally observable symptom, the one-paragraph root cause, what fixed it with proof it is deployed, and the exact signal plus a one-line repro so a future reader recognizes recurrence and self-serves.

The raw trail is not duplicated; it stays in version-control history, and the summary records the path in a field such as `expanded_history`. This is the deliberate difference from ADRs, which are never deleted: a known-issue dossier is a working set whose durable value is the distilled lesson.

## Linking code to a case

Three mechanisms, kept separate so they never blur:

- Honest-fail — a test that must not hide the bug stays failing, with a `KI-<NNNN>` comment pointing at the case.
- Expected failure — when a marker is wanted, use the test runner's native mechanism with the id in the reason string, and prefer the strict form so the suite goes red the moment the external system is fixed, as with `xfail(reason="KI-<NNNN>: …", strict=True)`. That forces the case closed.
- Temporary mask — carry the id at the code site with a revert condition, and route to the ledger.

Whatever the language, every suppression carries a tracker id and a revert condition. A single grep of `KI-<NNNN>` then ties together the directory, the registry row, the marker, the mask comment, and the commit.

A mask never hides a defect silently. Its `mask.md` records what is masked, why, where, the revert trigger, and the revert checklist. The revert trigger is the exact condition — upstream fix confirmed deployed and stability proven — that ends the mask; a green run that still carries the mask does not prove the underlying fix. This is the same discipline as a tracking file for perishable facts; see [08 — Tracking and Revalidation](./08-tracking-and-revalidation.md).

## The registry index

`known-issues/README.md` is the one file a future debugger greps: a status-only table of id, status, severity, affected tests, external system, upstream reference, and whether a mask exists, plus a resolved table. Every other fact lives in the case directory. A machine-readable `registry.yaml` alongside it lets a CI or pre-commit check assert that every `KI-<NNNN>` referenced in the codebase resolves to a non-resolved row and that the registry agrees with the on-disk directories.

## Sources

- Test runner expected-failure and strict mode: <https://docs.pytest.org/en/stable/how-to/skipping.html>
- Known-failure expectation files with required bug ids: <https://chromium.googlesource.com/chromium/src/+/main/docs/testing/web_test_expectations.md>
- Postmortems as compact searchable learning artifacts: <https://sre.google/sre-book/postmortem-culture/> and <https://github.com/danluu/post-mortems>
