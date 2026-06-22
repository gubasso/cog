# Plan Templates

Every template here uses `{{PLACEHOLDER}}` markers the skill must substitute before writing.
Standard placeholders:

| Placeholder               | Source                                                       |
| ------------------------- | ------------------------------------------------------------ |
| `{{PLAN_ID}}`             | `refactor-<UTC-YYYYMMDD-HHMMSS>`                             |
| `{{TIMESTAMP}}`           | UTC ISO 8601 at plan creation                                |
| `{{SOURCE_ROOT}}`         | Absolute path to source project                              |
| `{{SOURCE_LANG}}`         | Detected source language (e.g. `bash`, `python`)             |
| `{{SOURCE_VERSION}}`      | Source language version, if discoverable                     |
| `{{SOURCE_GIT_HEAD}}`     | `git rev-parse HEAD` in source (may be empty)                |
| `{{SOURCE_LOC}}`          | Approx total source LOC (from scan)                          |
| `{{TARGET_ROOT}}`         | Absolute path to target project (cwd)                        |
| `{{TARGET_LANG}}`         | User-confirmed target language                               |
| `{{TARGET_LANG_VERSION}}` | User-confirmed target language version                       |
| `{{TARGET_LANG_CANON}}`   | URL of target idiom canon (Effective Go, PEP 8, …)           |
| `{{GUIDELINE_PATH}}`      | Resolved canonical guideline path                            |
| `{{SYSTEM_TYPE}}`         | CLI / library / HTTP service / gRPC / worker / mixed         |
| `{{CONTRACT_SURFACES}}`   | Comma-separated list of declared contract surfaces           |
| `{{PRESERVED_LIST}}`      | Bulletized preserved items                                   |
| `{{NOT_PRESERVED_LIST}}`  | Bulletized intentionally-not-preserved items + ADR#          |
| `{{QUIRKS}}`              | User-declared undocumented behavior list                     |
| `{{SCAN_FINGERPRINT}}`    | SHA-256 over source-scan file contents, LC_ALL=C name-sorted |

When a value is unknown, write the literal `<TBD: short description>` and append the question to the
`Open Questions` list in `00-OVERVIEW.md`.

---

## TEMPLATE — `AGENTS.md` (Spec Kit interop)

This file is the universal entry point for any AI agent. It conforms to the GitHub Spec Kit
convention so downstream tools can consume it.

```markdown
# AGENTS.md — Refactor/Migration Plan {{PLAN_ID}}

> Spec Kit-compatible universal entry point for AI coding agents. See:
> <https://github.com/github/spec-kit>

## Project context

- **Target project**: `{{TARGET_ROOT}}` (this repository)
- **Source project**: `{{SOURCE_ROOT}}`
- **Refactor type**: `{{SOURCE_LANG}}` → `{{TARGET_LANG}}` (full rewrite)
- **System type**: `{{SYSTEM_TYPE}}`
- **Plan created**: `{{TIMESTAMP}}`
- **Plan ID**: `{{PLAN_ID}}`

## Entry point for agents

1. Read `00-EXECUTION-GUIDE.md` — explains how to find your next task and how to mark progress.
2. Read `MANIFEST.yaml` — machine-readable plan state.
3. Read `00-OVERVIEW.md` — human-friendly overview, open questions, non-negotiables digest.

## Non-negotiables (binding rules)

This is a **full refactor**, NOT a transliteration.

- Preserve the external contract (CLI surface, exit codes, API, observable behavior, on-disk/wire
  formats, semver promises).
- Re-derive the internal implementation from the contract using `{{TARGET_LANG}}`'s idioms.
- See `04-ANTI-TRANSLITERATION.md` for the 16-smell refusal list. The agent must refuse to emit code
  matching any of those smells.
- No scope creep. New features ship in a separate change.

## Canonical guideline

`{{GUIDELINE_PATH}}` — when present, treat as authoritative over this file. Section references in
plan files (`§0`, `§3`, `§6`) refer to it.

## Phase model

| Phase | File                              | Status field in MANIFEST.yaml |
| ----- | --------------------------------- | ----------------------------- |
| A     | `01-CONTRACT.md`                  | `phases.A.status`             |
| B     | `02-CHARACTERIZATION.md`          | `phases.B.status`             |
| C     | `03-DESIGN.md`                    | `phases.C.status`             |
| D     | `05-IMPLEMENTATION-GUARDRAILS.md` | `phases.D.status`             |
| E     | `06-VERIFICATION-PLAN.md`         | `phases.E.status`             |
| F     | `07-CUTOVER.md`                   | `phases.F.status`             |

Phases are gated. Do not advance past phase X until `phases.X.status` is `complete` and all
checkboxes in the corresponding file are checked.

## Task ID convention

`T-AA-NN` where `AA` is the phase letter (`A`–`F`) and `NN` is a zero-padded sequence inside the
phase. Example: `T-A-01`, `T-C-12`, `T-E-03`.

## How to advance

After completing a task:

1. Edit the file containing the task. Change `- [ ] T-AA-NN — …` to
   `- [x] T-AA-NN — … _(completed: <UTC ISO 8601>, by: <agent-name>)_`.
2. Append a line to `MANIFEST.yaml: implementation-log` describing what changed and any files
   touched.
3. When all tasks in a phase are `[x]`, set `phases.<X>.status: complete` in `MANIFEST.yaml` and
   stamp `phases.<X>.completed-at`.

## Coding canon for `{{TARGET_LANG}}`

Consult: `{{TARGET_LANG_CANON}}`

## Style for AI-friendly outputs

- Cite plan files by relative path + section header.
- When unsure of a contract behavior, do not guess — open a TODO under
  `00-OVERVIEW.md › Open Questions` and stop.
```

