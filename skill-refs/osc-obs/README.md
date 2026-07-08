# osc-obs reference index

Generic openSUSE Build Service (OBS) and `osc` reference content for the `osc-obs` skill. This tree
ships in-repo and resolves through `cog skill-refs path osc-obs/<file>`. It holds only generic,
portable OBS knowledge — no project-, host-, or account-specific data. Project-specific references
belong in the caller-supplied `$OBS_DOCS_DIR`.

## Contents

- [`auth-in-devcontainers.md`](auth-in-devcontainers.md) — Tier-1 remediation for the
  `creds_invalid` / `keyring_unavailable` auth classes: seeding a headless-friendly `oscrc`.

## Diagnostics source order

When a step lands on an unfamiliar error, branch point, or fix-and-retry loop, consult authoritative
sources before proposing a fix. Do not infer `osc` flag behavior, `.spec` macro semantics, OBS
resolver rules, or package versions from memory. Consult, in order:

1. `$OBS_DOCS_DIR/` if the caller supplied project-specific references.
2. This shipped `osc-obs/` reference tree (`cog skill-refs path osc-obs/...`).
3. The invoker-supplied runbook and its log directory.
4. `osc --help`, `osc <verb> --help`, `man osc`, and read-only API probes.
5. Upstream OBS/openSUSE/SUSE docs and the OBS web UI.
6. `rpm`, `.spec`, and macro references.

Cite the URL or local path in the structured output summary when it drove a decision.

## Common `osc` reference points

- Binary RPM names rarely equal source-package names (`libexpat1` ships from source `expat`); use
  `cog osc-probe-binary` and trust the returned `source_package`.
- `osc results --watch <project> <package>` is a server-side long-poll — prefer it over shell
  polling loops.
- `osc getbinaries`: the fifth positional is a single file, not a directory; use `-d <dir>`.
- `osc whoami` does not exist; use `osc -A "$OBS_API" api /person/<user>` or the preflight auth
  probe.

## Further reading (public, optional)

- `osc` documentation: <https://opensuse.github.io/osc/>
- OBS user guide: <https://openbuildservice.org/help/manuals/obs-user-guide/>
- openSUSE packaging guidelines: <https://en.opensuse.org/openSUSE:Packaging_guidelines>
