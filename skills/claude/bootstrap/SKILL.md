---
name: bootstrap
description: >
  Scaffold or update a project's baseline configuration by interviewing the operator once
  and dispatching the bootstrap-* config skills (pre-commit, editorconfig, nix devshell,
  repo starter, governance docs, CI workflow, taskrunner) as parallel fresh-context workers. Runs on a brand
  new project or an existing one; every run refreshes the reviewed templates and reconciles each
  selected domain — installing what is absent and applying improvements to what is present. Use
  when the user says "bootstrap", "project bootstrap", "bootstrap a project", "scaffold a new
  project", or "set up a project".
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
every run refreshes the reviewed templates and reconciles each selected domain, installing what is
absent and applying improvements to what is present. Every worker follows the shared refresh routine at
`$(cog skill-refs path bootstrap/template-refresh-routine.md)`.

The dispatchable workers are `bootstrap-precommit`, `bootstrap-editorconfig`, `bootstrap-nix`,
`bootstrap-repo`, `bootstrap-governance`, `bootstrap-ci`, and `bootstrap-taskrunner`.

`bootstrap-rust` is a conditional **language** worker rather than a domain: it is dispatched only when
the project is Rust (per `cog classify-project`) or the operator's intent is a new Rust project. It owns
the Rust crate skeleton (`Cargo.toml`, `src/`) plus optional rust config, and is intentionally **not**
part of `cog bootstrap-audit` — the audit's every-domain-in-scope matrix stays language-orthogonal, so
rust never reads as a "missing" domain on a non-rust project.

`bootstrap-cargo-publish` is a conditional **Rust + publishing** worker, dispatched only when the
project is Rust (per `cog classify-project`) **and** the operator's intent involves publishing or
release setup (crates.io, `cargo publish`, `release-plz`, `cargo-release`, `cargo dist`, `publish`,
`release`). Like `bootstrap-rust` it is not a `bootstrap-audit` domain, keeping the audit matrix
language-orthogonal.

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

Each `domains[]` row reports `domain`, `present`, the per-artifact `artifacts` breakdown,
`requires_question`, and the machine-explicit scope fields `default_in_scope`, `default_action`
(`install` when `present=false`, `reconcile` when `present=true`), and `requirements_satisfied`. This
matrix is the authoritative scope: **every domain is in scope by default, dispatched in its
`default_action` mode**, unless the operator explicitly opts it out. Free-form intent **orients** the
interview but never **shrinks** this set — an example domain ("set up what's missing, e.g. nix") names
one instance, not the whole list. Read each domain's `default_action` rather than re-deriving it.

Interview the operator with `AskUserQuestion` — this orchestrator is the only interactive component, and
asking here is expected. Ground every question in the audit matrix and resolve:

- Any domain the operator explicitly opts **out** of. Absent an explicit opt-out, every domain stays in
  scope in its `default_action` mode — a present domain reconciles rather than being skipped.
- The conflict policy (overwrite, merge, skip) for any domain whose worker may need overwrite authority
  to apply improvements. Reconcile never becomes an unprompted destructive overwrite; present domains no
  longer need an opt-in to run.
- Language/runtime specifics that the workers cannot infer.
- License SPDX id, holder, and year whenever the `repo` row reports `requires_question=true` (asked,
  never silently defaulted).
- CI target whenever the `ci` row reports `requires_question=true` (no github/gitlab remote detected).
- Taskrunner preference (default `just`; `make` only when a `Makefile` already exists).

