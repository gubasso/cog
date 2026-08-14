# 013 — Plugin protocol

## Goal

An external program becomes a `cog <name>` subcommand by shipping one executable, and can prove its conformance without reading cog's source.

## Appetite

3 implementation sessions. Chosen before the design below.

## Core

Cog dispatches to a separate process and inspects it; it never installs, catalogues, or trusts it.

## In scope

This is the ordered negotiable remainder, cut last-first from the bottom of the list.

- The published protocol at [plugin protocol](../../../reference/plugin-protocol.md) and [ADR-0034](../../../decisions/ADR-0034-extend-cog-through-external-executables.md). A third party must be able to implement a conformant plugin from the reference alone, which is what makes the seam an extension point rather than an invitation to read cog's Bash.
- Resolution, the side-effect-free metadata probe, and environment construction in `lib/functions/fn_plugin.sh`. Nothing in that file may die on plugin input: a malformed or hostile plugin degrades to a state token, because a third party's bug must not become a cog outage.
- `cog plugin list|info|validate|host-info` with its four mirrored surfaces. `validate` is the load-bearing verb — without it "conformant" is a matter of opinion and every third party guesses.
- The dispatch fallback in `lib/loader.sh`, reached only once the first-party module check has failed.
- `cog help <plugin>` delegation. This is cut first.

## Out of scope

- Installing, downloading, updating, or catalogueing plugins. Each of those makes cog responsible for a third party's lifecycle, and each needs its own decision record.
- Multi-level plugin names and plugins that replace, wrap, decorate, or hide a first-party command.
- Plugin-contributed skills, skill-refs, or `data/` tables. Resource roots are first-hit-wins whole-root replacement today, and composing them bundles namespace ownership, install safety, and precedence into one mechanism.
- Signing, provenance, sandboxing, or any trust claim about a plugin's contents.

## Governed by

- `docs/decisions/ADR-0002-standalone-loader-based-cli.md` — the loader this extends, and why cog is one process rather than a set of scripts.
- `docs/decisions/ADR-0003-machine-facing-output-contract.md` — the `--json` obligation every verb answers to.
- `docs/decisions/ADR-0007-skill-and-cli-responsibility-boundary.md` — why the mechanics of resolution and inspection belong in cog.
- `docs/decisions/ADR-0008-self-contained-resource-homes.md` — why a plugin may not write into cog's installed trees.

## Acceptance

```text
When a cog-<name> executable is on PATH and no module owns the name, cog shall exec it with argv verbatim and return its exit code. -> test/integration/loader_plugin_dispatch.bats
When a first-party module owns a name, cog shall never execute a same-named plugin. -> test/integration/loader_plugin_dispatch.bats
When a plugin's metadata probe fails, cog shall still dispatch to it. -> test/integration/loader_plugin_dispatch.bats
When cog execs a plugin, it shall export exactly four COG_ variables and no path under lib/. -> test/unit/fn_plugin.bats
When cog plugin validate runs against a conformant plugin, it shall exit 0 with every check passing. -> test/integration/cmd_plugin.bats
```

## Rabbit holes

- Installation creeps in through `validate` needing a source — escape: `validate` takes a path or a resolved name and nothing else.
- The probe becomes a dispatch gate — escape: dispatch never probes, and a fixture that records being probed asserts it.
- Plugin names leak into the static completion array — escape: runtime append only, because the array is gated by exact set equality against `lib/commands/`.
- The protocol constants drift from the published table — escape: the literals in `fn_plugin.sh` are pinned to `data/plugin-protocol/` by a unit test, the same mirrored-surface-plus-drift-test shape help, completion, and the man page already use.

## Done when

A fixture plugin dispatches, `cog plugin validate` certifies it, `cog --help` is byte-identical to before, all four surfaces agree, and the milestone line flips.

## Revisions

2026-08-14, at implementation: five shaping decisions the plan left to the operator. The slice took id 013 and the record took ADR-0034, because the draft was written against a tree where 0032 and 0033 were still free. A non-executable `cog-<name>` at dispatch raises `PluginNotExecutable` rather than folding into `UnknownCommand`, because a forgotten `chmod +x` is far more common than a name that happens to collide with a file. The probe uses `timeout(1)`, already carried by the devShell's coreutils and now named in `just devshell-check` so the dependency is declared rather than assumed. `COG_PLUGIN_DIR` ships in this revision, documented as forward compatibility toward a dedicated plugin directory. `cog plugin` keeps all four verbs.

2026-08-14, at implementation: `cog plugin list` emits one row per candidate rather than one per name. Shaping assumed one row per plugin, which left `shadowed-by-path` and a broken losing candidate with nowhere to be reported — the state vocabulary named states the command could never emit.

2026-08-14, at review: six corrections where the implementation and the published protocol disagreed, the reference being right in every case but one. A flag after a plugin name is argv, so `cog <plugin> -h|--help` now dispatches verbatim instead of being answered by cog's help path, which had been rewriting the flag and dropping every argument after it; `cog help <plugin>` and `cog --help <plugin>` remain the delegations. The probe's deadline is enforced with a follow-up kill, because `timeout`'s TERM alone left a plugin that ignores TERM holding `list`, `info`, and `validate` open forever — the outage the design forbids. `$PATH` is split without translating `:` to newline, which had converted a newline inside one component into two searchable directories and made the documented newline rejection unreachable. `list` and `info` derive state and metadata from one probe rather than two, since a plugin answering the two runs differently could produce `state: "ok"` beside null metadata. `validate` reports `requires_cog` and `requires_cog_satisfied` advisorily, which the reference already promised. Completion enumeration runs under a hard time bound, which the reference also already promised.

The one place the code was right and the reference silent: `info`'s `ok` now means the inspection succeeded, matching `list` and agreeing with the exit status, and plugin health is read from `state`. Conflating the two made `cog plugin info <broken> --json` print `ok: false` and exit `0`.
