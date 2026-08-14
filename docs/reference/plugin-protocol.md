# Plugin protocol

The exact contract between cog and an external `cog-<name>` executable. A third-party project can implement a conformant plugin from this page alone and prove it with `cog plugin validate`, without reading cog's source.

Cog inspects and executes plugins. Cog never installs, downloads, updates, or catalogues them. A plugin arrives on the machine by whatever means its own project ships it. Why this shape was chosen is in [ADR-0034](../decisions/ADR-0034-extend-cog-through-external-executables.md); the living design is in [plugins](../explanation/plugins.md). The constants below are also published as data under `data/plugin-protocol/`.

## Naming

A plugin is a single executable file named `cog-<name>`, where `<name>` matches `^[a-z][a-z0-9_-]*$` — the same slug rule cog applies to its own command names.

Names are single-level. `cog foo bar` always resolves `cog-foo` and passes `bar` as its first argument. Cog does not search for the longest matching filename.

## Resolution

In order, first match wins:

1. `$COG_PLUGIN_DIR/cog-<name>`, when `COG_PLUGIN_DIR` is set and non-empty.
2. `command -v cog-<name>` against `$PATH`, in `$PATH` order.

A candidate is rejected unless, after symlink resolution, it is a regular file executable by the current user. A directory, a socket, a dangling symlink, or a non-executable file named `cog-<name>` is not a plugin: it is reported by `cog plugin list` and never run.

Empty `$PATH` components are ignored. `execvp` and `command -v` read an empty component as the current directory; cog does not, because a `cog-<name>` left in any directory the user cd's into would otherwise become a subcommand. This is the one intentional deviation from `command -v` semantics.

A directory whose path contains a newline is not searched. Cog's candidate lists are newline-delimited, so such a directory is unrepresentable rather than merely unsupported. `$PATH` itself cannot express one portably.

`COG_PLUGIN_DIR` is a single directory, not a list. It exists so a dedicated plugin directory can become the default later without a protocol change.

## Precedence

A first-party command always wins. Resolution is attempted only when `lib/commands/cmd_<derived>.sh` is not readable, where `<derived>` is `<name>` with dashes replaced by underscores.

There is no mechanism by which a plugin can replace, wrap, decorate, hide, or add a subcommand to a first-party command. A `cog-<name>` colliding with a first-party command is dead weight: `cog plugin list` reports it with state `shadowed-by-core` and cog never executes it.

## Invocation

Cog `exec`s the resolved path, replacing its own process. Consequences, all intentional:

- Remaining argv passes verbatim. Cog performs no flag parsing, no reordering, and no interpretation of anything after the plugin name.
- stdout and stderr are the plugin's, unfiltered.
- The plugin's exit status is cog's exit status, unmodified.
- A plugin crash, hang, or strict-mode abort affects one process. Cog is already gone.
- Cog's global flags are consumed before the command name and are never forwarded. A plugin needing verbosity reads `COG_*` from the environment.

## Environment

Cog exports exactly these variables and no others:

| Variable              | Value                                                                                     |
| --------------------- | ----------------------------------------------------------------------------------------- |
| `COG_PLUGIN_PROTOCOL` | Protocol version cog implements. `1` for this revision.                                   |
| `COG_HOST_VERSION`    | Cog's version string, as `cog --version` reports it.                                      |
| `COG_PLUGIN_NAME`     | The resolved `<name>`, without the `cog-` prefix.                                         |
| `COG_EXECUTABLE`      | Absolute path to the `cog` entry point, so a plugin can call back into the invoking host. |

Cog never exports a path to its own Bash sources, and never sets a variable that would make sourcing an internal file convenient. That omission is the ABI boundary.

Pre-existing `COG_*` variables in the caller's environment pass through untouched; cog does not scrub the environment.

## Metadata probe

A conformant plugin implements one reserved subcommand:

```console
$ cog-plan cog-plugin-metadata
{"protocol":1,"name":"plan","version":"0.4.0","summary":"Work with a plan-xp planning record","requires_cog":">=0.1.0"}
```

Requirements:

