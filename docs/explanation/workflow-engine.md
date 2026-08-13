# Workflow engine

How the `cog workflow` surface is built today. The accepted grammar, the engine registry shape, and the validator rules are owned by [workflow contract](../reference/workflow-contract.md); the verb grammar and the exit-code protocol are owned by [CLI commands](../reference/cli-commands.md). This page owns the module boundary and the run-time shape those two describe from the outside.

## Module boundary

One command module and three shared helpers, split by responsibility rather than by verb:

| Unit                                    | Owns                                                         |
| --------------------------------------- | ------------------------------------------------------------ |
| `lib/commands/cmd_workflow.sh`          | Argument parsing, JSON emission, exit codes, verb dispatch.  |
| `lib/functions/fn_workflow.sh`          | Layer resolution, workspace loading, engine-registry lookup. |
| `lib/functions/fn_workflow_validate.sh` | The validator rule set and the five registry invariants.     |
| `lib/functions/fn_workflow_state.sh`    | Run state, node directories, tokens, receipts.               |

The command module stays a thin layer over the helpers: it decides what to print and which code to exit with, and never decides what is valid.

## Resolution is per file

The unit of resolution is the file, not the root. One resolver walks project, then user, then installed, and returns the first file that exists, taken whole.

| Layer       | Root                                                           |
| ----------- | -------------------------------------------------------------- |
| `project`   | `$PWD/workflow` (`COG_WORKFLOW_PROJECT_ROOT` overrides)        |
| `user`      | `$XDG_CONFIG_HOME/cog/workflow`                                |
| `installed` | `$XDG_DATA_HOME/cog/workflow`, else the checkout's `workflow/` |

Nothing is merged, so a project-layer workflow replaces the installed one entirely rather than inheriting its steps. Resolving per file is what lets a user-authored workflow reference a shipped step, and `show` prints the resolved source per file so shadowing stays visible rather than inferred.

The engine registry deliberately lives outside that tree. It is CLI-owned reference data under `data/workflow-engines/`, because membership in the registry is the permission to dispatch — a project layer that could add its own rows could grant itself an engine.

## The run directory

`resolve` validates first and materializes second, so an invalid definition leaves no directories behind. Each step then writes into its own directory, and `needs:` hands every upstream directory to the step that depends on it.

```text
$RUN_DIR/
  state.json   the whole run: nodes, statuses, tokens, engines
  draft/       plan.md writes here
  vet/         receives ../draft/
  apply/       receives ../draft/ and ../vet/
```

`state.json` is written atomically — a partial state file is worse than none — and reading or persisting it is the only thing that exits `1`. Everything the caller got wrong exits `2`.

## Receipts

One `record` call inventories the node directory, truncates the captured final message, writes `<as>/outputs.json`, and updates `state.json`. The receipt lists what the directory holds rather than verifying it against a declaration: cog counts files and never reads them. A failed node still gets a receipt, carrying an `error` object.

The receipt key set is closed to inputs, outputs, state, and dispatch identity, and a jq key-set equality check enforces it on every write. That check is the guard against receipts drifting into telemetry; weakening it to `has(...)` tests would remove the only thing stopping a token count from being added quietly.

## What this release does not do

`resolve` accepts only an all-`step:` linear workflow and refuses `workflow:` and `loop:` nodes. The validator still checks those node kinds in full, and `advance` implements every round-boundary transition rule, so the grammar surface and the protocol are settled — what is missing is the materializer. A live `continue` therefore reports `75`, which is the honest signal for cannot advance yet.

The [orchestrator contract](../reference/orchestrator-contract.md) is published ahead of its enforcement, deliberately. Capability negotiation, the `requires_judgment` directive, and `max-fresh-depth` are specified there and consulted nowhere here: `resolve` stores `--orchestrator` and `--max-fresh-depth` verbatim and no verb reads either. Publishing first is what lets slice 006 write a runner against a fixed target instead of against this module's current behavior, and each forward-looking clause is marked as such on that page rather than left for a reader to discover by grep.

Composites, lazy loop rounds, and crash recovery arrive next; provider runners follow. Until a provider runner exists, a registry row's provider declares a runner name rather than proving a live binary, which is why `claude` rows validate today while only `codex` can be dispatched. What a runner must satisfy before that changes is published in [runner contract](../reference/runner-contract.md), ahead of its enforcement for the same reason the orchestrator contract is.