---

## TEMPLATE — `MANIFEST.yaml`

```yaml
# Machine-readable plan index. Update fields under `phases.*.status`,
# `phases.*.completed-at`, and `implementation-log` as you execute.

version: "1.0"
plan-id: "{{PLAN_ID}}"
created-at: "{{TIMESTAMP}}"
guideline-resolved-from: "{{GUIDELINE_PATH}}"

source:
  root: "{{SOURCE_ROOT}}"
  language: "{{SOURCE_LANG}}"
  version: "{{SOURCE_VERSION}}"
  git-head: "{{SOURCE_GIT_HEAD}}"
  approximate-loc: {{SOURCE_LOC}}
  scan-fingerprint: "{{SCAN_FINGERPRINT}}"

target:
  root: "{{TARGET_ROOT}}"
  language: "{{TARGET_LANG}}"
  version: "{{TARGET_LANG_VERSION}}"
  idiom-canon: "{{TARGET_LANG_CANON}}"

system-type: "{{SYSTEM_TYPE}}"
contract-surfaces:
{{CONTRACT_SURFACES_YAML_LIST}}

parity-boundary:
  preserved:
{{PRESERVED_YAML_LIST}}
  not-preserved:
{{NOT_PRESERVED_YAML_LIST}}
  documented-in: "01-CONTRACT.md"

phases:
  A:
    title: "Contract Extraction"
    file: "01-CONTRACT.md"
    status: "pending"          # pending | in-progress | complete | blocked
    started-at: null
    completed-at: null
    gate: "All <cli-contract>, <exit-codes>, <config-schema>, and <parity-boundary> blocks finalized; contract/ artifacts written."
  B:
    title: "Freeze Behavior"
    file: "02-CHARACTERIZATION.md"
    status: "pending"
    started-at: null
    completed-at: null
    gate: "parity-tests/ created and PASSING against the source today."
    blocked-by: ["A"]
  C:
    title: "Idiomatic Design (from contract, NOT source code)"
    file: "03-DESIGN.md"
    status: "pending"
    started-at: null
    completed-at: null
    gate: "design/ artifacts written; every choice justified by contract requirement + target-language canon; ADRs written."
    blocked-by: ["A", "B"]
    source-code-access: "FORBIDDEN during this phase (see 00-EXECUTION-GUIDE.md § 4)."
  D:
    title: "Implementation Under Anti-Transliteration Guardrails"
    file: "05-IMPLEMENTATION-GUARDRAILS.md"
    status: "pending"
    started-at: null
    completed-at: null
    gate: "All features implemented; each feature ships with parity tests; 04-ANTI-TRANSLITERATION.md review passes clean."
    blocked-by: ["C"]
  E:
    title: "Differential / Property / Fuzz / Shadow Validation"
    file: "06-VERIFICATION-PLAN.md"
    status: "pending"
    started-at: null
    completed-at: null
    gate: "All parity tests pass; differential tests clean; fuzz campaign clean; performance within envelope."
    fuzz-budget: "24h"            # T-E-04 fuzz-campaign CPU-time budget (default 24 CPU-hours)
    shadow-duration: "<TBD>"      # T-E-05 shadow-traffic window (services only)
    blocked-by: ["D"]
  F:
    title: "Parallel-Run, Canary, Cutover, Decommission"
    file: "07-CUTOVER.md"
    status: "pending"
    started-at: null
    completed-at: null
    gate: "Parallel-run period complete; canary clean; rollback tested; source decommissioned."
    divergence-threshold: "<TBD>"      # T-F-02 max acceptable parallel-run divergence rate
    confidence-period-days: "<TBD>"    # T-F-07 solo-monitoring window before decommission
    blocked-by: ["E"]

recommended-tools:
  # Implementation agent must consult target-language idiomatic
  # equivalents. The names below are intentionally non-prescriptive —
  # confirm in 03-DESIGN.md dependency choices.
  cli-parity-tests: ["bats-core", "trycmd", "cram", "ApprovalTests", "insta"]
  property-tests:   ["Hypothesis", "proptest", "QuickCheck", "fast-check", "jqwik"]
  fuzz:             ["AFL++", "libFuzzer", "cargo-fuzz", "jazzer", "OSS-Fuzz"]
  differential:     ["Trail of Bits DIFFER"]
  http-replay:      ["VCR", "WireMock", "mitmproxy", "GoReplay"]
  contract-diff:    ["Pact", "openapi-diff", "cargo-semver-checks"]
  adr:              ["MADR (https://adr.github.io/madr/)"]

context-references:
  guideline-path: "{{GUIDELINE_PATH}}"
  guideline-sections-load-first:
    - "§0 Non-Negotiables"
    - "§3 Mandatory Phase Model"
    - "§5 Idiomatic Target-Language Canon"
    - "§6 Refusal List"
    - "§8 AI-Agent Prompting Tactics"
    - "§11 LLM Code Translation Findings"
  case-studies-worth-emulating:
    - "§10 Discord Go→Rust"
    - "§10 Astral ruff/uv (Python→Rust tooling)"
    - "§10 esbuild (JS→Go bundler)"

implementation-agent-instructions: |
  1. Read AGENTS.md first.
  2. Read 00-EXECUTION-GUIDE.md.
  3. Find the next unchecked task: lowest phase letter whose status is
     not `complete`, lowest T-AA-NN in that phase.
  4. Execute exactly that task. Do not advance phases without permission.
  5. Tick the checkbox in the phase file:
     `- [x] T-AA-NN — <desc> _(completed: <UTC ISO 8601>, by: <agent-name>)_`
  6. Append to implementation-log (below) what changed and which files
     you touched.
  7. When every checkbox in a phase is ticked, set the phase status to
     `complete` and stamp `completed-at`.

implementation-log: []
  # Each entry shape:
  # - task: "T-A-03"
  #   completed-at: "<UTC ISO 8601>"
  #   by: "<agent name>"
  #   files-touched: ["contract/cli-surface.md", "contract/help-text/root.golden"]
  #   note: "captured top-level --help"
```

