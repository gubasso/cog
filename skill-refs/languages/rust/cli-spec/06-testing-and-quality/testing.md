# Testing (Rust)

> Prerequisite: [General principles — Testing Strategy](../../../../cli-design/08-testing-and-quality/testing-strategy.md) for the pyramid, isolation rules, and what to mock. This chapter is the Rust implementation.

## Crate stack

| Concern                  | Crate                    |
| ------------------------ | ------------------------ |
| Process-level CLI tests  | `assert_cmd`             |
| Assertion helpers        | `predicates`             |
| Snapshots                | `insta` (`yaml` feature) |
| Temp dirs                | `tempfile`               |
| Compile-fail / typestate | `trybuild`               |
| Test runner              | `cargo nextest`          |

## Pyramid layout in the tree

```text
src/
└─ commands/widget.rs           [unit tests inline in #[cfg(test)] mod tests]

tests/
├─ cmd_widget.rs                [one integration test file per subcommand]
├─ fixtures/                    [test fixtures]
├─ snapshots/                   [insta snapshots]
└─ support/mod.rs               [shared helpers]
```

## Unit tests

Colocated at the bottom of each module:

```rust
// src/commands/widget.rs

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn from_cli_parses_glob() {
        let args = WidgetArgs { id: None, dry_run: false, filter: Some("*.txt".into()) };
        let req = Request::from_cli(args).unwrap();
        assert!(req.filter.is_some());
    }
}
```

Target: every CLI-args → domain-Request projection, every newtype constructor, every state-machine transition.

## Integration tests — one per subcommand

```rust
// tests/cmd_widget.rs

use assert_cmd::Command;
use predicates::prelude::*;
use tempfile::tempdir;

#[test]
fn widget_dry_run_prints_plan_without_changing_state() {
    let tmp = tempdir().unwrap();
    Command::cargo_bin("app").unwrap()
        .arg("widget").arg("--dry-run")
        .current_dir(&tmp)
        .assert()
        .success()
        .stdout(predicate::str::contains("would create"));
    assert!(tmp.path().read_dir().unwrap().next().is_none(), "dry-run should not write files");
}
```

Rules:

- One file per subcommand. Test names describe behavior, not implementation.
- Every test gets its own `tempdir`. Never share state.
- Use `predicates::str::contains` for stdout matching; reserve exact-equality for tiny stable strings.

## Snapshot tests with `insta`

For any structured output (JSON, YAML, rendered tables, long error messages):

```rust
#[test]
fn widget_list_renders_table() {
    let report = make_test_report();
    insta::assert_yaml_snapshot!(report);
}
```

For stdout snapshots from integration tests, use `insta::assert_snapshot!` with the captured stdout. Snapshots live in `tests/snapshots/`.

**Review snapshot diffs as carefully as code diffs** — they're behavior.

Use `cargo insta review` interactively to accept/reject snapshot updates.

## Compile-fail / typestate (optional)

Use `trybuild` only when you have a typestate API (a builder where the type changes per `.with_x()` call) and want to lock down the invalid call sequences. Skip otherwise.

```rust
// tests/trybuild.rs
#[test]
fn ui() {
    let t = trybuild::TestCases::new();
    t.compile_fail("tests/trybuild/*.rs");
}
```

## Test runner

Use `cargo nextest` via `just test`. It parallelizes correctly, fails fast, and produces a flat summary. `cargo test` is fine but slower and noisier.

```sh
cargo install cargo-nextest --locked
cargo nextest run                          # ad-hoc local run; uses [profile.default]
cargo nextest run --profile pre-commit     # unit tests, fail-fast (pre-commit hook)
cargo nextest run --profile pre-push       # integration tests (pre-push hook)
cargo nextest run --profile ci             # CI workflow — retries, quiet output
```

