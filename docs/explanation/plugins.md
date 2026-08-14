# Plugins

Cog has exactly one extension seam. An unknown command `cog <name>` resolves an executable called `cog-<name>` and `exec`s it. The exact contract — resolution order, the environment, the metadata probe, the states, and the conformance checks — is owned by [plugin protocol](../reference/plugin-protocol.md); this page owns why the seam has the shape it does. [ADR-0034](../decisions/ADR-0034-extend-cog-through-external-executables.md) records the decision.

## Why a separate process

Cog sources more than fifty function files eagerly into one flat global namespace under `set -euo pipefail` with `inherit_errexit`. A sourced plugin could redefine any `cog::fn::*`, change shell options or traps, and take cog's process down with it. Every ecosystem that tried the in-process version documents the cost: cargo tells tool authors not to link its library because the API is unstable and may not match the running binary, AWS labels its CLI v2 plugin interface provisional with no compatibility guarantee, and mise now classifies asdf plugins as legacy over arbitrary shell execution and weak provenance. `exec` replaces cog's process, so a plugin's crash, hang, or strict-mode abort is a fault in one program rather than two.

## Why core always wins, structurally

Resolution is attempted only after the first-party module check has failed. That is not a policy check a future contributor could reorder without noticing — there is no code path in which a plugin is consulted while a module exists. A `cog-<name>` that collides with a first-party command is dead weight, reported as `shadowed-by-core` and never executed. It also means normal dispatch pays nothing for the seam: a first-party command never touches plugin code.

## Why the probe is not a gate

The metadata probe is the single most likely thing for a future contributor to "fix" into a precondition. It must not become one. A plugin whose probe times out, exits non-zero, or emits malformed JSON still dispatches; only `cog plugin list`, `info`, and `validate` ever run it. Gating dispatch on the probe would turn every plugin author's bug into a cog outage, and would put a fork and a timeout on the path of every plugin invocation. `test/integration/loader_plugin_dispatch.bats` asserts both halves: a broken-probe plugin runs, and a plugin that records being probed is never probed by dispatch.

## Why no path to cog's Bash is ever exported

Cog hands a plugin four variables and no more. None of them is a path into `lib/`. The omission is deliberate: the moment a plugin can find `fn_data.sh`, someone sources it, and every internal helper becomes a compatibility surface that cannot be renamed. The contract is the CLI — a plugin calls `cog <command> --json` like any other caller. `COG_EXECUTABLE` exists so it can call the host that actually invoked it rather than whichever `cog` is first on `PATH`, which is the same reason cargo exports `CARGO`.

## What cog does not claim

Cog makes no trust, provenance, or safety claim about a plugin. It does not sign, verify, checksum, sandbox, or audit anything, and it has no index that could imply review. Running a plugin means the file was found and was executable; it means nothing else. Installing a plugin is the plugin project's business, exactly as krew installs kubectl plugins without kubectl knowing krew exists.

## Why plugins are invisible to default help

`cog --help` is asserted byte-equal against a literal snapshot, which is what keeps help, completion, the man page, and `docs/reference/cli-commands.md` honest as commands come and go. Merging third-party names into that listing would end the guarantee. Every comparable system draws the same line — git keeps external commands behind `git help --all`, kubectl uses `kubectl plugin list`, gh uses `gh extension list`. Cog uses `cog plugin list`, and the completion function appends plugin names at runtime rather than writing them into the array the snapshot test gates.

## Relationship to skills and to `data/`

Plugins extend the command surface only. They contribute no skills, no skill-refs, and no `data/` tables. Those roots are first-hit-wins whole-root replacement rather than composition, and one malformed third-party YAML file is fatal for an entire merged table — so letting plugins into them would bundle namespace ownership, install safety, and precedence into a single undesigned mechanism. Whether that composition is ever wanted is [Q-008](../plan/open-questions.md).
