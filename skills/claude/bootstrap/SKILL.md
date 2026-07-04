---
name: bootstrap
description: >
  Scaffold or update a project's baseline configuration by interviewing the operator once
  and dispatching the bootstrap-* config skills (pre-commit, editorconfig, nix devshell,
  repo starter, CI workflow, taskrunner) as parallel fresh-context workers. Runs on a brand
  new project or an existing one, filling in what is missing. Use when the user says
  "bootstrap", "project bootstrap", "bootstrap a project", "scaffold a new project", or
  "set up a project".
argument-hint: "[project-dir] <what to set up / free-form intent>"
disable-model-invocation: true
allowed-tools: Bash Read Write Edit Agent Skill AskUserQuestion Grep Glob
model: opus
effort: low
---

<!-- trigger-tests: "bootstrap", "project bootstrap", "bootstrap a project", "scaffold a new project", "set up a project" -->
<!-- cog-skill: input-fidelity -->

# Bootstrap

Scaffold a project's baseline tooling by interviewing the operator once, then dispatching the
`bootstrap-*` config skills as parallel fresh-context workers. This orchestrator owns the interview,
per-worker orientation, dispatch sequencing, and postcondition verification; each worker owns its own
config domain and its deterministic `cog` mechanics. It runs on a new project or an existing one —
detecting what is already present and setting up only what is missing.

The dispatchable workers are `bootstrap-precommit`, `bootstrap-editorconfig`, `bootstrap-nix`,
`bootstrap-repo`, `bootstrap-ci`, and `bootstrap-taskrunner`.

<!-- cog-context-brief-gate -->

**Context-brief gate.** Before `/bootstrap` dispatches to any fresh-context worker — an Agent subagent
or a `cog codex-runner` Codex job — build its input as a validated context brief from your whole
accumulated raw context: attach the raw request as-is, author an oriented objective, carry the full
substance and load-bearing artifacts, and omit your own verdict. Build the brief with `cog
context-brief build` and confirm it with `cog context-brief validate` before dispatch.

## Inputs

`$ARGUMENTS` is an optional target project directory (default: the current working directory) plus
free-form intent describing what to set up. The intent orients the interview; it is never assumed to be
complete.

## Phase A: Audit and interview

First establish the deterministic present/missing baseline across every domain in one call:

```bash
cog bootstrap-audit --json
```

Each `domains[]` row reports `domain`, `present`, the per-artifact `artifacts` breakdown, and
`requires_question`. This matrix is the authoritative scope: **every domain with `present=false` is in
scope.** Free-form intent **orients** the interview but never **shrinks** this set — an example domain
("set up what's missing, e.g. nix") names one instance, not the whole list.

Interview the operator with `AskUserQuestion` — this orchestrator is the only interactive component, and
asking here is expected. Ground every question in the audit matrix and resolve:

- Any missing domain the operator explicitly opts **out** of. Absent an explicit opt-out, every
  `present=false` domain stays in scope.
- The destructive-change policy (overwrite, merge, skip) for any `present=true` domain the operator
  still wants re-run.
- Language/runtime specifics that the workers cannot infer.
- License SPDX id, holder, and year whenever the `repo` row reports `requires_question=true` (asked,
  never silently defaulted).
- CI target whenever the `ci` row reports `requires_question=true` (no github/gitlab remote detected).
- Taskrunner preference (default `just`; `make` only when a `Makefile` already exists).

If the intent already answers a question, confirm rather than re-ask.

## Phase B: Run directory and per-worker briefs

Open a run directory for every scratch and intermediate artifact this orchestration produces. Obtain it
the canonical way and substitute the literal path it echoes into the commands below — scratch never
lands in the project tree or CWD:

```bash
RUN_DIR="$(cog rundir bootstrap | sed -n 's/^RUN_DIR=//p')"
[ -n "$RUN_DIR" ] || { echo "ERROR: cog rundir did not emit RUN_DIR" >&2; exit 1; }
```

Write the raw request to `$RUN_DIR/request.md`. Gather per-worker orientation by running each in-scope
domain's detector against the project, so each brief carries the true starting state:

```bash
cog classify-project --json
cog precommit-detect --json
cog editorconfig-detect --json
cog nix-devshell-detect --json
cog gitignore-detect --json
cog ci-detect --json
cog taskrunner-detect --json
```

Then build one validated context brief per in-scope worker under `$RUN_DIR`. Assemble each brief inline
with the `context-builder` skill, carrying the operator's answers as precise orientation, the raw
request attached as-is, and the full substantive context and detector findings that bear on that worker
— omitting your own proposed solution:

```bash
cog context-brief template --out "$RUN_DIR/brief-body-<worker>.md"
# fill the body for that worker, then:
cog context-brief build --request "$RUN_DIR/request.md" --body "$RUN_DIR/brief-body-<worker>.md" --out "$RUN_DIR/brief-<worker>.md"
cog context-brief validate "$RUN_DIR/brief-<worker>.md"
```

## Phase C: Dispatch in dependency-aware waves

Dispatch the selected workers as foreground Agent subagents (env-first, no backgrounding; respect the
fixed 5-level subagent depth budget). Assign every shared output path exactly one owning writer per run:
`bootstrap-repo` is the sole writer of `.gitignore` and receives any ignore fragments other workers need
through its brief.

- **Wave 1 (independent):** `bootstrap-editorconfig`, `bootstrap-nix`, `bootstrap-repo`.
- **Wave 2 (consume Wave 1):** `bootstrap-precommit` (reads the established `.editorconfig` baseline),
  `bootstrap-ci` and `bootstrap-taskrunner` (reuse the flake devshell and task names).

Give each subagent its validated brief as the complete orientation. After each wave, verify the durable
postcondition by re-running `cog bootstrap-audit --json` and confirming every dispatched domain now
reports `present=true` (or was intentionally opted out), and that each touched `SKILL.md` lints clean,
before starting the next wave.

## Phase D: Reconcile and report

Re-run `cog bootstrap-audit --json` as the final postcondition: every in-scope domain must now report
`present=true`. Summarize what each worker produced, list follow-ups (`nix flake lock` on a nix host,
`pre-commit install`, `direnv allow`), and surface any conflicts or still-missing domains that need an
operator decision.

## Guardrails

- The orchestrator is the only interactive component; workers never interview.
- The audit's `present=false` set is the authoritative scope; an example domain in the intent never
  shrinks it.
- Scratch and intermediate artifacts live under the `cog rundir bootstrap` directory; never write them
  into the project tree or CWD.
- Keep the interview, brief-building, and dispatch foreground; never background them.
- Deterministic mechanics stay behind `cog` subcommands and the worker skills.
- Do not run git commands unless the operator authorizes it.
- Verify a durable postcondition at every wave boundary.
