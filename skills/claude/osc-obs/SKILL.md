---
name: osc-obs
description: Single high-level surface for `osc` (openSUSE build service) operations against an OBS home/test project configured by the invoker. Delegates deterministic OBS/osc preflight and binary-to-source probing to the cog CLI while preserving runbook execution, diagnostics, and OBS judgment in prose. Use whenever the user asks to run an `osc` verb, watch a build, branch from upstream, inspect a buildroot/buildinfo/buildlog, or drive a per-lane runbook. Triggers on phrases like "osc", "osc results", "osc buildlog", "osc buildinfo", "check the buildroot", "watch the build", "branch from upstream", "branch from Factory", "run the runbook".
model: opus
effort: low
---

<!-- trigger-tests: "osc", "osc results", "osc buildlog", "watch the build", "branch from upstream" -->

# osc-obs - OBS operations skill

runbook-execute helper extraction is DEFERRED because it is high-risk, environment-sensitive,
network-dependent, and requires real OBS credentials.

## Scope

This is the generic, portable OBS skill. It reads configuration from environment variables so the
same skill can drive any OBS overlay project. Per-project copies may hard-code constants, but this
generic version stays environment-driven.

The skill's generic OBS reference content lives at `~/DocsNNotes/tech/tools/osc-obs/`. Project-
specific references may be supplied through `$OBS_DOCS_DIR`.

Per-lane runbooks are inputs to the skill. They are not skill-owned and are not edited
unilaterally.

## Configuration

| Variable           | Required | Default                    | Purpose                                                         |
| ------------------ | -------- | -------------------------- | --------------------------------------------------------------- |
| `OBS_API`          | no       | `https://api.opensuse.org` | OBS API URL. Passed as `-A` to every `osc` invocation.          |
| `OBS_HOME_PROJECT` | yes      | none                       | Home/test project namespace, such as `home:<user>:<proj>-test`. |
| `OBS_WORKSPACE`    | no       | `~/Projects/_obs-work/`    | Host path where `osc co` checkouts live.                        |
| `OBS_DOCS_DIR`     | no       | none                       | Project-specific reference docs subtree.                        |

If `$OBS_HOME_PROJECT` is unset, preflight stops. The skill does not guess project namespaces.

## Edit Fence

You may only edit files under:

- `$OBS_WORKSPACE/$OBS_HOME_PROJECT/`
- `$OBS_DOCS_DIR/` if set
- the log directory supplied by the invoker for the current runbook run

All other paths are off-limits, including the consumer project's source tree, user-owned
configuration, and generic DocsNNotes paths outside `~/DocsNNotes/tech/tools/osc-obs/`, except where
this skill explicitly says to persist reusable generic findings.

If a step asks you to edit outside the allowed roots, stop and surface the issue to the user.

## Agent-helper Contract

`cog` must be installed and on `PATH`; a bare call fails
legibly if it is missing. Create the run directory and output paths:

```bash
RUN_DIR="$(cog rundir osc-obs | sed -n 's/^RUN_DIR=//p')"
PREFLIGHT_JSON="$RUN_DIR/preflight.json"
PROBE_JSON="$RUN_DIR/probe.json"
```

Run preflight before any `osc` operation:

```bash
cog osc-preflight "$PREFLIGHT_JSON"
```

Probe binary RPM names before `osc branch`:

```bash
cog osc-probe-binary --binary "$BINARY_RPM" --project "$SOURCE_PROJECT" "$PROBE_JSON"
```

If `osc-preflight` exits non-zero, stop. Surface `.reason` and the checks whose `status` is not
`pass`. If `.checks.auth_probe.details.auth_class` is present, map it to the remediation below:

- `creds_invalid`: re-seed the `oscrc` per
  `~/DocsNNotes/tech/tools/osc-obs/auth-in-devcontainers.md`, Tier 1.