---

## TEMPLATE — `00-EXECUTION-GUIDE.md`

````markdown
# 00 — Execution Guide

> Read this file ONCE at the start of every implementation session.

You are an AI coding agent. This plan was generated by the `refactor-migration-plan` skill on
{{TIMESTAMP}}. Your job is to execute the plan, one task at a time, advancing through phases A→F.

## Step 1 — Read three files

1. `AGENTS.md` — universal entry point (non-negotiables, phase map).
2. `MANIFEST.yaml` — machine-readable plan state.
3. `00-OVERVIEW.md` — human overview, open questions, ground rules.

## Step 2 — Find your next task

Use this algorithm:

1. Open `MANIFEST.yaml`. Find the lowest-letter phase whose `status` is not `complete`.
2. Open that phase's file (e.g. `phases.A.file`).
3. In that file, find the first `- [ ] T-AA-NN — …` line. That is your task.
4. If every checkbox in the file is `[x]` but the phase status is not `complete`, set the phase
   status to `complete`, stamp `completed-at` with the current UTC ISO 8601 timestamp, then go to
   step 1.

If the next phase is **blocked** by an earlier phase (see `phases.X.blocked-by`), refuse to start it
and report the blocker to the user.

### Special rule for Phase C

`phases.C.source-code-access: FORBIDDEN`. While working on Phase C (Idiomatic Design), do **NOT**
read the source project's code. You may read:

- `{{TARGET_ROOT}}/refactor-plan/01-CONTRACT.md`
- `{{TARGET_ROOT}}/refactor-plan/02-CHARACTERIZATION.md`
- The target-language idiom canon `{{TARGET_LANG_CANON}}`
- Any official Spec Kit / docs URLs cited in the plan

This separation is the single highest-leverage anti-transliteration guardrail. Re-derive the design
from the contract.

## Step 3 — Execute exactly one task

Do only what the task description says. Do not bundle adjacent tasks. If a task spawns subtasks, add
them as `- [ ] T-AA-NN.M — …` _below_ the parent and execute them in order.

## Step 4 — Mark the task done

Edit the phase file in place. Change:

```
- [ ] T-AA-NN — <description>
```

to:

```
- [x] T-AA-NN — <description> _(completed: <UTC-ISO-8601>, by: <agent-name>)_
```

Use the actual UTC timestamp at the moment you finish (not when you started). `<agent-name>` is your
model+harness identifier, e.g. `claude-code/opus-4.7` or `codex-cli/gpt-5.4`.

## Step 5 — Append to `MANIFEST.yaml: implementation-log`

```yaml
implementation-log:
  - task: "T-AA-NN"
    completed-at: "<UTC-ISO-8601>"
    by: "<agent-name>"
    files-touched:
      - "path/relative/to/repo-root.ext"
    note: "<one short sentence about what changed>"
```

## Step 6 — Stop or continue

- If the user invoked you with `one-task` (single-step mode), stop here and report status.
- If the user invoked you with `phase`, continue executing tasks in the current phase until all are
  checked, then stop at the phase boundary.
- If the user invoked you with `full`, advance through phases. Pause at every phase boundary and ask
  for explicit user permission before starting the next phase.

## Step 7 — When you hit a blocker

If you cannot complete a task because of missing information, an ambiguous contract item, or an open
question:

1. Do NOT guess.
2. Open `00-OVERVIEW.md` and add the question under `## Open
   Questions` with the task ID and your
   specific need.
3. Set the task's status in `MANIFEST.yaml` to `blocked` (add a `blocked` field to
   `implementation-log` entry).
4. Report to the user and stop.

## Step 8 — Refusal list (always active)

While working in any phase, refuse to emit code that matches any pattern in
`04-ANTI-TRANSLITERATION.md`. If you find yourself about to write a counterpart of source-language
code, stop and re-derive from the contract.

