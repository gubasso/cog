# Write a cog plugin

This guide builds one working plugin end to end, runs it, breaks it on purpose, and reads what cog says about it. Every transcript below is real output from the commands shown.

A cog plugin is one executable file named `cog-<name>`. Cog finds it, `exec`s it, and gets out of the way. There is no manifest, no registry, and no install step on cog's side. The exact contract is [plugin protocol](../reference/plugin-protocol.md); why the seam has this shape is [plugins](../explanation/plugins.md).

## Start state

You need `cog` on `PATH` and a directory you can write to. The plugin itself can be written in any language that produces an executable file — this guide uses Bash because it is the shortest thing to read.

Ask cog what it promises before writing anything:

```console
$ cog plugin host-info
{
  "schema": "cog.plugin.host-info.v1",
  "ok": true,
  "protocol": 1,
  "host_version": "0.1.0",
  "executable": "/home/you/.local/bin/cog",
  "exported_environment": [
    "COG_PLUGIN_PROTOCOL",
    "COG_HOST_VERSION",
    "COG_PLUGIN_NAME",
    "COG_EXECUTABLE"
  ],
  "resolution_order": [
    "$COG_PLUGIN_DIR",
    "$PATH"
  ],
  "executable_prefix": "cog-",
  "reserved_subcommand": "cog-plugin-metadata",
  "probe_timeout_seconds": 2,
  "probe_output_cap_bytes": 65536
}
```

Those are the only numbers this guide depends on, and they come from the host rather than from this page.

## The whole contract, in four lines

1. The file is named `cog-<name>`, where `<name>` matches `^[a-z][a-z0-9_-]*$`.
2. The file is a regular file, executable by you.
3. `cog-<name> cog-plugin-metadata` prints one JSON object, exits `0`, and changes nothing.
4. Everything else is yours. Argv arrives verbatim, stdout and stderr are unfiltered, and your exit code becomes cog's exit code.

Rule 3 is the only thing cog asks you to implement. Rules 1 and 2 are about the filename.

## Step 1 — Choose a name that is free

A first-party command always wins. Cog looks for a plugin only after finding no module of its own, so a `cog-doctor` sitting next to cog's built-in `doctor` is dead weight — reported, never run.

Check before you commit to a name:

```console
$ cog plugin list --names
hello
```

`--names` prints one plugin name per line and is what shell completion consumes. Without it, `cog plugin list` prints JSON, because machine output is cog's default.

## Step 2 — Write the executable

Save this as `cog-hello`. It is a complete, conformant plugin.

```bash
#!/usr/bin/env bash
# cog-hello — a minimal conformant cog plugin.
set -euo pipefail

VERSION="0.1.0"

# The metadata probe. First thing the script does, before any setup, because it
# must be fast and must not touch anything.
if [[ ${1:-} == cog-plugin-metadata ]]; then
  printf '%s\n' "{\"protocol\":1,\"name\":\"hello\",\"version\":\"${VERSION}\",\"summary\":\"Greet a target, cog-style\",\"requires_cog\":\">=0.1.0\"}"
  exit 0
fi

case "${1:-}" in
  --help | -h)
    cat <<'USAGE'
Usage: cog hello [--json] [name]
Greets NAME (default: world).
USAGE
    exit 0
    ;;
  --version)
    printf '%s\n' "$VERSION"
    exit 0
    ;;
esac

json=false
[[ ${1:-} == --json ]] && {
  json=true
  shift
}
who="${1:-world}"

# Call back into the cog that invoked us, not whichever cog is first on PATH.
host="$("${COG_EXECUTABLE:-cog}" --version 2>/dev/null || echo unknown)"

if $json; then
  printf '{"schema":"cog.hello.v1","ok":true,"greeting":"hello, %s","host":"%s"}\n' "$who" "$host"
else
  printf 'hello, %s (via cog %s, protocol %s)\n' "$who" "$host" "${COG_PLUGIN_PROTOCOL:-?}"
fi
```

The metadata object has four required fields and one optional one:

| Field          | Required | Notes                                                      |
| -------------- | -------- | ---------------------------------------------------------- |
| `protocol`     | yes      | Integer. `1` today. Read it from `cog plugin host-info`.   |
| `name`         | yes      | Must equal the `<name>` in your filename.                  |
| `version`      | yes      | Your version, not cog's.                                   |
| `summary`      | yes      | One line.                                                  |
| `requires_cog` | no       | Advisory only. Cog reports a mismatch and runs you anyway. |

Unknown fields are ignored rather than rejected, so adding your own key is safe.

## Step 3 — Make it findable