- `keyring_unavailable`: use a headless-friendly `oscrc` with
  `credentials_mgr_class = osc.credentials.ObfuscatedConfigFileCredentialsManager`.
- `network`: check network egress, proxy, DNS, TLS, or firewall before any further step.

Never respond to auth failures by running or suggesting interactive `osc user` inside this skill.

If `osc-probe-binary` exits non-zero, refuse to branch and escalate rather than guessing a source
package.

## Helper Schemas

`osc-preflight`:

```json
{
  "ok": false,
  "api": "https://api.opensuse.org",
  "home_project": "home:user:test",
  "workspace": "/home/user/Projects/_obs-work",
  "osc_path": null,
  "oscrc": "/home/user/.config/osc/oscrc",
  "checks": {
    "env": {
      "status": "pass",
      "ok": true,
      "required": true,
      "reason": null,
      "remediation": null,
      "details": {}
    },
    "osc_binary": {},
    "credentials": {},
    "auth_probe": {},
    "workspace": {},
    "home_project": {},
    "obs_build": {}
  },
  "reason": "missing OBS_HOME_PROJECT"
}
```

Each check object has:

```json
{
  "status": "pass",
  "ok": true,
  "required": true,
  "reason": null,
  "remediation": null,
  "details": {}
}
```

`osc-probe-binary`:

```json
{
  "ok": true,
  "api": "https://api.opensuse.org",
  "binary": "libexpat1",
  "project": "openSUSE:Factory",
  "osc_path": "/usr/bin/osc",
  "query_path": "/search/published/binary/id?match=@name=\"libexpat1\"+and+@project=\"openSUSE:Factory\"",
  "probe": {
    "status": "pass",
    "exit_code": 0,
    "reason": null,
    "stderr": ""
  },
  "matches": [
    {
      "binary": "libexpat1",
      "package": "expat",
      "project": "openSUSE:Factory"
    }
  ],
  "source_package": "expat",
  "source_differs": true,
  "reason": null
}
```

## Supported Verbs

Route these `osc` verbs through this skill after preflight passes:

```text
branch, co, up, ci, vc, status, diff, revert, meta prj, meta pkg, results, buildinfo,
buildlog, getbinaries, rebuild, rdelete
```

Every direct `osc` command in prose must pass the configured API:

```bash
osc -A "$OBS_API" <verb> ...
```

## Generic Operation Rules

Apply these rules to every OBS workflow this skill drives.

### Watching Builds

For any rebuild that takes more than a few seconds:

```bash
osc -A "$OBS_API" results --watch <project> <package>
```

Never poll `osc results` in a shell loop. `--watch` is a server-side long-poll and is safe to detach
with Ctrl-C.

### Before Branching

Binary RPM names rarely equal source-package names. `libexpat1` ships from source package `expat`.
`python311-setuptools` is a binary subpackage of source `python-setuptools`.

Use `cog osc-probe-binary` first. The returned `source_package` is authoritative. If it
differs from the binary name, use the four-argument branch form:

```bash
osc -A "$OBS_API" branch <src-prj> <src-pkg> "$OBS_HOME_PROJECT" <binary-name>
```

### Build-state Interpretation

| State                                   | Class                       | Action                                       |
| --------------------------------------- | --------------------------- | -------------------------------------------- |
| `succeeded` / `failed` / `unresolvable` | terminal                    | branch on it via the runbook                 |
| `building` / `scheduled` / `outdated`   | in-flight                   | wait via `osc results --watch`               |
| `blocked: <dep>`                        | transient                   | wait; do not `osc rebuild`                   |
| `broken`                                | pre-build link/source drift | recover; never branch as if it were terminal |

`blocked: <dep>` usually clears when the dependency republishes. Default to wait. Escalate only
after checking job history and the project references.

`broken` is pre-build. The resolver and build did not run. Recovery is usually the `osc add <new>` +
`osc rm <old>` + `osc ci` sequence inside the OBS workspace.