## Step 9 — On confusion, read the canonical guideline

`{{GUIDELINE_PATH}}` is authoritative when this plan and your training disagree.
````

---

## TEMPLATE — `00-OVERVIEW.md`

```markdown
# Refactor / Migration Plan — Overview

> Plan ID: `{{PLAN_ID}}` Generated: `{{TIMESTAMP}}` Generated by: `refactor-migration-plan` skill

## What this plan covers

Refactor `{{SOURCE_ROOT}}` (`{{SOURCE_LANG}}`) into `{{TARGET_ROOT}}`
(`{{TARGET_LANG}} {{TARGET_LANG_VERSION}}`) as a **full rewrite**, preserving the external contract
and re-deriving the internal implementation in `{{TARGET_LANG}}` idioms.

System type: `{{SYSTEM_TYPE}}` Contract surfaces: {{CONTRACT_SURFACES}}

## Non-negotiables (digest)

1. Preserve the external contract; do not preserve internal structure.
2. Re-derive design from contract + target canon, not from source code.
3. No transliteration. See `04-ANTI-TRANSLITERATION.md`.
4. No scope creep. New features ship after rewrite is complete.
5. Phase model A→F is gated. Each phase's gate is in `MANIFEST.yaml`.

## Where the canonical guideline lives

`{{GUIDELINE_PATH}}` — section references throughout the plan (`§0`, `§3`, `§6`, …) refer to this
document.

## Parity boundary

**Preserved:** {{PRESERVED_LIST}}

**Intentionally NOT preserved (each has an ADR):** {{NOT_PRESERVED_LIST}}

## Open Questions

<!-- The implementation agent appends here whenever it hits ambiguity. -->

- (none yet)

## Known undocumented behaviors / quirks (from user)

{{QUIRKS}}

## How to use this plan

1. As an implementation agent: read `AGENTS.md` then `00-EXECUTION-GUIDE.md`.
2. As a human: skim the seven numbered files (01–07) in order; each maps to one phase of the
   rewrite.
3. As a reviewer: invoke the skill with `--review` to audit the target against this plan + the
   source.
```

---

## TEMPLATE — `01-CONTRACT.md` (Phase A)

