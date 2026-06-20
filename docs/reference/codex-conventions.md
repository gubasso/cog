# Codex Conventions Maintenance Reference

Maintenance-time only. This reference is not loaded at runtime by skills or commands.

This page records the Codex orchestration conventions that `cog` maintainers need when changing the
Codex runner implementation. Runtime behavior is owned by `cog`, primarily
[`lib/functions/fn_codex.sh`](../../lib/functions/fn_codex.sh) and
[`lib/commands/cmd_codex_runner.sh`](../../lib/commands/cmd_codex_runner.sh).

## Source of Truth

Codex invocations go through `codex-session`. Each orchestration call must pass an explicit
`--profile`; `codex-session` does not inject one. Profile data lives outside this repository under
the user's `codex-session` configuration, while model and effort policy for shipped skills is
documented in [Model/effort policy](model-effort-policy.md).

`cog` owns the command construction and status interpretation used by shipped skills:

- `cog codex-runner run-exec`
- `cog codex-runner run-resume`
- `cog codex-runner orientation <read-only|write>`
- `cog codex-runner explain-status <status>`

Do not duplicate those mechanics in skill prose. Skills should call the `cog codex-runner` surfaces
and keep sequencing or judgment in the skill body.

## Runtime-Owned Behavior

The following behavior is intentionally implemented in `lib/functions/fn_codex.sh`, not in this
document:

- Exec and resume argv construction.
- Native read-only sandbox, disk-full-read-access fallback, quick-auto, and danger modes.
- Output/status classification such as `ok`, `empty-output`, `quota-75`, `resume-blocked`,
  `timeout-124`, `sigterm`, and `nonzero`.
- Read-only and write prompt orientation text.
- Human-readable status explanations for retry and recovery decisions.

When these conventions change, update the function implementation, tests, generated command
references, and this maintenance note together.

## Operational Constraints

Every non-interactive Codex call must be foregrounded and must not inherit interactive stdin. A
foreground call lets the orchestrator classify completion deterministically from exit code, stderr,
events, and final-message output. Backgrounding a Codex call breaks workflow sequencing and can
leave later stages unrun.

Resume calls are account-bound because the thread exists in the owning account's `CODEX_HOME`.
`resume-blocked` is a quota state on the owner, not a missing-thread error. Recovery is either to
wait for the owner reset and retry the resume, or deliberately start a fresh exec with no transcript
continuity.

For workflows that resume across access-mode boundaries, use one compatible Codex invocation mode
for the whole thread and enforce read-only or write behavior through the orientation emitted by
`cog codex-runner orientation`.

## Maintenance Checklist

- Keep direct Codex command construction in `cog codex-runner`.
- Keep status names and explanations synchronized with `cog::fn::codex_known_statuses` and
  `cog::fn::codex_explain_status`.
- Keep generated help, command reference docs, completions, and man-page mirrors synchronized when
  command surfaces change.
- Keep skill bodies free of copied orientation blocks or bespoke Codex retry mechanics.