If the intent already answers a question, confirm rather than re-ask. The template review runs on a
default 14-day freshness window, applied when a worker stamps a review (a review stays fresh until its
recorded date plus the window); the operator may choose a longer window (e.g. 30 days) for a looser
re-review cadence, carried in each worker's brief so its stamp uses it.

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
cog cargo-detect --json          # when classify-project reports Rust (drives bootstrap-rust)
cog cargo-publish-detect --json  # when Rust plus publishing intent is in scope (drives bootstrap-cargo-publish)
cog precommit-detect --json
cog editorconfig-detect --json
cog nix-devshell-detect --json
cog gitignore-detect --json
cog governance-detect --json
cog ci-detect --json
cog taskrunner-detect --json
```

When `classify-project` reports Rust — or the intent is a new Rust project — include `bootstrap-rust`
in the dispatch and build its brief from `cog cargo-detect` (scaffold state, crate kind, and how cargo
is reachable). When the project is Rust **and** the intent involves publishing or release setup, also
include `bootstrap-cargo-publish` and build its brief from `cog cargo-publish-detect` (crate kind,
publishability, CI provider, release tool, semver tooling, and binary-distribution hints) plus the
operator's publishing intent and any known CI target and taskrunner type.

Once a domain's detector resolves its template type, capture the template-review freshness so the
worker can skip re-research when a recent review already covers this domain and type, and fold that JSON
into the worker's brief:

```bash
cog bootstrap-template-review check --domain <domain> --type "$TYPE" --json
```

Each row reports `review.state` (fresh/stale/missing/invalid), `review.fresh`, the cached `summary`, and
the `skill_refs` origin/writability that tells the worker whether a template write lands in the tracked
repo or the installed, uncommitted tree.

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
`bootstrap-repo` is the sole writer of `.gitignore` during the waves and receives any ignore fragments
other workers need through its brief. Cross-domain ignore fragments that outlive a worker's scope — the
nix devshell's `.direnv/` and `/result` — are guaranteed deterministically in Phase D, so they land even
when the `repo` domain was already present and `bootstrap-repo` never ran.

- **Wave 0 (Rust skeleton, conditional):** when the project is Rust, dispatch `bootstrap-rust` first so
  the `Cargo.toml`/`src/` skeleton exists before the type-sensitive detectors resolve `--type rust`. For
  a greenfield Rust project, gather the remaining workers' detector orientation after this wave so they
  observe the now-present `Cargo.toml`; on an already-scaffolded crate `bootstrap-rust` reconciles in
  place and may run alongside Wave 1.
- **Wave 1 (independent):** `bootstrap-editorconfig`, `bootstrap-nix`, `bootstrap-repo`,
  `bootstrap-governance` (writes only `CLAUDE.md`/`AGENTS.md`/`docs/decisions/`, depends on no other
  domain), and — when Rust
  plus publishing intent is in scope — `bootstrap-cargo-publish`, dispatched after `bootstrap-rust` so
  the crate exists; it surfaces publish/version task-recipe fragments to `bootstrap-taskrunner` and
  release-CI fragments to `bootstrap-ci` (each `--type rust`).
- **Wave 2 (consume Wave 1):** `bootstrap-precommit` (reads the established `.editorconfig` baseline),
  `bootstrap-ci` and `bootstrap-taskrunner` (reuse the flake devshell and task names, and reconcile any
  publishing fragments surfaced by `bootstrap-cargo-publish`).

Give each subagent its validated brief as the complete orientation, including the freshness `check` JSON
so a worker with a fresh review reuses the cached summary instead of re-searching. Dispatch every
selected domain, present or missing, in these waves — a present domain reconciles in place. After each
wave, verify the durable postcondition by re-running `cog bootstrap-audit --json` and confirming every
dispatched domain now reports `present=true` (or was intentionally opted out) with
`requirements_satisfied==true`, that each worker either reused a fresh review or recorded a new stamp
(reporting any changed template paths), and that each touched `SKILL.md` lints clean, before starting
the next wave.

## Phase D: Reconcile and report

Guarantee the cross-domain ignore fragments before the final check. Whenever the `nix` domain was in
scope, apply its ignore lines through the gitignore domain's own idempotent mechanic — regardless of
whether the `repo` domain ran:

```bash
cog gitignore-apply --type nix --append --json
```

Re-run `cog bootstrap-audit --json` as the final postcondition: every in-scope domain must report
`present=true` **and** `requirements_satisfied==true` — a `present` domain with an unsatisfied
requirement (a nix devshell whose `.gitignore` lacks `.direnv/`/`/result`, a pre-commit config missing
the `editorconfig-checker` hook, an existing CI pipeline that does not reuse the flake) is incomplete
and must be reconciled before reporting done. Summarize what each worker produced — the target files
changed, the shared template paths updated, the research-shelf review entry ids, and whether the
template root resolved from the tracked `repo` checkout or the installed `xdg` tree (installed-tree
writes are local and uncommitted), and — when `bootstrap-cargo-publish` ran — the deployed publishing
helper scripts and `PUBLISHING.md`, the auth-mode/release-tool/cargo-dist decisions, and the fragments
handed to the taskrunner and CI owners. List follow-ups (`nix flake lock` on a nix host, `pre-commit
install`, `direnv allow`, the manual first `cargo publish`), and surface any conflicts or still-missing
domains that need an operator decision.

## Guardrails

- The orchestrator is the only interactive component; workers never interview.
- Every audited domain is in scope by default in its `default_action` mode (install when absent,
  reconcile when present); only an explicit operator opt-out removes one, and an example domain in the
  intent never shrinks the set.
- Every worker follows the shared refresh routine at
  `$(cog skill-refs path bootstrap/template-refresh-routine.md)`; installed-tree (`origin=xdg`) template
  writes are local and uncommitted and must be surfaced in the report.
- Scratch and intermediate artifacts live under the `cog rundir bootstrap` directory; never write them
  into the project tree or CWD.
- Keep the interview, brief-building, and dispatch foreground; never background them.
- Deterministic mechanics stay behind `cog` subcommands and the worker skills.
- Do not run git commands unless the operator authorizes it.
- Verify a durable postcondition — every in-scope domain `present` with all `requirements[]` satisfied —
  at every wave boundary and again at the final reconcile.