```markdown
# Phase A — Contract Extraction

<phase-metadata>
phase: A
file: 01-CONTRACT.md
status: pending
gate: All contract surfaces captured as machine-checkable artifacts.
</phase-metadata>

## Purpose

Produce a machine-checkable description of what `{{SOURCE_ROOT}}` promises to its users,
**independent of how it is implemented**. Source code is **not** the authority; observed behavior
is.

## Contract surfaces in scope

{{CONTRACT_SURFACES}}

## Tasks

- [ ] T-A-01 — Capture top-level `--help` output of the source binary into
      `contract/help-text/root.golden`.
- [ ] T-A-02 — Capture `--help` for each subcommand into `contract/help-text/<subcommand>.golden`.
- [ ] T-A-03 — Capture `--version` output into `contract/VERSION.txt`.
- [ ] T-A-04 — Enumerate every exit code the source can emit; populate `contract/exit-codes.md`
      (markdown table: code → meaning → trigger).
- [ ] T-A-05 — Document stdout/stderr shape (plain, JSON, table, line-ending behavior, TTY-vs-pipe
      differences) in `contract/stdout-stderr-shape.md`.
- [ ] T-A-06 — Document every environment variable the source reads in `contract/env-vars.md` (name,
      type, default, semantics).
- [ ] T-A-07 — Extract the config-file schema as JSON Schema into `contract/config-schema.json`. If
      multiple formats are accepted, list them all.
- [ ] T-A-08 — If source exposes an HTTP/gRPC API: capture/produce `contract/openapi.yaml` (or
      `*.proto`) and `contract/error-payloads.md`. Otherwise mark this task `[s]` (skipped) with
      reason.
- [ ] T-A-09 — Document on-disk file formats produced/consumed by the source in
      `contract/on-disk-formats.md`.
- [ ] T-A-10 — Document wire formats (if networked) in `contract/wire-formats.md`.
- [ ] T-A-11 — Document semver promises and compatibility envelope in `contract/semver-promises.md`.
- [ ] T-A-12 — Finalize the parity boundary in `<parity-boundary>` below. Every item under
      "not-preserved" must have an ADR.
- [ ] T-A-13 — Write `adr/0001-rewrite-decision.md` (MADR; rationale for the rewrite).
- [ ] T-A-14 — Write `adr/0002-parity-boundary.md` (MADR; what is preserved vs. not).
- [ ] T-A-15 — Record `source.scan-fingerprint` in `MANIFEST.yaml` — SHA-256 over the concatenated
      CONTENTS of every file in the source-scan dir, in `LC_ALL=C` filename-sorted order (the
      deterministic order the skill uses at plan-creation) — used for drift detection in `--review`.

## CLI contract

<cli-contract>
Tool name: <TBD: confirm binary name>
Top-level invocation: `<binary> [GLOBAL OPTIONS] <subcommand> [SUBCOMMAND OPTIONS] [ARGS]`

Subcommands:

- `<subcommand>` — <one-line description from help text>
  - Flags: <list>
  - Arguments: <list>
  - Exit codes: <list>

(Fill from `contract/help-text/*.golden` captured in T-A-01/02.)
</cli-contract>

## Exit codes

<exit-codes>
| Code | Meaning | When emitted |
|------|---------|--------------|
|   0  | success | normal completion |
| ...  | ...     | ...           |
</exit-codes>

## Config schema

See `contract/config-schema.json`. Inline summary:

<config-schema>
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "type": "object",
  "properties": {},
  "required": []
}
</config-schema>

## Parity boundary

<parity-boundary>
Preserved (must be bit-for-bit or per documented tolerance):
{{PRESERVED_LIST}}

Intentionally NOT preserved (each requires an ADR): {{NOT_PRESERVED_LIST}}
</parity-boundary>

## Semantic gaps

See `SEMANTIC-GAPS.md` for `{{SOURCE_LANG}}`↔`{{TARGET_LANG}}` mismatches the implementation agent
must handle (integer arithmetic, string encoding, null/None semantics, concurrency model, error
model, …).

## Reference: canonical guideline §3 Phase A

`{{GUIDELINE_PATH}}#phase-a--contract-extraction`
```

---

## TEMPLATE — `02-CHARACTERIZATION.md` (Phase B)

```markdown
# Phase B — Freeze Behavior (Characterization Tests Against the Source)

<phase-metadata>
phase: B
file: 02-CHARACTERIZATION.md
status: pending
gate: parity-tests/ created and PASSING against the source today.
blocked-by: [A]
</phase-metadata>

## Purpose

Lock the source's current observable behavior into automated tests that pass against the source
**now** and will be required to pass against the target later. These are the contract in executable
form.

## Tasks

- [ ] T-B-01 — Decide the harness language for parity tests (typically the target language or a
      language-neutral runner like `bats-core` for CLI). Justify in this file.
- [ ] T-B-02 — Create `parity-tests/golden/` and write one approval/golden test per documented CLI
      invocation captured in Phase A. Each test asserts stdout, stderr, and exit code.
- [ ] T-B-03 — Create `parity-tests/help-text/` tests that diff against
      `contract/help-text/*.golden`.
- [ ] T-B-04 — Create `parity-tests/exit-codes/` tests; one test per row in
      `contract/exit-codes.md`.
- [ ] T-B-05 — If service: create `parity-tests/replay/` with recorded HTTP cassettes
      (VCR/WireMock/mitmproxy) covering every documented route.
- [ ] T-B-06 — Define **language-neutral** invariants in `parity-tests/property/` so the same suite
      can be re-implemented against the target (Hypothesis / proptest / QuickCheck / fast-check /
      jqwik).
- [ ] T-B-07 — Establish a performance baseline. Record source runtime/memory for the representative
      workloads in `parity-tests/perf/`.
- [ ] T-B-08 — Run the full Phase-B suite against the source. **It must be 100% green** before Phase
      C. Save the run log to `parity-tests/run-logs/source-<timestamp>.log`.
- [ ] T-B-09 — Coverage map: a table in this file mapping each contract artifact from Phase A to the
      parity test that exercises it. Gaps explicitly accepted (with a top-level Open Question) or
      filled.

## Coverage map

| Contract item                            | Parity test path                           | Status |
| ---------------------------------------- | ------------------------------------------ | ------ |
| `contract/exit-codes.md` row 0 (success) | `parity-tests/exit-codes/test_exit_0.bats` | <TBD>  |
| ...                                      | ...                                        | ...    |

## Reference

`{{GUIDELINE_PATH}}#phase-b--freeze-behavior-characterization-tests-against-the-source`
```

---

## TEMPLATE — `03-DESIGN.md` (Phase C)

```markdown
# Phase C — Idiomatic Design

<phase-metadata>
phase: C
file: 03-DESIGN.md
status: pending
gate: design/ artifacts written; every choice justified by contract + target canon.
blocked-by: [A, B]
source-code-access: FORBIDDEN
</phase-metadata>

## Hard rule

During Phase C, **do not read the source project's code**. You may read:

- `01-CONTRACT.md` and the `contract/` tree.
- `02-CHARACTERIZATION.md` and `parity-tests/`.
- The target-language idiom canon: `{{TARGET_LANG_CANON}}`.
- The canonical guideline at `{{GUIDELINE_PATH}}`.

This separation is the single highest-leverage anti-transliteration guardrail (§3 Phase C of the
canonical guideline).

## Tasks

- [ ] T-C-01 — Module layout: propose the target-language source-tree layout and justify each
      top-level dir/file by (a) a contract requirement, (b) a target-language convention. Write to
      `design/architecture.md`.
- [ ] T-C-02 — Dependency choices: for each contract surface, choose the idiomatic `{{TARGET_LANG}}`
      library. List rejected alternatives. Write to `design/dependencies.md`.
- [ ] T-C-03 — Error model: design from contract (recoverable vs. bug vs. precondition). Do NOT
      mirror source error types 1:1. Write to `design/error-model.md`.
- [ ] T-C-04 — Concurrency model: choose target's native primitives. Write to
      `design/concurrency-model.md`.
- [ ] T-C-05 — I/O model: streaming vs. batch, sync vs. async, buffering decisions. Write to
      `design/io-model.md`.
- [ ] T-C-06 — CLI parsing strategy (if CLI): idiomatic target library (clap / cobra / typer / oclif
      / picocli). Write to `design/cli.md`.
- [ ] T-C-07 — Configuration parsing: typed config (dataclass / pydantic / serde struct), not
      stringly-typed dict. Write to `design/config.md`.
- [ ] T-C-08 — Logging/observability: structured logging via target's idiomatic crate/lib (slog /
      tracing / structlog / pino). Write to `design/observability.md`.
- [ ] T-C-09 — Write one MADR per non-trivial design choice in `adr/0003-*.md`, `0004-*.md`, ….
- [ ] T-C-10 — Self-review against `04-ANTI-TRANSLITERATION.md`. For each smell, confirm the design
      does not exhibit it.

## Reference

`{{GUIDELINE_PATH}}#phase-c--idiomatic-design-from-the-contract-without-the-source-code`
```

---

## TEMPLATE — `04-ANTI-TRANSLITERATION.md`

See `references/refusal-list.md` — the skill copies that file's body into
`04-ANTI-TRANSLITERATION.md`, with `{{SOURCE_LANG}}` and `{{TARGET_LANG}}` substituted.

---

## TEMPLATE — `05-IMPLEMENTATION-GUARDRAILS.md` (Phase D)

```markdown
# Phase D — Implementation Under Anti-Transliteration Guardrails

<phase-metadata>
phase: D
file: 05-IMPLEMENTATION-GUARDRAILS.md
status: pending
gate: All features implemented; each feature ships with parity tests; refusal-list review clean.
blocked-by: [C]
</phase-metadata>

## Hard rules for the implementing agent

1. The agent **must refuse** to "translate function X from source to target". The valid request is
   "implement contract feature Y per `03-DESIGN.md`".
2. The agent **must refuse** to copy source-side names, file layouts, or module structure when those
   violate target conventions.
3. The agent **must consult** `{{TARGET_LANG_CANON}}` for every non-trivial construct.
4. The agent **must emit a parity test alongside every implemented contract feature**, before
   committing.
5. The agent **must scan its own diff** for the 16 smells in `04-ANTI-TRANSLITERATION.md` before
   declaring a task done.

## Implementation tasks

Tasks here are **per-feature**, not per-source-file. The implementation agent generates them as a
derivative of `01-CONTRACT.md`. Example seeds:

- [ ] T-D-01 — Implement command `<subcommand-1>` end-to-end (parsing, behavior, output, exit
      codes). Ship `parity-tests/golden/test_<subcommand-1>.*` alongside.
- [ ] T-D-02 — Implement command `<subcommand-2>` end-to-end. Ship parity tests.
- [ ] T-D-03 — Implement config loader per `design/config.md`. Ship a property test that round-trips
      every shape in `contract/config-schema.json`.
- [ ] T-D-04 — Implement error hierarchy per `design/error-model.md`. Ship unit tests for every
      error path.
- [ ] T-D-05 — Implement logging per `design/observability.md`. Ship a smoke test that emits each
      log level.
- [ ] T-D-06 — Implement I/O layer per `design/io-model.md`. Ship a property test for streaming
      invariants.
- [ ] T-D-07 — Implement concurrency layer per `design/concurrency-model.md`. Ship a race/property
      test.
- [ ] T-D-08 — Run full self-review against `04-ANTI-TRANSLITERATION.md` over the diff; record
      findings.

(Implementation agent may split and re-number tasks freely as long as the parent T-D-NN slots are
accounted for in `MANIFEST.yaml`.)

## Reference

`{{GUIDELINE_PATH}}#phase-d--implementation-under-anti-transliteration-guardrails`
```

---

## TEMPLATE — `06-VERIFICATION-PLAN.md` (Phase E)

```markdown
# Phase E — Differential / Property / Fuzz / Shadow Validation

<phase-metadata>
phase: E
file: 06-VERIFICATION-PLAN.md
status: pending
gate: All parity tests green; differential clean; fuzz clean; perf within envelope.
blocked-by: [D]
</phase-metadata>

## Tasks

- [ ] T-E-01 — Run Phase-B parity tests against the target. Resolve every failure (fix code or add
      ADR for documented diff).
- [ ] T-E-02 — Run language-neutral property tests against the target with at least the same
      input-space as Phase B.
- [ ] T-E-03 — Build a differential test harness that runs identical inputs through source and
      target and asserts equivalence. Use Trail of Bits DIFFER
      (<https://blog.trailofbits.com/2024/01/31/introducing-differ-a-new-tool-for-testing-and-validating-transformed-programs/>)
      or a language-native harness. Run on the corpora from `parity-tests/golden/` and
      `parity-tests/replay/`.
- [ ] T-E-04 — Run a coverage-guided fuzz campaign (AFL++ / libFuzzer / cargo-fuzz / jazzer /
      OSS-Fuzz) for the duration in `MANIFEST.yaml: phases.E.fuzz-budget` (default: 24 CPU-hours).
      No crashes; no divergence on minimized inputs.
- [ ] T-E-05 — If service: shadow-traffic the target against production source traffic for the
      duration in `MANIFEST.yaml: phases.E.shadow-duration`. Investigate and resolve/ADR every
      divergence.
- [ ] T-E-06 — Measure performance against the `parity-tests/perf/` baseline from Phase B.
      Regressions outside the documented envelope block cutover.
- [ ] T-E-07 — Final coverage report: every contract item covered by at least one test class (golden
      / property / differential / fuzz / shadow / perf).

## Reference

`{{GUIDELINE_PATH}}#phase-e--differential-property-fuzz-shadow-validation`
```

---

## TEMPLATE — `07-CUTOVER.md` (Phase F)

```markdown
# Phase F — Parallel-Run, Canary, Cutover, Decommission

<phase-metadata>
phase: F
file: 07-CUTOVER.md
status: pending
gate: parallel-run complete; canary clean; rollback tested; source decommissioned.
blocked-by: [E]
</phase-metadata>

## Tasks

- [ ] T-F-01 — Deploy the target alongside the source. Wire both to the same upstream traffic.
- [ ] T-F-02 — Parallel-run (dark launch): only source responses are user-visible; target responses
      are logged + diffed. Run until divergence rate ≤ threshold in
      `MANIFEST.yaml: phases.F.divergence-threshold`.
- [ ] T-F-03 — Canary: route 1–5% of user traffic to the target. Monitor error rate, latency,
      resource usage.
- [ ] T-F-04 — Progressive rollout: 5% → 25% → 50% → 100%, gated by SLO adherence at each step.
- [ ] T-F-05 — Cutover: source goes read-only / off. Target is system of record.
- [ ] T-F-06 — Document rollback procedure and test it once on a canary before step T-F-05.
- [ ] T-F-07 — Confidence period: monitor target alone for
      `MANIFEST.yaml: phases.F.confidence-period-days`. No incidents → proceed to decommission.
- [ ] T-F-08 — Decommission: remove source code from the repo (or archive). Announce EOL.
- [ ] T-F-09 — Write `adr/9999-postmortem.md` capturing what worked, what surprised us, and what to
      do differently next time.

## Reference

`{{GUIDELINE_PATH}}#phase-f--parallel-run-canary-cutover-decommission`
```

---

## TEMPLATE — `GLOSSARY.md`

```markdown
# Glossary

| Term                       | Definition                                                                                                                                                                                      |
| -------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Contract**               | The external observable surface of the source/target: CLI flags, exit codes, stdout/stderr shape, HTTP routes and payloads, on-disk and wire formats, env vars, config schema, semver promises. |
| **Transliteration**        | Mechanical mapping of source-language constructs into target-language syntax preserving source-side structure. Always wrong in this rewrite.                                                    |
| **Characterization test**  | A test that pins the source's _current_ observable behavior before any change (Feathers).                                                                                                       |
| **Golden / approval test** | A characterization test whose expected output is a stored fixture. Diffs are explicitly re-approved.                                                                                            |
| **Differential test**      | Same inputs through source and target; outputs compared.                                                                                                                                        |
| **Property test**          | Asserts invariants hold for randomly generated inputs. Language-neutral; reuse across source and target.                                                                                        |
| **Parity test**            | Any of the above used as a gate for this rewrite.                                                                                                                                               |
| **Parity boundary**        | Explicit set of behaviors the rewrite **does** and **does not** preserve. Documented in `01-CONTRACT.md`.                                                                                       |
| **Translation smell**      | A construct that betrays source-language origin in target-language code. See `04-ANTI-TRANSLITERATION.md`.                                                                                      |
| **ADR**                    | Architecture Decision Record (MADR format: <https://adr.github.io/madr/>).                                                                                                                      |
| **Plan dir**               | This directory: `refactor-plan/`. The single source of truth for this rewrite.                                                                                                                  |
| **Phase letter**           | `A`–`F`, matches the phases in `MANIFEST.yaml`.                                                                                                                                                 |
```

---

## TEMPLATE — `SEMANTIC-GAPS.md`

```markdown
# Semantic Gaps — `{{SOURCE_LANG}}` → `{{TARGET_LANG}}`

Per the canonical guideline §11 (LLM Code Translation Research), these are the categories where
mechanical translation fails because of different language semantics. The implementation agent must
check each item during Phase D and write a parity test that pins behavior on the gap.

Common gap categories (instantiate the rows for this specific pair):

| Category              | `{{SOURCE_LANG}}` behavior                 | `{{TARGET_LANG}}` behavior             | Mitigation in this rewrite                                         |
| --------------------- | ------------------------------------------ | -------------------------------------- | ------------------------------------------------------------------ |
| Integer arithmetic    | <e.g. defined modulo 2³² (Java)>           | <e.g. arbitrary precision (Python)>    | <e.g. cast to `int32` at API boundary; property test for overflow> |
| String / text         | <e.g. byte sequences with no encoding (C)> | <e.g. always Unicode (Python str)>     | <decode at boundary; pin encoding in `contract/`>                  |
| Null / absence        | <e.g. `nil` / null-pointer>                | <e.g. `Option<T>` / typed absence>     | <use typed absence; property test for None handling>               |
| Concurrency primitive | <e.g. threads + GIL (Python)>              | <e.g. goroutines (Go)>                 | <design from contract; do not port locking strategy>               |
| Error model           | <e.g. exceptions>                          | <e.g. `Result<T, E>` (Rust)>           | <re-derive recoverable vs. bug from contract>                      |
| Char/byte arithmetic  | <e.g. char == u8 (C)>                      | <e.g. char is a Unicode scalar (Rust)> | <treat all text as Unicode at boundary>                            |
| Floating point        | <e.g. JS `number` (IEEE 754 double)>       | <e.g. Rust f32/f64 split>              | <pin precision per contract; property test>                        |
| Time / timezone       | <…>                                        | <…>                                    | <…>                                                                |
| Filesystem            | <…>                                        | <…>                                    | <…>                                                                |

Add a row for any quirk the user surfaced in the Phase 2 interview (see `{{QUIRKS}}`).

## Reference

`{{GUIDELINE_PATH}}#11-llm-code-translation-research-findings`
```

---

## TEMPLATE — `REVIEW-<UTC-ISO-8601>.md` (review-mode output)

```markdown
# Review Report — {{TIMESTAMP}}

<review-metadata>
reviewed-by: <agent-name>
plan-id: {{PLAN_ID}}
source-root: {{SOURCE_ROOT}}
source-git-head-at-plan: {{SOURCE_GIT_HEAD}}
source-git-head-at-review: <re-read>
implementation-status: <in-progress | complete>
</review-metadata>

## Verdict

`<APPROVED | APPROVED_WITH_CONDITIONS | CHANGES_REQUIRED | REJECTED>`

## Source drift detection

- Git HEAD diff: <none | drifted: <old> → <new>>
- Scan fingerprint diff: <match | drifted; see findings below>
- Findings:
  - <list any contract surfaces that changed in the source and were not reflected in the plan;
    recommend Phase A re-run>

## Phase A — Contract adherence

Status: `<✅ | ⚠️ | ❌>` Findings:

- <ID, severity, file:line, recommendation>

## Phase B — Parity-test coverage

Status: `<✅ | ⚠️ | ❌>` Findings: …

## Phase C — Design adherence

Status: `<✅ | ⚠️ | ❌>` Findings: …

## Phase D — Anti-transliteration smell scan

Status: `<✅ | ⚠️ | ❌>` Findings (per smell from `04-ANTI-TRANSLITERATION.md`):

- §6.1 (Class-hierarchy mirroring): <count> hits — <file:line list>
- §6.2 (Shell pipeline as subprocess chain): <count> hits — <…>
- … (one row per refusal item)

## Phase E — Verification gates

Status: `<✅ | ⚠️ | ❌>` Findings: …

## Phase F — Cutover readiness

Status: `<✅ | ⚠️ | ❌>` (or `N/A` if not yet in Phase F) Findings: …

## Semantic-gap regressions

Status: `<✅ | ⚠️ | ❌>` Findings: …

## Recommended actions (numbered, ordered by severity)

1. …
2. …

## Gate to next phase?

`<approve | block; reasons>`
```

---

## TEMPLATE — ADRs (MADR format)

### `adr/0001-rewrite-decision.md`

```markdown
---
status: accepted
date: {{TIMESTAMP}}
decision-makers: [<user>]
consulted: []
informed: []
---

# Rewrite `{{SOURCE_LANG}}` project to `{{TARGET_LANG}}`

## Context and Problem Statement

`{{SOURCE_ROOT}}` is implemented in `{{SOURCE_LANG}}`. Why rewrite, and why now?

<Fill from user's stated motivation in the interview.>

## Decision Drivers

- <e.g. performance>
- <e.g. type safety>
- <e.g. distribution as a single binary>
- <e.g. team familiarity>

## Considered Options

1. Keep `{{SOURCE_LANG}}` as-is and refactor internally.
2. Rewrite in `{{TARGET_LANG}}` (full refactor, contract-preserving). ← chosen
3. Rewrite in a different target language.

## Decision Outcome

Chosen: option 2. The rewrite preserves the external contract per `01-CONTRACT.md` and re-derives
the internal implementation in `{{TARGET_LANG}}` idioms per `03-DESIGN.md`.

### Consequences

- ✅ <expected wins>
- ⚠️ <known costs (rewrite effort, dual maintenance during cutover, …)>

## Reference

Canonical guideline: `{{GUIDELINE_PATH}}`.
```

### `adr/0002-parity-boundary.md`

```markdown
---
status: accepted
date: {{TIMESTAMP}}
decision-makers: [<user>]
---

# Parity Boundary

## Context

The rewrite preserves the external contract. Some behaviors are intentionally **not** preserved.
This ADR makes that boundary explicit so reviewers and the implementation agent know where the line
is.

## Decision

### Preserved (bit-for-bit or per documented tolerance)

{{PRESERVED_LIST}}

### Intentionally NOT preserved

{{NOT_PRESERVED_LIST}}

(Each "not preserved" item also gets its own dedicated ADR explaining the rationale and the
migration path.)

## Consequences

- Users depending on a "not preserved" behavior must migrate or accept the change. This is the only
  place such expectations are made explicit.
- The Phase E parity tests will document each "not preserved" item as an approved diff, not a
  regression.
```

---

End of templates.