- Writes a single JSON object to stdout, exits `0`, and has no side effects — no files written, no network, no state changed, no prompting, no reading stdin.
- Completes within `probe_timeout_seconds` and emits at most `probe_output_cap_bytes`, both published in `data/plugin-protocol/protocol.yaml` and reported by `cog plugin host-info`. A probe that overruns is terminated, and ignoring the termination signal only delays it: the deadline is enforced, not requested.
- Fields: `protocol` (integer, required), `name` (string, required, must equal the filename's `<name>`), `version` (string, required), `summary` (string, required, one line), `requires_cog` (string, optional, a version constraint).
- Unknown fields are ignored, never rejected. That is what lets the schema grow without a deprecation cycle.

Cog runs the probe only from `cog plugin list`, `cog plugin info`, and `cog plugin validate`. Dispatch never probes. `cog plan next` execs directly; it pays no probe, and a plugin whose probe is broken still runs.

## Version negotiation

- `protocol` greater than `COG_PLUGIN_PROTOCOL` yields state `protocol-newer`; `validate` fails; dispatch still works, because a newer plugin speaking an older invocation contract is the normal forward case.
- `protocol` absent, unparseable, or a probe that fails for any reason yields state `metadata-unavailable`; `validate` fails; dispatch still works.
- `requires_cog` is advisory. Cog reports a mismatch in `info` and `validate` and does not block execution. The plugin owns its own compatibility decision, because only it knows which cog behavior it depends on. The supported grammar is a bare version or one of `>=`, `>`, `<=`, `<`, `=` followed by a version.

The governing rule is that a failed probe never prevents an otherwise valid plugin from running. The probe exists to make plugins inspectable, not to gate them.

## States

`cog plugin list` reports one row per candidate, each carrying one of these states. The full vocabulary is in `data/plugin-protocol/meta.yaml`.

A state is an inventory verdict; `cog plugin validate` is the conformance verdict. They apply the same metadata field contract and the same filename agreement, so `ok` never contradicts a passing `validate`. The one check `validate` adds is `probe_side_effect_free`, which `list` does not assert because it would mean auditing a temporary directory for every candidate on `$PATH`.

| State                  | Meaning                                                                                                                                              |
| ---------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------- |
| `ok`                   | Resolves, is executable, and its probe returned conformant metadata for a supported protocol.                                                        |
| `shadowed-by-core`     | A first-party command owns this name. Never executed.                                                                                                |
| `shadowed-by-path`     | An earlier candidate in resolution order wins. Never executed.                                                                                       |
| `not-executable`       | Found, but not a regular file executable by the current user.                                                                                        |
| `metadata-unavailable` | The probe failed, timed out, exceeded the cap, or returned metadata that is not one conformant JSON object naming this plugin. Dispatch still works. |
| `protocol-newer`       | Declares a protocol above this cog's. Dispatch still works.                                                                                          |

## Conformance checks

`cog plugin validate <path-or-name>` reports each check by name as `pass`, `fail`, or `skip`, and exits non-zero when any check fails. A check whose prerequisite failed is reported `skip` rather than `fail`, so the reported failure is the cause rather than its consequences.

Alongside the checks, `validate` reports `requires_cog` and `requires_cog_satisfied`, both `null` when the plugin declares no constraint. These are advisory and are not checks: an unsatisfied constraint is reported, and `ok` and the exit status are unmoved by it.

`ok` and the exit status always agree. For `validate` and `list` they report whether the command did its job, and so does `info` — a plugin whose probe failed is inspected successfully, and `state` is where its health is reported.

| Check                      | Asserts                                                                           |
| -------------------------- | --------------------------------------------------------------------------------- |
| `executable`               | The path is executable by the current user.                                       |
| `regular_file`             | After symlink resolution, the path is a regular file.                             |
| `name_matches_filename`    | The filename is `cog-<name>` for a valid `<name>`, and metadata `name` equals it. |
| `no_firstparty_collision`  | No `lib/commands` module owns this name.                                          |
| `metadata_exit`            | The probe exits 0.                                                                |
| `metadata_json`            | The probe emits one valid JSON object.                                            |
| `metadata_required_fields` | Every required field is present and correctly typed.                              |
| `protocol_supported`       | Declared protocol is at or below this cog's.                                      |
| `probe_within_timeout`     | The probe finished inside `probe_timeout_seconds`.                                |
| `probe_within_cap`         | Probe output did not exceed `probe_output_cap_bytes`.                             |
| `probe_side_effect_free`   | Run in an empty temporary working directory, the probe created nothing there.     |

## Help

- `cog --help` lists first-party commands only, byte-stable.
- `cog help <name>` and `cog --help <name>`, where `<name>` resolves to a plugin, invoke `cog-<name> --help` and pass its output and exit status through. Both spellings put the flag before the plugin name, where it is cog's.
- `cog <name> --help` and `cog <name> -h` are not delegation. A flag after the plugin name is argv, so it reaches the plugin unchanged along with everything following it, per Invocation. `cog <name> -h extra` runs `cog-<name> -h extra`.
- `cog plugin list` is where plugins are visible.

## Completion

- The checked-in command array in `completions/cog.bash` stays first-party-only.
- At top-level completion only, the completion function appends names from `cog plugin list --names`.
- Enumeration failure, a missing `cog`, or a slow response yields no plugin completions. It is never a shell error and never blocks first-party completion. Enumeration runs under its own hard time bound, so an unresponsive filesystem on `$PATH` costs the completion, not the shell.
- Nothing after `cog <plugin-name>` is completed by cog. A plugin that wants completion ships its own.

## Errors and exit codes

Two distinct regimes.

**Before `exec`**, failures are cog's and use cog's sysexits table:

| Situation                                            | Kind                  | Exit                  |
| ---------------------------------------------------- | --------------------- | --------------------- |
| No first-party module and no `cog-<name>` found      | `UnknownCommand`      | `EX_USAGE` (64)       |
| `cog-<name>` found but not a regular executable file | `PluginNotExecutable` | `EX_UNAVAILABLE` (69) |
| Name fails the slug rule                             | `BadCommandName`      | `EX_USAGE` (64)       |

**After `exec`**, the exit code is the plugin's alone. Cog does not remap it, does not read `69` as "unavailable", and adds nothing to stderr. A plugin exiting `64` means whatever that plugin says it means.

## What a plugin may and may not do

May:

- Invoke `cog <command>` and consume its `--json` output and exit codes.
- Read resource paths through cog's own lookup commands, for example `cog skill-refs path ...`.
- Ship anything it likes under its own name, anywhere its own installer chooses.

May not:

- Source `lib/functions/fn_*.sh`, `lib/commands/cmd_*.sh`, `lib/core.sh`, or `lib/helpers.sh`. These are private, unversioned, and actively churning.
- Write into `data/`, `skill-refs/`, `skills/`, or `agents/` under cog's installed tree. Mirror-mode install deletes anything cog did not ship, so files placed there are one `just install-sync` away from removal.
- Depend on cog's internal file layout, function names, or run-directory structure.

The contract is the CLI.
