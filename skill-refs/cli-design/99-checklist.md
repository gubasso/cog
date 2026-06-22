# 99 — Checklist

One-page sanity check before declaring a CLI shippable. If a box is unchecked, fix it or explicitly
waive it in an ADR — don't ship with silent gaps.

## Architecture

- [ ] Facing category declared at design time: `human-facing` or `machine-facing`.
- [ ] `main` is ≤ 120 LOC: parses args, inits logging, builds `AppContext`, dispatches, maps errors
      to exit codes. Nothing else.
- [ ] Parse-shape (CLI structs) and runtime-shape (domain requests) are different types. Projection
      happens at the top of every handler.
- [ ] One `AppContext`, built once, passed by reference. No globals, no thread-locals.
- [ ] Every subcommand is its own file on both sides (`cli/<name>` + `commands/<name>`).
- [ ] The human-UX `ui/` boundary or machine-output boundary is real: no print statements outside
      it. Verified by a grep-able lint.
- [ ] `domain/` has zero I/O imports. `adapters/` is the only place that talks to the outside world.
- [ ] If a `lib.rs` (or public package surface) exists, it has a real second consumer. Otherwise,
      delete it.

→ Detail: [00 — Architecture](00-architecture.md)

## Logging & output

- [ ] Human-facing tools default to human-UX: stdout is command results; stderr carries prompts,
      progress, warnings, and terse error messages.
- [ ] Human-UX color respects `NO_COLOR` / `FORCE_COLOR` / `--color {auto,always,never}`.
- [ ] Human-UX progress/prompts auto-hide when stderr is not a TTY.
- [ ] Human-UX non-interactive mode: `--yes` for confirmations; auto-fail-vs-prompt when stdin is
      not a TTY.
- [ ] Machine-facing tools default to structured machine-output on stdout (JSON or best format).
- [ ] Human-facing tools expose machine-output via `--format json`, `--json`, or equivalent for
      commands whose output might be piped or scripted.
- [ ] Machine-output does not paginate by default; any too-large output documents
      `--limit`/`--page`/`--cursor`/`--offset` rules in `--help`.
- [ ] Machine-output is token-friendly where possible without compromising machine readability.
- [ ] Log-messages go to `$XDG_STATE_HOME/<app>/<app>.log` by default. File rotation configured.
- [ ] Terminal mirror of log-messages is opt-in (`--log-stderr` or documented verbosity policy).
- [ ] Log records are single-line, structured (`key=value` or JSON), no ANSI.
- [ ] Log levels include at least `info`, `warn`, `error`, and `debug`.
- [ ] Log schema has stable field names (`ts`, `level`, `target`, `op`, `status`, `dur_ms`,
      `err.kind`).

→ Detail: [01 — Logging & Output](01-logging-and-output.md)

## Error messages

- [ ] Each error has a stable `err.kind` identifier.
- [ ] Every variant maps to a specific BSD sysexits exit code. No catch-all `1`.
- [ ] The exit-code matrix is unit-tested.
- [ ] User-facing errors include `what`, `where`, `why`, and a `hint` (when one is known).
- [ ] Error chains are printed at terse depth by default, full depth at `-v` and in log-messages.
- [ ] Lower-layer errors don't leak into higher-layer types as opaque "unknown" wrappers. Wrap with
      cause links.
- [ ] No `panic`/`unwrap`/`expect`/bare exceptions outside `main`, tests, build scripts, and
      once-init blocks.

→ Detail: [02 — Error Messages](02-error-messages.md)

## Configuration

- [ ] Precedence is `CLI > env > project file > user file > defaults`. The same rule applies to
      every key.
- [ ] User config lives under `$XDG_CONFIG_HOME/<app>/`.
- [ ] Loader tracks per-key source provenance — errors say which file and line.
- [ ] Unknown keys at the file layer fail loudly (or a documented `--config-strict` toggle controls
      this).
- [ ] Env vars use `<APP>_*` prefix; nested keys use `__` separator.
- [ ] Log level reuses the ecosystem env var (`RUST_LOG` / `PYTHONLOGLEVEL`), not an app-specific
      one.
- [ ] `--print-config` (or `config show`) subcommand exists and shows resolved values + sources.

→ Detail: [03 — Config Precedence](03-config-precedence.md)

## Coding style

- [ ] Parse, don't validate: strings → precise types at every boundary.
- [ ] Newtypes for every domain primitive (IDs, paths, names, durations, byte sizes).
- [ ] Composition over inheritance. Static dispatch by default; dynamic only with justification.
- [ ] Constructor placement: pure assembly belongs on the produced type, not as a free function in
      `services/`.
- [ ] Files ≤ ~400 LOC. Hitting the cap is a signal to split.
- [ ] Comments say _why_, not _what_. Link to ADRs / issues by stable identifier.
- [ ] Module headers state purpose and non-purpose ("what it is, what it isn't").
- [ ] Strict lints enabled at the project level; per-line `allow` only with a justifying comment.

→ Detail: [04 — Coding Style](04-coding-style-rust-zig.md)

## Designing for LLM coding agents

- [ ] `--help` is documentation. Every flag and subcommand has descriptive help text.
- [ ] `help` / usage output lets an agent discover commands, flags, defaults, and examples.
- [ ] Machine-output is default for machine-facing tools; human-facing tools expose `--format json`
      or equivalent.
- [ ] Output is deterministic for the same input. No timestamps in default output (unless that's the
      point).
