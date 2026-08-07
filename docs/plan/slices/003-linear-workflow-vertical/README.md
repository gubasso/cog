# 003 — Linear workflow vertical

## Goal

One installed linear stub workflow can be listed, validated, resolved, claimed, recorded, and summarized end to end.

## Appetite

3 implementation sessions. Chosen before the design below.

## Core

A single leaf workflow completes the full lifecycle with durable receipts and named integration coverage, leaving optional registry breadth as remainder.

## In scope

This is the ordered negotiable remainder, cut last-first from the bottom of the list.

- Create the feature-scoped `workflow/meta.yaml`, `workflow/workflows/`, `workflow/steps/`, and `workflow/skills/` tree. `meta.yaml` carries exactly three closed defaults — `context`, `max_rounds`, `max_workflow_depth` — and no default engine, because every step definition pins its own. The `max_rounds` default is a single digit, because a ceiling large enough to hide a runaway loop only makes the run expensive before it fails.
- Carry the proposed verb grammar verbatim so a later session does not re-derive it. Every verb fails closed and exits `2` on `InvalidInput`; `--json` is the contract and the bare forms exist for a human reading a terminal.

  ```text
  cog workflow list [--json]
  cog workflow show <key> [--json]
  cog workflow init <key> --from <key> [--force]
  cog workflow validate [<key>]
  cog workflow resolve --key <key> --run-dir <dir> --task-file <file> \
                       [--max-fresh-depth <n>] [--orchestrator <json>] --json
  cog workflow next    --run-dir <dir> --json
  cog workflow claim   --run-dir <dir> --as <instance> --owner <id> --json
  cog workflow record  --run-dir <dir> --as <instance> --claim-token <tok> \
                       --status done|failed [--reason <text>] --json
  cog workflow advance --run-dir <dir> --loop <handle> --decision-token <tok> \
                       --outcome continue|converged|pause|abort \
                       --reason criterion-met|stalled|unfeasible|needs-user \
                       [--note <text>] --json
  cog workflow reclaim --run-dir <dir> --as <instance> --previous-claim <tok> \
                       --owner <id> --reason <text> --json
  cog workflow summary --run-dir <dir> --json
  cog workflow conformance --run-dir <dir>
  ```

- Carry the validator rule set, which runs once at load before any agent is spawned so a failure does not land at depth three after real spend: exactly one kind key per entry; `as:` unique within a DAG and every `needs:` target present in it; no cycle among `needs:` edges and none across file references; `engine:` a literal that exists in the engine registry, required on every step definition and optional on a call site where it overrides that definition; `loop:` carrying both `until:` and `max_rounds:`, with `max_rounds:` a positive integer and `until:` a non-empty string; `id:`, `as:`, `engine:`, and `until:` parsed as strings to close the YAML scalar footguns; reference nesting within `max_workflow_depth`; and no `skill:` key anywhere under `workflows/`. A step file's described inputs and artifacts are checked against the skill it runs rather than enforced at run time. The subagent budget is deliberately not a validator check: the structural part is `max_workflow_depth`, and the harness part is the opt-in `--max-fresh-depth` an orchestrator passes from its own remaining budget.
- Carry the exit-code protocol, which is protocol only and never workflow semantics: `0` valid result or applied transition, including the terminal states; `1` internal failure reading or persisting state; `2` `InvalidInput` for a stale or missing token, an illegal transition, a digest mismatch, or malformed output; `75` cannot advance yet, matching `cog codex-runner finalize`. An `advance` that would exceed `max_rounds`, or that reports `continue` or `converged` on a round which produced no files, is an illegal transition. Terminal run states live in the JSON `state` field at exit `0`.
- Implement layer resolution. The unit of resolution is the file, not the root: one resolver walks project, then user, then installed, and returns the first file that exists, taken whole. Nothing is merged, not two files and not the keys inside them, so a project-layer workflow replaces the installed one entirely rather than inheriting its steps. Resolving per file rather than per root is what lets a user-authored workflow reference a shipped step, and `show` prints the resolved source per file so shadowing is visible. The workspace carries `meta.yaml`, `workflows/`, `steps/` — the only files that may carry `skill:` — and `skills/`, with the same shape at every layer.
- Implement the directory and receipt contract. Each step writes its artifacts into `<as>/` under the run directory, and `needs:` hands every upstream directory to the step that depends on it. One `record` call inventories the node directory, truncates the captured final message, then writes `<as>/outputs.json` and updates `state.json`. The receipt lists what the directory holds rather than verifying it against a declaration: cog counts files and never reads them. A failed node still gets a receipt with an `error` object, and the receipt sees the node directory only.
- Install the accepted eleven-engine registry and validate literal engines plus call-site overrides.
- Wire pre-commit `workflow validate --all` and the workflow Markdown pattern. This wiring is cut last.

## Out of scope

- Composite calls, loops, crash recovery, or provider-specific fresh-context runners.
- Retries, backoff, autonomous scheduling, or credential storage.

## Governed by

- `docs/decisions/ADR-0003-machine-facing-output-contract.md` — receipt stream behavior.
- `docs/decisions/ADR-0007-skill-and-cli-responsibility-boundary.md` — deterministic command mechanics.
- `docs/reference/workflow-contract.md` — accepted grammar, engine registry, and validator rules.
- `docs/reference/cli-commands.md` — public CLI grammar owner.

## Acceptance

```text
When a linear stub is installed, the workflow system shall list, validate, resolve, claim, record, and summarize it. -> test/integration/cmd_workflow.bats
If a literal engine on a definition or a call-site override is unknown, then validation shall fail before dispatch. -> test/integration/cmd_workflow.bats
```

## Rabbit holes

- A general graph engine can displace the vertical — escape: support only the one accepted linear path.
- Receipt schemas can expand into telemetry — escape: keep only inputs, outputs, state, and dispatch identity.

## Done when

The named integration file passes unskipped, the accepted contract has current reference owners, and milestone 003 flips from `active` to `done`.

## Revisions

Engine-registry growth: `In scope` said "install the accepted eleven-engine registry". The shipped registry carries the seed plus the current subscription-available provider models, because membership in the registry is the permission to dispatch and a seed that names only superseded models grants permission to nothing useful. What changed it was the provider surface moving after ADR-0027: the effort ladders are unchanged and the five invariants still gate every row, so the accepted grammar is untouched. Two rows the ladders imply are deliberately absent, on the same membership rule — a rung a provider rejects is a row that does not exist.

Nothing was cut. The pre-commit `workflow validate --all` wiring landed, and so did a subsystem page under `docs/explanation/` now that there is code for it to own. The registry invariants run on every `validate` call rather than behind a separate sub-mode, because a breadth surface that has to be asked for is a gate that gets skipped.
