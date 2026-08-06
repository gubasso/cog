# 003 — Linear workflow vertical

<!-- markdownlint-configure-file { "MD043": { "headings": ["# 003 — Linear workflow vertical","## Goal","## Appetite","## Core","## In scope","## Out of scope","## Governed by","## Acceptance","## Rabbit holes","## Done when","## Revisions"] } } -->

## Goal

One installed linear stub workflow can be listed, validated, resolved, claimed, recorded, and summarized end to end.

## Appetite

3 implementation sessions. Chosen before the design below.

## Core

A single leaf workflow completes the full lifecycle with durable receipts and named integration coverage, leaving optional registry breadth as remainder.

## In scope

This is the ordered negotiable remainder, cut last-first from the bottom of the list.

- Create the feature-scoped `workflow/meta.yaml`, `workflow/workflows/`, `workflow/steps/`, and `workflow/skills/` tree. `meta.yaml` carries exactly three closed defaults — `context`, `max_rounds`, `max_workflow_depth` — and no default cell, because every leaf pins its own.
- Carry the proposed verb grammar verbatim so a later session does not re-derive it. Every verb fails closed and exits `2` on `InvalidInput`; `--json` is the contract and the bare forms exist for a human reading a terminal.

  ```text
  cog workflow list [--json]
  cog workflow show <key> [--json]
  cog workflow init <key> --from <key> [--force]
  cog workflow validate [<key>]
  cog workflow resolve --key <key> --run-dir <dir> --task-file <file> \
                       [--tier <name>] [--input k=v]... [--max-fresh-depth <n>] \
                       [--orchestrator <json>] --json
  cog workflow next    --run-dir <dir> --json
  cog workflow claim   --run-dir <dir> --as <instance> --owner <id> --json
  cog workflow record  --run-dir <dir> --as <instance> --claim-token <tok> \
                       --status done|failed [--reason <text>] --json
  cog workflow advance --run-dir <dir> --loop <handle> --round <n> --decision-token <tok> \
                       --outcome continue|converged|pause|abort [--reason <text>] --json
  cog workflow reclaim --run-dir <dir> --as <instance> --previous-claim <tok> \
                       --owner <id> --reason <text> --json
  cog workflow summary --run-dir <dir> --json
  cog workflow conformance --run-dir <dir>
  ```

- Carry the validator rule set, which runs once at load before any agent is spawned so a failure does not land at depth three after real spend: exactly one kind key per entry; `as:` unique within a DAG and every `needs:` target present in it; no cycle among `needs:` edges and none across file references; `cell:` a literal that exists in the cell registry as selectable and executable, with the same check on every value in a `cells:` map; a `cells:` map only on a `workflow:` node with every key naming a direct step of the referenced workflow, and the error carrying both file paths; `loop:` carrying both `until:` and `max_rounds:`; every expression path resolving to a declared input or an upstream declared handle, with `stdout` resolving on a leaf only; expression bodies containing only the declared tokens; `id:`, `as:`, and `cell:` parsed as strings to close the YAML scalar footguns; declared input types, `required:`, and `options:` honored; every leaf carrying a cell; `outputs:` never redeclaring `stdout`; no declared file output named `outputs.json`, `scalars.json`, `preamble.txt`, or `stdout.txt`; reference nesting within `max_workflow_depth`; and no `skill:` key anywhere under `workflows/`. The subagent budget is deliberately not a validator check: the structural part is `max_workflow_depth`, and the harness part is the opt-in `--max-fresh-depth` an orchestrator passes from its own remaining budget.
- Carry the exit-code protocol, which is protocol only and never workflow semantics: `0` valid result or applied transition, including the terminal states; `1` internal failure reading or persisting state; `2` `InvalidInput` for a stale or missing token, an illegal transition, a digest mismatch, or malformed output; `75` cannot advance yet, matching `cog codex-runner finalize`. Terminal run states live in the JSON `state` field at exit `0`.
- Implement layer resolution. The unit of resolution is the file, not the root: one resolver walks project, then user, then installed, and returns the first file that exists, taken whole. Nothing is merged, not two files and not the keys inside them, so a project-layer workflow replaces the installed one entirely rather than inheriting its steps. Resolving per file rather than per root is what lets a user-authored workflow reference a shipped step, and `show` prints the resolved source per file so shadowing is visible. The workspace carries `meta.yaml`, `workflows/`, `steps/` — the only files that may carry `skill:` — and `skills/`, with the same shape at every layer.
- Implement the input/output receipt contract. Statically, every `${{ ...outputs.X }}` resolves to a declared handle on an upstream node or to `stdout`. At run time, each declared file must exist after a leaf finishes, and when the definition declares any scalar, `scalars.json` must exist, parse, and carry every declared handle at its declared type, or the step fails. One `record` call verifies declared file outputs, type-checks declared scalars, scans for unclaimed files, truncates `stdout.txt`, then writes `<as>/outputs.json` and updates `state.json`. cog never synthesizes `scalars.json`, a failed node still gets a receipt with partial outputs and an `error` object, and the receipt sees the node directory only.
- Install the accepted eleven-cell registry and validate literal cells plus direct-child overrides.
- Wire pre-commit `workflow validate --all` and the workflow Markdown pattern. This wiring is cut last.

## Out of scope

- Composite calls, loops, crash recovery, or provider-specific fresh-context runners.
- Retries, backoff, autonomous scheduling, or credential storage.

## Governed by

- `docs/decisions/0003-machine-facing-output-contract.md` — receipt stream behavior.
- `docs/decisions/0007-skill-and-cli-responsibility-boundary.md` — deterministic command mechanics.
- `docs/plan/slices/002-workflow-engine-go-no-go/README.md` — accepted grammar and cell contract.
- `docs/reference/cli-commands.md` — public CLI grammar owner.

## Acceptance

```text
When a linear stub is installed, the workflow system shall list, validate, resolve, claim, record, and summarize it. -> test/integration/cmd_workflow.bats
If a literal cell or direct-child override is unknown, then validation shall fail before dispatch. -> test/integration/cmd_workflow.bats
```

## Rabbit holes

- A general graph engine can displace the vertical — escape: support only the one accepted linear path.
- Receipt schemas can expand into telemetry — escape: keep only inputs, outputs, state, and dispatch identity.

## Done when

The named integration file passes unskipped, the accepted contract has current reference owners, and milestone 003 flips from `active` to `done`.

## Revisions

None.