```console
$ chmod +x cog-hello
$ export COG_PLUGIN_DIR="$PWD"
```

Cog resolves in exactly two places, first match wins: `$COG_PLUGIN_DIR/cog-<name>`, then `cog-<name>` on `$PATH` in `$PATH` order. `COG_PLUGIN_DIR` is a single directory, not a list. Dropping the file anywhere on `$PATH` works equally well and needs no variable.

## Step 4 — Prove it conforms

`cog plugin validate` is the verb that turns "conformant" from an opinion into a check. Run it before you ship, and run it in your own CI.

```console
$ cog plugin validate ./cog-hello
{
  "schema": "cog.plugin.validate.v1",
  "ok": true,
  "path": "/home/you/plugins/cog-hello",
  "name": "hello",
  "checks": {
    "executable": "pass",
    "regular_file": "pass",
    "name_matches_filename": "pass",
    "no_firstparty_collision": "pass",
    "metadata_exit": "pass",
    "metadata_json": "pass",
    "metadata_required_fields": "pass",
    "protocol_supported": "pass",
    "probe_within_timeout": "pass",
    "probe_within_cap": "pass",
    "probe_side_effect_free": "pass"
  },
  "failures": [],
  "requires_cog": ">=0.1.0",
  "requires_cog_satisfied": true
}
```

`validate` takes a path or an installed name, so `cog plugin validate hello` works once the file is findable. Exit status agrees with `ok`: `0` when every check passes, non-zero otherwise.

## Step 5 — Run it

```console
$ cog hello Gustavo
hello, Gustavo (via cog 0.1.0, protocol 1)

$ cog hello --json Gustavo
{"schema":"cog.hello.v1","ok":true,"greeting":"hello, Gustavo","host":"0.1.0"}
```

Your exit code is cog's exit code, untouched. A plugin that exits `3` makes `cog <name>` exit `3`:

```console
$ cog boom; echo "exit=$?"
exit=3
```

Cog does not remap it, does not read `69` as "unavailable", and adds nothing to stderr. After the `exec`, cog is already gone.

### Two spellings of help, and only one delegates

```console
$ cog help hello
Usage: cog hello [--json] [name]
Greets NAME (default: world).
```

`cog help hello` and `cog --help hello` put the flag before the plugin name, where it belongs to cog, so cog delegates by invoking `cog-hello --help`.

`cog hello --help` is not delegation. Anything after the plugin name is argv and reaches you unchanged, exactly like `cog hello -h extra` runs `cog-hello -h extra`. Handle `--help` yourself, as the example above does, and both spellings work.

Plugins never appear in `cog --help`, which is asserted byte-equal against a snapshot. `cog plugin list` is where plugins are visible.

## What cog hands your plugin

Four environment variables, and nothing else:

```console
$ cog plugin info hello --json
{
  "schema": "cog.plugin.info.v1",
  "ok": true,
  "name": "hello",
  "path": "/home/you/plugins/cog-hello",
  "state": "ok",
  "metadata": {
    "protocol": 1,
    "name": "hello",
    "version": "0.1.0",
    "summary": "Greet a target, cog-style",
    "requires_cog": ">=0.1.0"
  },
  "requires_cog_satisfied": true,
  "candidates": [
    "/home/you/plugins/cog-hello"
  ],
  "environment": {
    "COG_PLUGIN_PROTOCOL": "1",
    "COG_HOST_VERSION": "0.1.0",
    "COG_PLUGIN_NAME": "hello",
    "COG_EXECUTABLE": "/home/you/.local/bin/cog"
  }
}
```

`cog plugin info` shows the environment your plugin would receive without running it, which makes it the fastest way to debug a resolution problem.

Notably absent from that list is any path into cog's Bash sources. That omission is the ABI boundary, and it is deliberate. `COG_EXECUTABLE` exists so you can call back into the cog that invoked you rather than whichever `cog` happens to be first on `PATH`.

Cog's own global flags are consumed before the command name and are never forwarded. A plugin that wants verbosity reads `COG_*` from the environment. Pre-existing `COG_*` variables pass through untouched.

## The probe rule that catches everyone

The metadata probe must be fast, small, and side-effect-free. `validate` enforces the last one literally: it runs your probe in an empty temporary directory and checks that nothing was created there.

```console
$ cog plugin validate ./cog-dirty
{"ok":false,"failures":["probe_side_effect_free"]}
```

That plugin's only sin was touching a cache file before printing its metadata.

The probe is **not a gate**. If it times out, exits non-zero, or emits garbage, `cog plugin list`, `info`, and `validate` report the problem — and `cog <name>` still runs:

```console
$ cog oops
ran anyway
```

