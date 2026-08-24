---
name: bootstrap
description: >
  Scaffold or update a project's baseline configuration by interviewing the
  operator once and dispatching the bootstrap-* workers as parallel
  fresh-context agents. Runs on a brand new project or an existing one; every
  run refreshes the reviewed templates and reconciles each selected domain,
  installing what is absent and improving what is present. Use when the user
  says "bootstrap", "project bootstrap", "bootstrap a project", "scaffold a new
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

Scaffold a project's baseline tooling: interview the operator once, then dispatch the `bootstrap-*` workers as parallel fresh-context agents. This orchestrator owns the interview, the per-worker orientation, the dispatch sequencing, and the postcondition verification. Each worker owns its own domain and its deterministic `cog` mechanics, following the shared routine at `$(cog skill-refs path bootstrap/domain-worker-routine.md)`.

It runs on a new project or an existing one. Every run refreshes the reviewed templates and reconciles each selected domain — installing what is absent, applying improvements to what is present.

**This orchestrator is the only interactive component.** Workers never interview; everything they need arrives in their brief.

## Workers

Six run on every project: `bootstrap-lint` (`.editorconfig` plus `.pre-commit-config.yaml` — one code-style domain, two files that only work when they agree), `bootstrap-nix`, `bootstrap-repo`, `bootstrap-governance`, `bootstrap-ci`, and `bootstrap-taskrunner`.

Two are conditional, and none is a `cog bootstrap-audit` domain — the audit's every-domain-in-scope matrix stays language-orthogonal, so a language a project does not use never reads as "missing":

- **`bootstrap-rust`** — when `cog classify-project` reports Rust, or the intent is a new Rust project. Owns the crate skeleton (`Cargo.toml`, `src/`) and optional rust config, plus a publishing branch (crates.io helper scripts, `PUBLISHING.md`, release-plz/cargo-dist) taken when the intent involves publishing or release setup.
- **`bootstrap-installer`** — when the intent involves shippable install/uninstall scripts. Owns `install.sh`/`uninstall.sh`/`install-common.sh` and wires the install recipes into the justfile.

**Context-brief gate.** Before dispatching to any fresh-context worker, build and validate its brief per `$(cog skill-refs path orchestration/context-brief-gate.md)` — build with `cog context-brief build --request`, confirm with `cog context-brief validate`.

## Inputs

`$ARGUMENTS` is an optional target project directory (default: the current working directory) plus free-form intent describing what to set up. The intent orients the interview; it is never assumed to be complete.

## Audit and interview

Establish the deterministic present/missing baseline across every domain in one call:

```bash
cog bootstrap-audit --json
```

Each `domains[]` row reports `domain`, `present`, the per-artifact `artifacts` breakdown, `requires_question`, and the scope fields `default_in_scope`, `default_action` (`install` when absent, `reconcile` when present), and `requirements_satisfied`.

**This matrix is the authoritative scope: every domain is in scope by default, dispatched in its `default_action` mode, unless the operator explicitly opts it out.** Free-form intent _orients_ the interview but never _shrinks_ this set — an example domain ("set up what's missing, e.g. nix") names one instance, not the whole list. Read each row's `default_action` rather than re-deriving it.

Interview with `AskUserQuestion`, grounding every question in the matrix, and resolve:

- Any domain the operator explicitly opts **out** of. Absent an opt-out, every domain stays in scope — a present domain reconciles rather than being skipped.
- The conflict policy for any domain whose worker may need overwrite authority to apply improvements. Reconcile never becomes an unprompted destructive overwrite.
- Language and runtime specifics the workers cannot infer.
- License SPDX id, holder, and year whenever the `repo` row reports `requires_question=true` — asked, never silently defaulted.
- CI target whenever the `ci` row reports `requires_question=true` (no github/gitlab remote detected).

If the intent already answers a question, confirm rather than re-ask. The template review runs on a default 14-day freshness window, applied when a worker stamps a review; the operator may choose a longer one (30 days, say), carried in each brief so the stamps use it.

## Orientation and briefs

Open a run directory for every scratch and intermediate artifact. Substitute the literal path it echoes into the commands below — scratch never lands in the project tree or CWD:

```bash
RUN_DIR="$(cog rundir bootstrap | sed -n 's/^RUN_DIR=//p')"
[ -n "$RUN_DIR" ] || { echo "ERROR: cog rundir did not emit RUN_DIR" >&2; exit 1; }
```

Write the raw request to `$RUN_DIR/request.md`, then run each in-scope domain's detector so every brief carries the true starting state:

```bash
cog classify-project --json
cog precommit-detect --json
cog editorconfig-detect --json
cog nix-devshell-detect --json
cog gitignore-detect --json
cog governance-detect --json
cog ci-detect --json
cog taskrunner-detect --json
cog cargo-detect --json               # Rust (drives bootstrap-rust)
cog cargo-publish-detect --json       # Rust plus publishing intent
cog installer-detect --json           # install-script intent
```