### Before Rebuild

When a dependency republishes, OBS usually auto-rebuilds consumers. An unconditional rebuild can
cancel an in-flight auto-rebuild. Check state first:

```bash
state=$(osc -A "$OBS_API" results <prj> <pkg> --csv \
  | awk -F';' -v r=<repo> -v a=<arch> '$1==r && $2==a {print $4}')
case "$state" in
  building|scheduled|blocked:*) echo "in flight; skip rebuild" ;;
  *)                            osc -A "$OBS_API" rebuild <prj> <pkg> <repo> <arch> ;;
esac
```

### Before Tightening BuildRequires

Probe every lane where the dependency will fire:

```bash
osc -A "$OBS_API" api \
  '/build/'"$OBS_HOME_PROJECT"'/<lane>/<arch>/_repository?view=binaryversions&binary=<binary-rpm>&withevr=1'
```

If any lane reports `error="not available"`, do not commit. Scope the requirement down or publish
the provider on the missing lane first.

### Common Foot-guns

- `osc getbinaries`: the fifth positional is a single file, not a destination directory. Use
  `-d <dir>`.
- `osc results`: use `-v` when you need the human-readable failure reason.
- `osc whoami` does not exist. Use the helper preflight auth probe or
  `osc -A "$OBS_API" api /person/<user>`.
- Patch rename in `_link.apply`: `osc add <new>` and `osc rm <old>` must land in the same commit.

## Diagnostics Protocol

When a step lands on an unfamiliar error, branch point, or fix-and-retry loop, consult
authoritative sources before proposing a fix. Do not infer `osc` flag behavior, `.spec` macro
semantics, OBS resolver rules, or package versions from memory.

Consult sources in this order:

1. `$OBS_DOCS_DIR/` if supplied.
2. `~/DocsNNotes/tech/tools/osc-obs/`.
3. Invoker-supplied runbook and log directory.
4. `osc --help`, `osc <verb> --help`, `man osc`, and read-only API probes.
5. Upstream OBS/openSUSE/SUSE docs and the OBS web UI.
6. rpm, spec, and macro references.

Cite the URL or local path in the structured output summary when it drove the decision.

## Persisting Findings

Always record the source URL or local path in the run's closing log next to the decision it
informed.

Reusable generic findings may be appended to `~/DocsNNotes/tech/tools/osc-obs/<topic>.md` and the
subtree index. Project-specific findings go to `$OBS_DOCS_DIR/<topic>.md` when set.

## Structured Output

For every `osc` command executed on the user's behalf, end the response with:

```jsonc
{
  "outcome": "succeeded | unresolvable | failed | in_progress | other",
  "summary": "one-line human description",
  "branch_points": ["matches a runbook Branch points label"],
  "raw_excerpt": "first/last N lines of raw osc output for fallback diagnosis"
}
```

On `outcome: "other"`, refuse to branch and surface the issue for escalation.

## Per-runbook Loop Contract

Runbook execution remains prose in this skill.

1. Run `cog osc-preflight`. If it fails, stop and surface the remediation.
2. Read the runbook front-to-back once.
3. Confirm the invoker supplied a log directory. Ask if missing.
4. Before executing a step, list the log directory and read prior runs for the same lane.
5. Execute each `## Step N` using the supported verbs and generic operation rules.
6. If a repeated `{step, failure-signature}` pair appears, do not repeat the same edit. Choose a
   different strategy, consult references, or escalate.
7. Close with structured output and a log entry containing commands, outcomes, branch points,
   references consulted, and remaining risks.

## Guardrails

- Preflight is mandatory before any `osc` operation.
- The helper is detect-only. It never installs packages, creates credentials, runs `osc user`, or
  creates the OBS workspace.
- The skill does not branch from guessed package names.
- The skill does not self-provision home projects.
- The skill does not run `osc` without `-A "$OBS_API"`.