Dispatch never probes at all. It `exec`s directly, so a plugin invocation pays no fork and no timeout. Gating dispatch on the probe would turn every plugin author's bug into a cog outage.

The practical rule: put the `cog-plugin-metadata` branch at the very top of your program, before argument parsing, before config loading, before anything that opens a file or a socket. Print, exit, done.

## When something is wrong

`cog plugin list` gives one row per candidate with a state. Read the state first.

```console
$ cog plugin list | jq -c '.plugins[]|{name,state,shadowed_by}'
{"name":"doctor","state":"shadowed-by-core","shadowed_by":"lib/commands/cmd_doctor.sh"}
{"name":"hello","state":"ok","shadowed_by":null}
{"name":"nox","state":"not-executable","shadowed_by":null}
{"name":"oops","state":"metadata-unavailable","shadowed_by":null}
```

| State                  | What happened                                 | Fix                                                                      |
| ---------------------- | --------------------------------------------- | ------------------------------------------------------------------------ |
| `ok`                   | Resolves, runs, probe conformant.             | Nothing.                                                                 |
| `shadowed-by-core`     | A first-party command owns the name.          | Rename your plugin. Nothing else can work.                               |
| `shadowed-by-path`     | An earlier candidate wins resolution.         | `shadowed_by` names the winner. Reorder, or rename.                      |
| `not-executable`       | Found, but not a regular executable file.     | `chmod +x`, or resolve the dangling symlink.                             |
| `metadata-unavailable` | Probe failed, timed out, or emitted bad JSON. | Run `cog plugin validate` and read `failures`. Dispatch works meanwhile. |
| `protocol-newer`       | You declared a protocol above this cog's.     | Expected when the plugin is ahead. Dispatch works.                       |

When a check fails, `validate` names the cause rather than its consequences — downstream checks report `skip`, not `fail`:

```console
$ cog plugin validate ./cog-oops
{
  "checks": {
    "metadata_json": "fail",
    "metadata_required_fields": "skip",
    "protocol_supported": "skip",
    ...
  },
  "failures": [
    "metadata_json"
  ]
}
```

One failure, `metadata_json`. The two `skip`s are not separate problems.

### Errors before the exec are cog's

Two failures happen while cog is still in control, and they use cog's exit codes:

```console
$ cog nosuchthing
cog: unknown command
  err.kind: UnknownCommand
  where: command: nosuchthing
  why: no readable command module and no executable cog-nosuchthing on $COG_PLUGIN_DIR or $PATH
  hint: check the command name, or install the plugin that provides it
exit=64

$ cog nox
cog: plugin is not executable
  err.kind: PluginNotExecutable
  where: command: nox
  why: cog-nox was found but is not a regular file executable by the current user
  hint: run 'cog plugin list' to see why, then make it executable
exit=69
```

Once the `exec` happens, every exit code is yours.

## What you may and may not do

May:

- Invoke `cog <command>` and consume its `--json` output and exit codes.
- Read shared prose through cog's own lookups, such as `cog skill-refs path ...`.
- Ship anything you like under your own name, installed however you choose.

May not:

- Source `lib/functions/fn_*.sh`, `lib/commands/cmd_*.sh`, `lib/core.sh`, or `lib/helpers.sh`. Private, unversioned, and actively churning.
- Write into `data/`, `skill-refs/`, `skills/`, or `agents/` in cog's installed tree. Mirror-mode install deletes anything cog did not ship, so those files are one `just install-sync` from deletion.
- Depend on cog's internal file layout, function names, or run-directory structure.

Plugins extend the command surface only. They contribute no skills, no skill-refs, and no `data/` tables — see [plugins](../explanation/plugins.md) for why, and [open questions](../plan/open-questions.md) for whether that ever changes.

The contract is the CLI.

## Ship it

Cog never installs, downloads, updates, or catalogues a plugin, and makes no trust claim about one. Distribution is your project's business, exactly as krew installs kubectl plugins without kubectl knowing krew exists.

A reasonable shape:

1. Ship the `cog-<name>` file in your own package, on your own release cadence.
2. Install it into any directory on the user's `$PATH`.
3. Run `cog plugin validate <path>` in your CI, so a metadata regression fails your build rather than your users'.
4. Ship your own shell completion if you want one. Cog completes nothing after `cog <name>`.

## Next

- [Plugin protocol](../reference/plugin-protocol.md) — the exact contract, sufficient to implement against without reading this guide.
- [Plugins](../explanation/plugins.md) — why the seam is a separate process, and why the probe is not a gate.
- [ADR-0034](../decisions/ADR-0034-extend-cog-through-external-executables.md) — the decision record.
