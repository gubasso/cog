---
name: refactor-migration-plan
description: >
  Generate an AI-friendly, multi-phase refactor or rewrite plan inside the current target project
  from a separate source project. Deterministic setup, source scan, and drift fingerprint mechanics
  delegate to cog; migration design remains prose.
argument-hint: "[--review] <source-project-path> [--target-lang=<lang>]"
---

# `refactor-migration-plan`

This skill preserves the live skill contract: it writes only the plan directory, never source code,
and treats the source project as read-only. It may reference parity-test scaffolds in the plan but
does not edit target source files.

## Helper Delegation

Run setup through:

```bash
cog refactor-setup [--review] [--source "$SOURCE_ARG"] [--target-root "$TARGET_ROOT"] [--plan-dir "$PLAN_DIR"] [--target-lang "$TARGET_LANG"] [--dry-run] --json
```

This resolves source root, target root, plan dir, collision state, and the canonical guideline path
using the live resolution order.

Run source probes through:

```bash
cog refactor-scan-source --source-root "$SOURCE_ROOT" --run-dir "$RUN_DIR" --json
```

This writes `$RUN_DIR/source-scan/` artifacts and `$RUN_DIR/scan-fingerprint.txt`.

For review mode, recompute drift through:

```bash
cog refactor-scan-drift --scan "$RUN_DIR/source-scan" --expected "$RECORDED_SCAN_FINGERPRINT" --json
```

`refactor-scan-drift` must stay byte-compatible with the recorded
`MANIFEST.yaml: source.scan-fingerprint`. The fingerprint is the SHA-256 of concatenated scan-file
contents in `LC_ALL=C` filename-sorted order.

## Judgment That Stays In Prose

The migration design, interview questions, semantic-gap analysis, phase breakdown, refusal-list
instantiation, ADR decisions, and `<TBD: ...>` open questions remain agent judgment. Helper outputs
are evidence; they are not a substitute for design.

## Review Mode

Review mode re-runs source scanning and drift fingerprinting, compares the current fingerprint and
source metadata to the manifest, then reports `DRIFT:` findings before assessing target
implementation quality against the plan and refusal list.