- [ ] A `doctor` subcommand (or equivalent) exists and emits a structured health report.
- [ ] An `init` subcommand (or equivalent) handles setup/scaffold/bootstrap and reuses `doctor`
      checks as the source of truth.
- [ ] Bash completion is shipped.
- [ ] Man pages are shipped and available through a subcommand.
- [ ] `--help` and JSON output are snapshot-tested to catch accidental regressions.
- [ ] Error messages include a stable `err.kind` an agent can pattern-match on.
- [ ] The log-message format is documented in the README so an agent can reason about it.

→ Detail: [05 — Designing for LLM Agents](05-designing-for-llm-agents.md)

## Naming & docs

- [ ] Visibility defaults to the least public modifier that works. No blanket `pub mod` across the
      codebase.
- [ ] Verb/noun naming follows the table in [07](07-naming-and-docs.md): `<Verb>Args`,
      `<Verb>Request`, `<Layer>Error`.
- [ ] Every public and crate-public item has a doc comment.
- [ ] Doc comments on CLI flag fields are written for the user; they become `--help` text.
- [ ] Crate root has a module map linking to the architecture spec.
- [ ] No `Manager` / `Helper` / `Utils` / `Handler` / `Wrapper` suffix soup.

→ Detail: [07 — Naming & Documentation](07-naming-and-docs.md)

## Testing

- [ ] One integration test file per subcommand. Always.
- [ ] Every test runs in an isolated tempdir with a cleared environment (`env_clear` + curated env).
- [ ] Newtype constructors and parse-shape → runtime-shape projections are unit-tested.
- [ ] Exit-code matrix is locked down by tests.
- [ ] Structured output is snapshot-tested.
- [ ] `--help` is snapshot-tested.
- [ ] No tests share state, no tests share temp dirs, no tests modify global env or cwd.
- [ ] Test runner is the parallel-default option for the language (`nextest` / `pytest -n auto` /
      `go test -parallel`).
- [ ] Unit tests run in pre-commit (parallel, fast).
- [ ] Integration tests run in pre-push (parallel, single-digit seconds total).
- [ ] E2E tests run in CI only — never in local hooks.
- [ ] Coverage is judged by risk and impact, not by chasing a line-count number.
- [ ] Property-based tests cover parsers, codecs, and state machines (`proptest` / `hypothesis` /
      `fast-check`).
- [ ] Mutation score (≥ 60% on critical modules) tracked nightly, even if not gated (`cargo-mutants`
      / `mutmut` / `stryker`).
- [ ] LLM-generated tests reviewed against the third-party-API heuristics in
      [08 § Detecting "testing the third-party library"](08-testing-and-quality/testing-strategy.md#detecting-testing-the-third-party-library).
- [ ] Every test survives the "import-removal test": deleting a third-party import would break the
      test (proving it tests the boundary, not the library).

→ Detail: [08 — Testing Strategy](08-testing-and-quality/testing-strategy.md) → Tooling:
[08a — Testing Tools](08-testing-and-quality/testing-tools.md)

## Regression safeguards

- [ ] Property-based tests cover parsers, codecs, newtypes, and state machines (`proptest` /
      `hypothesis` / `fast-check`).
- [ ] Mutation score (>= 60%) tracked on critical modules; nightly CI (`cargo-mutants` / `mutmut` /
      `stryker`).
- [ ] Complexity thresholds enforced in CI: cognitive complexity <= 25, function length <= 100 LOC,
      NARGS <= 7.
- [ ] Restriction lints enabled: `todo`, `dbg_macro`, `unwrap_used`, `panic`, `unimplemented`.
- [ ] Unused dependency detection in pre-commit (`cargo-machete` / `deptry` / `depcheck`).
- [ ] Binary size baseline tracked; CI flags growth > 5%.
- [ ] Snapshot updates require explicit review; never auto-updated in CI.
- [ ] Architectural boundary rules enforced via grep-based lints (domain must not import adapters,
      no print outside ui/).
- [ ] TDD-for-agents workflow documented in CLAUDE.md / AGENTS.md: write tests first, agent
      implements, human reviews.
- [ ] Eval harness exists for agent-consumed CLI skills (10+ samples per prompt, tracked over time).

→ Detail: [10 — Regression Safeguards](08-testing-and-quality/regression-safeguards.md) → Tooling:
[10a — Code Quality Tools](08-testing-and-quality/code-quality-tools.md)

## CI / shipping

- [ ] Format-check, lint, test all gate the PR.
- [ ] Toolchain version is pinned (`rust-toolchain.toml`, `.python-version`, `go.mod`).
- [ ] Dependency lock file committed for binaries.
- [ ] Reproducible builds in CI (cached, deterministic).
- [ ] Smoke test on every supported OS.
- [ ] Release artifacts include shell completions and a man page (if applicable).
- [ ] `--version` includes the git SHA and build date.

## CLI wrapper specifics (if applicable)

If the CLI wraps another binary (orchestrates a subprocess), additionally:

- [ ] Typed command builder; no stringly-typed args ever.
- [ ] Args are unit-testable as snapshots before any subprocess runs.
- [ ] Signal forwarding (SIGINT, SIGTERM) to the child.
- [ ] Exit-code passthrough where the wrapper has nothing to add.
- [ ] `--` sentinel handled correctly: passes-through verbatim to the child.

→ Detail: [06 — CLI Wrapper Design](06-cli-wrapper-design/)

## See also

- [README](README.md) — index of every chapter.
- Language-specific specs: [rust](../../languages/rust/cli-spec/) ·
  [python](../../languages/python/cli-spec/) · [bash](../../languages/bash/cli-spec/).