**Foot-gun:** non-default profiles in `.config/nextest.toml` are silently inert unless invoked with `--profile <name>`. A CI workflow that just runs `cargo nextest run` ignores its own `[profile.ci]` retry/timeout/output tuning and falls back to `[profile.default]`. This is the Rust instance of the general "explicit-profile" pattern in [cli-design § Tuning test-runner output for CI + AI agents](../../../../cli-design/08-testing-and-quality/testing-tools.md#tuning-test-runner-output-for-ci--ai-agents).

### nextest profile reference

The four general output axes in the cli-design doc map to these nextest keys (refs: [config reference](https://nexte.st/docs/configuration/reference/), [running tests](https://nexte.st/docs/running/)):

| General axis                            | nextest key          | Token-efficient value                                             |
| --------------------------------------- | -------------------- | ----------------------------------------------------------------- |
| Per-test status during execution        | `status-level`       | `"fail"` in CI / hooks; `"pass"` only for ad-hoc interactive runs |
| End-of-run summary                      | `final-status-level` | `"fail"`                                                          |
| Captured stdout/stderr of passing tests | `success-output`     | `"never"`                                                         |
| Captured stdout/stderr of failing tests | `failure-output`     | `"immediate-final"` (inline AND in final summary)                 |

Reference shape for a layered `.config/nextest.toml`:

```toml
[profile.default]
status-level = "pass"             # verbose OK for interactive runs
final-status-level = "fail"
success-output = "never"
failure-output = "immediate-final"

[profile.pre-commit]
default-filter = "kind(lib) + kind(bin)"   # unit tests only
fail-fast = true                  # tight feedback for the commit gate
status-level = "fail"             # silent on pass
final-status-level = "fail"
success-output = "never"
failure-output = "immediate-final"

[profile.pre-push]
default-filter = "kind(test)"     # integration tests (tests/*.rs)
fail-fast = false                 # surface ALL regressions
status-level = "fail"
final-status-level = "fail"
success-output = "never"
failure-output = "immediate-final"

[profile.ci]
fail-fast = false
retries = { backoff = "exponential", count = 2, delay = "1s", max-delay = "10s", jitter = true }
status-level = "fail"             # NOT "pass" — per-test pass lines are pure log noise
final-status-level = "fail"
success-output = "never"
failure-output = "immediate-final"
```

**Progress bars:** auto-suppress on non-TTY runners (GitHub Actions); set `NEXTEST_HIDE_PROGRESS_BAR=1` in workflow env if a runner emulates a TTY.

**Machine-readable output, if a downstream parser needs it:**

- `--message-format=libtest-json` / `libtest-json-plus` — CLI flag (not a profile key); compact JSON event stream; the `-plus` variant adds nextest-specific metadata (retries, slowness).
- `[profile.X.junit] path = "target/nextest-results.xml"` plus `store-failure-output = true` / `store-success-output = false` — JUnit XML, widely parseable.

Don't add either prophylactically — adopt them only when something downstream actually consumes the format.

## `tests/support/mod.rs`

Shared helpers — tempdir setup, fixture loaders, env scrubbers:

```rust
//! Shared test helpers.

use std::path::PathBuf;
use tempfile::TempDir;

pub struct Fixture {
    pub tmp: TempDir,
    pub home: PathBuf,
}

impl Fixture {
    pub fn new() -> Self {
        let tmp = tempfile::tempdir().unwrap();
        let home = tmp.path().join("home");
        std::fs::create_dir_all(&home).unwrap();
        Self { tmp, home }
    }

    pub fn cmd(&self) -> assert_cmd::Command {
        let mut c = assert_cmd::Command::cargo_bin("app").unwrap();
        c.env_clear()
            .env("HOME", &self.home)
            .env("PATH", std::env::var_os("PATH").unwrap());
        c
    }
}
```

`env_clear` plus a curated env is the defense against test pollution. Without it, your local `RUST_LOG=trace` will break CI snapshots.

## Locking down the exit-code matrix

The exit-code matrix is part of the user-facing API. Treat it like one:

```rust
#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn usage_is_64() {
        assert_eq!(AppError::Usage("bad flag".into()).exit_code(), 64);
    }

    #[test]
    fn permission_denied_is_77() {
        let e = AppError::Io(std::io::Error::from(std::io::ErrorKind::PermissionDenied));
        assert_eq!(e.exit_code(), 77);
    }
    // ... one test per variant
}
```

## Anti-patterns specific to Rust

- Calling `tracing_subscriber::fmt::init()` inside a test — installs a global subscriber and can't be re-installed cleanly across tests. Don't init logging in tests at all; use `tracing_test::traced_test` if you must.
- Letting `cargo test` run with `--test-threads=1` "to fix" flakiness. The flakiness is from shared state; fix the state.
- Hardcoding paths like `/tmp/myapp_test` instead of `tempfile::tempdir`.
- Using `env::set_var` in a test — leaks across the suite. Set env on `assert_cmd::Command` instead.

## See also

- [General principle — Testing Strategy](../../../../cli-design/08-testing-and-quality/testing-strategy.md)
- [03 — Error Handling](../03-error-handling.md) — exit-code unit tests
- [07 — Dependencies (Rust)](../07-dependencies.md)

## References

- [`assert_cmd`](https://docs.rs/assert_cmd/) · [`insta`](https://insta.rs/docs/) · [`predicates`](https://docs.rs/predicates/)
- [`tempfile`](https://docs.rs/tempfile/) · [`trybuild`](https://docs.rs/trybuild/) · [`cargo-nextest`](https://nexte.st/)
