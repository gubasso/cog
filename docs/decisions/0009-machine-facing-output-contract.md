# ADR-0009: Machine-facing output contract

## Context and Problem Statement

`cog` is called primarily by Claude/Codex skills, shell scripts, and other agent workflows. Its
output contract must be stable enough for those callers to parse, while still leaving room for
explicit human-UX when a command needs it.

## Considered Options

- Treat `cog` as human-facing by default.
- Let each command choose its own output posture.
- Declare `cog` machine-facing and centralize the output contract.

## Decision Outcome

Chosen option: **declare `cog` machine-facing**. Command output is machine-output by default:
structured stdout or JSON when requested/defaulted, BSD sysexits exit codes, stable error kinds, and
file-first log-messages. Human-UX is optional and opt-in, never the default contract.

Being machine-facing does **not** change the universal Unix stream contract: `stdout` carries only
the successful result, while errors, warnings, and diagnostics go to `stderr` with a non-zero exit
code (structured JSON for machine-output, prose for human-UX). Coding agents rely on that contract
(`2>/dev/null`, pipes, exit-code checks) exactly as humans do, so `cog` honors it always.

This references [ADR-0006](0006-loader-based-architecture.md) and
[ADR-0008](0008-skill-script-boundary.md). The general taxonomy lives in the `docs-n-notes`
repository under `tech/programming/cli-design/00-architecture.md` (section "Facing category &
message types").

`cog` already ships `help`, `doctor`, Bash completion, and man pages. Target state adds an `init`
surface for setup/scaffold/bootstrap. Existing human-message paths such as `cmd_msg.sh` are
acknowledged leakage to keep scoped behind explicit human-UX behavior.

## Consequences

- Good: skills and scripts can validate and compose `cog` output deterministically.
- Good: diagnostics remain available through XDG file logs and `doctor`.
- Bad: commands with friendly terminal output need extra care to keep it opt-in.

## Status

Accepted.