`classify-project` reports a deterministic `primary_type` with a `confidence` and an `ambiguous` flag. When `ambiguous` is `true` (or `confidence` is `low`), the deterministic rules could not settle the project shape: judge it from the whole session and the detector output, and confirm the type with the operator before dispatching `bootstrap-rust`. When `ambiguous` is `false`, trust `primary_type` and dispatch deterministically.

Once a domain's detector resolves its template type, capture the freshness so the worker can skip re-research, and fold that JSON into its brief:

```bash
cog bootstrap-template-review check --domain <domain> --type "$TYPE" --json
```

Each row reports `review.state`, `review.fresh`, the cached `summary`, and the `skill_refs` origin/writability that tells the worker whether a template write lands in the tracked repo or the installed, uncommitted tree.

Then build one validated brief per in-scope worker under `$RUN_DIR`. Assemble each inline with the `context-builder` skill, carrying the operator's answers as precise orientation, the raw request attached as-is, and the full substantive context and detector findings bearing on that worker — omitting your own proposed solution:

```bash
cog context-brief template --out "$RUN_DIR/brief-body-<worker>.md"
# fill the body for that worker, then:
cog context-brief build --request "$RUN_DIR/request.md" --body "$RUN_DIR/brief-body-<worker>.md" --out "$RUN_DIR/brief-<worker>.md"
cog context-brief validate "$RUN_DIR/brief-<worker>.md"
```

## Dispatch

Dispatch the selected workers as foreground Agent subagents — environment-first, no backgrounding, respecting the fixed five-level depth budget. Give each its validated brief as the complete orientation, including the freshness `check` JSON so a worker with a fresh review reuses the cached summary instead of re-searching.

**Assign every shared output path exactly one owning writer per run.** `bootstrap-repo` is the sole writer of `.gitignore` during the waves and receives other workers' ignore fragments through its brief. The cross-domain fragments that outlive a worker's scope — the nix devshell's `.direnv/` and `/result` — are guaranteed deterministically at the reconcile step, so they land even when `repo` was already present and never ran.

Only two real dependencies remain, so the waves are shallow:

- **Wave 0 (conditional):** `bootstrap-rust`, when the project is Rust, so the `Cargo.toml`/`src/` skeleton exists before the type-sensitive detectors resolve `--type rust`. For a greenfield Rust project, gather the remaining detector orientation after this wave so the workers observe the now-present `Cargo.toml`. On an already-scaffolded crate it reconciles in place and may run alongside Wave 1.
- **Wave 1:** `bootstrap-lint`, `bootstrap-nix`, `bootstrap-repo`, `bootstrap-governance`, and `bootstrap-taskrunner`. None depends on another.
- **Wave 2:** `bootstrap-ci` (reuses the flake devshell and the justfile's recipe names) and `bootstrap-installer` (needs the justfile to wire `install`/`uninstall`/`reinstall` into).

After each wave, verify the durable postcondition before starting the next: re-run `cog bootstrap-audit --json` and confirm every dispatched domain reports `present=true` (or was intentionally opted out) with `requirements_satisfied==true`, that each worker either reused a fresh review or recorded a new stamp — reporting any changed template paths — and that each touched `SKILL.md` lints clean.

## Reconcile and report

Guarantee the cross-domain ignore fragments before the final check. Whenever the `nix` domain was in scope, apply its ignore lines through the gitignore domain's own idempotent mechanic, regardless of whether `bootstrap-repo` ran:

```bash
cog gitignore-apply --type nix --append --json
```

Re-run `cog bootstrap-audit --json` as the final postcondition. Every in-scope domain must report `present=true` **and** `requirements_satisfied==true`. A `present` domain with an unsatisfied requirement — a nix devshell whose `.gitignore` lacks `.direnv/`/`/result`, a pre-commit config missing the `editorconfig-checker` hook, a CI pipeline that does not reuse the flake — is incomplete and must be reconciled before reporting done.

Summarize what each worker produced: the target files changed, the shared template paths updated, the research-shelf review entry ids, and whether the template root resolved from the tracked `repo` checkout or the installed `xdg` tree — installed-tree writes are local and uncommitted, so name their absolute paths. When the Rust publishing branch ran, add the deployed helper scripts and `PUBLISHING.md`, the auth-mode/release-tool/cargo-dist decisions, and the fragments handed to the taskrunner and CI owners.

List follow-ups (`nix flake lock` on a nix host, `pre-commit install`, `direnv allow`, the manual first `cargo publish`), and surface any conflicts or still-missing domains needing an operator decision.

Run no git command unless the operator authorizes it.
