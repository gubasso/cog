# Codex Single Entrypoint

Cog skills must spawn Codex through the runner wrapper only:

```bash
cog codex-runner run-exec
cog codex-runner run-resume
```

Skill instructions must not invoke `codex-session` directly. The wrapper owns
the supported command shapes, output capture, stderr capture, thread metadata,
and error classification.

`lib/functions/fn_codex.sh` is the source of truth for the real
`codex-session exec` and resume command lines. It is the only layer that should
build or run those direct calls.

`cog hook-guard codex-foreground` recognizes a Codex spawn only when the Bash
tool command contains `cog codex-runner run-exec` or
`cog codex-runner run-resume` at shell command position. Mentions of
`codex-session` as a path, package name, quoted string, or prose are not Codex
spawns for the guard.

`cog lint-codex-wrapper` enforces this invariant in markdown shell examples
under:

```text
skills/claude/*/SKILL.md
```
