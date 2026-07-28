# Advanced Testing (Rust)

> Prerequisite: [Testing (Rust)](./testing.md) for the basics (`assert_cmd`, `insta`, `tempfile`, `trybuild`, `nextest`). This chapter covers advanced techniques: property-based testing, mutation testing, document-driven CLI testing, inline snapshots, golden files, HTTP fakes, and interactive CLI testing.
>
> General principles: [09 — Testing Strategy](../../../../cli-design/08-testing-and-quality/testing-strategy.md) · [09a — Testing Tools](../../../../cli-design/08-testing-and-quality/testing-tools.md) · [10 — Regression Safeguards](../../../../cli-design/08-testing-and-quality/regression-safeguards.md).

## Crate stack (advanced)

| Concern                   | Crate                      | When to add                                    |
| ------------------------- | -------------------------- | ---------------------------------------------- |
| Property-based testing    | `proptest`                 | Parsers, codecs, newtypes, state machines.     |
| Mutation testing          | `cargo-mutants` (CLI tool) | Always (validates test quality).               |
| Document-driven CLI tests | `trycmd`                   | Many CLI scenarios to maintain.                |
| Lightweight CLI snapshots | `snapbox`                  | When you want pattern-matching in CLI output.  |
| Inline snapshots          | `expect-test`              | Small snapshots that belong next to the test.  |
| Golden file testing       | `goldie`                   | Large outputs (compiler output, config dumps). |
| HTTP fakes                | `wiremock`                 | CLI talks to HTTP APIs.                        |
| Interactive CLI testing   | `rexpect`                  | CLI has interactive prompts.                   |

Add to `[dev-dependencies]` only when the concrete need arises.

## Property-based testing with `proptest`

[`proptest`](https://github.com/proptest-rs/proptest) generates hundreds of inputs per test, finds edge cases, and shrinks failures to minimal counterexamples.

### When to use

- Newtype constructors: every value the type accepts must satisfy invariants under all operations.
- Parsers and codecs: `decode(encode(x)) == x` for all valid inputs.
- CLI arg builders (wrapper CLIs): constructed argv round-trips back to the input model.
- State machine transitions: every reachable state is consistent.
- Pure transforms with algebraic laws.

### When not to use

- Side-effectful integrations (I/O, network).
- UI flows where the input space is too entangled.
- Anything whose oracle is expensive to compute.

### Setup

```toml
# Cargo.toml
[dev-dependencies]
proptest = "1"
```

```toml
# .config/nextest.toml — slow property tests get their own group
[[profile.default.overrides]]
filter = "test(prop_)"
test-group = "property"
slow-timeout = { period = "30s", terminate-after = 2 }
```

### Patterns

**Newtype round-trip:**

```rust
use proptest::prelude::*;

proptest! {
    #[test]
    fn widget_id_roundtrip(s in "[a-z][a-z0-9_-]{0,63}") {
        let id = WidgetId::try_new(s.clone()).unwrap();
        prop_assert_eq!(id.as_str(), &s);
        prop_assert_eq!(WidgetId::try_new(id.as_str().to_string()).unwrap(), id);
    }
}
```

**Parser rejects all invalid inputs:**

```rust
proptest! {
    #[test]
    fn widget_id_rejects_invalid(s in ".*") {
        if s.is_empty() || s.len() > 64 || !s.starts_with(|c: char| c.is_ascii_lowercase()) {
            prop_assert!(WidgetId::try_new(s).is_err());
        }
    }
}
```

**Argv builder round-trip (wrapper CLI):**

```rust
proptest! {
    #[test]
    fn codex_args_roundtrip(
        model in "(gpt-4|o4-mini|o3)",
        quiet in proptest::bool::ANY,
    ) {
        let cmd = CodexCommand::new().model(&model).quiet(quiet);
        let argv = cmd.to_argv();
        prop_assert!(argv.contains(&model));
        if quiet {
            prop_assert!(argv.contains(&"--quiet".to_string()));
        }
    }
}
```

### Regression files

`proptest` persists failing seeds in `proptest-regressions/` files alongside the test. **Commit these files.** They lock down the specific input that triggered the failure so the bug stays fixed.

```text
tests/
├── proptest-regressions/
│   └── test_widget_id.txt    # auto-generated on failure
```

### Integration with nextest

Property tests run with the standard `cargo nextest run` invocation. Name them with a `prop_` prefix so the nextest override (above) gives them extra time. For extended iteration counts in nightly CI:

```bash
PROPTEST_CASES=10000 cargo nextest run --profile ci
```

## Mutation testing with `cargo-mutants`

[`cargo-mutants`](https://mutants.rs/) modifies your source code (flips operators, deletes statements, replaces returns) and verifies your test suite catches the changes. Mutants that survive are holes in your tests.

### Installation

```bash
cargo install cargo-mutants
```

### Usage

```bash
# Basic run — tests all mutants
cargo mutants

# Use nextest as the test runner (recommended)
cargo mutants --test-tool nextest

# Limit to specific modules
cargo mutants --file src/domain/widget.rs

# Exclude test-only code
cargo mutants --exclude-regex 'tests?/'
```

### Interpreting results

| Outcome      | Meaning                                                                |
| ------------ | ---------------------------------------------------------------------- |
| **Killed**   | Test suite caught the mutation. Good.                                  |
| **Survived** | Test suite passed despite the mutation. Your tests have a gap.         |
| **Timeout**  | Mutation caused an infinite loop. Killed by timeout. Counts as caught. |
| **Unviable** | Mutation didn't compile. Not counted.                                  |

**Target:** >= 60% mutation score on critical modules (parsers, exit-code logic, state machines). Treat surviving mutants like uncovered branches: triage, add a test.

### Integration with CI

Mutation testing is slow (runs the test suite N times). Run nightly, not on every PR.

```yaml
# .github/workflows/mutation.yml
name: mutation-testing
on:
  schedule: [{ cron: '0 4 * * *' }]
  workflow_dispatch: {}

jobs:
  mutate:
    runs-on: ubuntu-latest
    timeout-minutes: 120
    steps:
      - uses: actions/checkout@v4
      - run: cargo install cargo-mutants cargo-nextest
      - run: cargo mutants --test-tool nextest || true
      - uses: actions/upload-artifact@v4
        if: always()
        with:
          name: mutation-report
          path: mutants.out/
```

### justfile recipe

```just
mutate:
    cargo mutants --test-tool nextest

mutate-file FILE:
    cargo mutants --test-tool nextest --file {{FILE}}
```

## Document-driven CLI testing with `trycmd`

[`trycmd`](https://docs.rs/trycmd) defines CLI test cases in `.toml` or `.md` files. Each case specifies the command, expected stdout, stderr, and exit code. Scales to hundreds of test cases without code duplication.

### When to use over `assert_cmd`

- Many similar CLI scenarios with slight variations.
- You want test cases reviewable without reading Rust code.
- Documentation and tests should stay in sync.

### Setup

```toml
# Cargo.toml
[dev-dependencies]
trycmd = "0.15"
```

```rust
// tests/cli_tests.rs
#[test]
fn cli_tests() {
    trycmd::TestCases::new().case("tests/cmd/*.toml");
}
```

### Test case format

```toml
# tests/cmd/help.toml
bin.name = "codex-session"
args = ["--help"]
status.code = 0
stdout.contains = ["Usage:", "codex-session"]
```

```toml
# tests/cmd/invalid-arg.toml
bin.name = "codex-session"
args = ["--nonexistent"]
status.code = 2
stderr.contains = ["unexpected argument"]
```

### Updating expectations

```bash
TRYCMD=overwrite cargo test
```

Review the diffs like snapshot diffs — they're behavioral changes.

## Lightweight CLI snapshots with `snapbox`

[`snapbox`](https://docs.rs/snapbox) is a lighter alternative to `assert_cmd` + `insta` for CLI output assertions. It supports pattern matching with `...` wildcards and `[..]` substitutions.

### When to use

- When you want snapshot-style output comparison with flexible matching.
- When `assert_cmd` + `predicates` is too verbose for simple output checks.

```toml
# Cargo.toml
[dev-dependencies]
snapbox = { version = "0.6", features = ["cmd"] }
```

```rust
use snapbox::cmd::Command;

#[test]
fn version_output() {
    Command::new(snapbox::cmd::cargo_bin!("codex-session"))
        .arg("--version")
        .assert()
        .success()
        .stdout_eq("codex-session [VERSION]\n");  // [VERSION] matches any version string
}
```

## Inline snapshots with `expect-test`

[`expect-test`](https://github.com/rust-analyzer/expect-test) (used by rust-analyzer) stores expected values inline in the test source. Run `UPDATE_EXPECT=1 cargo test` to auto-update them.

### When to use

- Snapshots are small enough to inline (< 10 lines).
- You want the expected value right next to the assertion, not in a separate file.

```toml
# Cargo.toml
[dev-dependencies]
expect-test = "1"
```

```rust
use expect_test::expect;

#[test]
fn error_display() {
    let err = AppError::Usage("bad flag".into());
    let actual = format!("{err}");
    expect![[r#"usage error: bad flag"#]].assert_eq(&actual);
}
```

Update inline snapshots:

```bash
UPDATE_EXPECT=1 cargo test
```

## Golden file testing with `goldie`

[`goldie`](https://github.com/rossmacarthur/goldie) compares output against checked-in golden files. Simpler than `insta` when you don't need its review workflow.

```toml
# Cargo.toml
[dev-dependencies]
goldie = "0.5"
```

```rust
#[test]
fn config_dump() {
    let output = render_config(&test_config());
    goldie::assert!(output);
    // Golden file: tests/goldie/config_dump.golden
}
```

Update golden files:

```bash
GOLDIE_UPDATE=1 cargo test
```

## HTTP fakes with `wiremock`

[`wiremock`](https://docs.rs/wiremock/) runs an in-process HTTP server that serves canned responses and records requests. Use it when your CLI talks to HTTP APIs.

### When to use

- Testing the boundary between your code and an external HTTP API.
- Verifying that your code sends the correct requests (method, path, headers, body).
- Asserting on your code's behavior given specific API responses.

```toml
# Cargo.toml
[dev-dependencies]
wiremock = "0.6"
```

```rust
use wiremock::{MockServer, Mock, matchers::*, ResponseTemplate};

#[tokio::test]
async fn fetches_quota_from_api() {
    let server = MockServer::start().await;
    Mock::given(method("GET"))
        .and(path("/v1/quota"))
        .and(header("Authorization", "Bearer test-token"))
        .respond_with(ResponseTemplate::new(200)
            .set_body_json(serde_json::json!({"remaining": 42})))
        .mount(&server)
        .await;

    let quota = fetch_quota(&server.uri(), "test-token").await.unwrap();
    assert_eq!(quota.remaining, 42);
}
```

**Assert on your code's return value, not on the mock.** The mock is the boundary fake; the assertion is about your domain logic. See [09 § heuristic 2](../../../../cli-design/08-testing-and-quality/testing-strategy.md#2-the-mock-is-the-only-subject).

## Interactive CLI testing with `rexpect`

[`rexpect`](https://docs.rs/rexpect/) automates interaction with CLI programs that use TTY prompts. Use it only if your CLI has interactive prompts (e.g., `dialoguer` or `inquire`).

```toml
# Cargo.toml
[dev-dependencies]
rexpect = "0.5"
```

```rust
use rexpect::spawn;

#[test]
fn interactive_login_prompt() {
    let mut p = spawn("cargo run -- account login", Some(10_000)).unwrap();
    p.exp_string("Enter API key:").unwrap();
    p.send_line("sk-test-key").unwrap();
    p.exp_string("Logged in successfully").unwrap();
}
```

**Prefer non-interactive paths** (`--yes`, `--api-key <key>`) for most tests. Reserve `rexpect` for verifying the interactive UX itself.

## Dev-dependencies summary

Updated dependency table (extends [06 § Crate stack](./testing.md#crate-stack)):

```toml
[dev-dependencies]
# Core (from 06-testing.md)
assert_cmd  = "2"
predicates  = "3"
insta       = { version = "1", features = ["yaml"] }
tempfile    = "3"

# Advanced (add as needed)
proptest    = "1"          # property-based testing
trycmd      = "0.15"       # document-driven CLI tests
snapbox     = { version = "0.6", features = ["cmd"] }  # lightweight CLI snapshots
expect-test = "1"          # inline snapshots
goldie      = "0.5"        # golden file testing
wiremock    = "0.6"        # HTTP fakes (if CLI talks to APIs)
rexpect     = "0.5"        # interactive CLI testing (if interactive prompts exist)
```

**CLI tools** (install separately, not in `Cargo.toml`):

```bash
cargo install cargo-mutants   # mutation testing
cargo install cargo-insta     # snapshot review workflow
```

## Naming conventions

```text
tests/
├── cmd_widget.rs              # integration: subcommand tests (assert_cmd)
├── cmd/                        # trycmd test cases (if using trycmd)
│   ├── widget_help.toml
│   └── widget_dry_run.toml
├── cli_tests.rs               # trycmd runner
├── fixtures/                   # shared test data
├── goldie/                     # golden files (if using goldie)
├── proptest-regressions/       # proptest regression seeds (auto-generated)
├── snapshots/                  # insta snapshots
└── support/mod.rs              # shared helpers
```

## See also

- [Testing (Rust)](./testing.md) — core crate stack, unit/integration patterns, nextest profiles, support module.
- [Code Quality (Rust)](./code-quality.md) — complexity metrics, clippy restriction lints, binary analysis.
- [07 — Dependencies (Rust)](../07-dependencies.md) — curated default crate list.
- General principles:
  - [09 — Testing Strategy](../../../../cli-design/08-testing-and-quality/testing-strategy.md) — pyramid, isolation, mutation testing, property-based testing.
  - [09a — Testing Tools](../../../../cli-design/08-testing-and-quality/testing-tools.md) — per-language tool matrix.
  - [10 — Regression Safeguards](../../../../cli-design/08-testing-and-quality/regression-safeguards.md) — TDD-for-agents, eval harnesses, layering model.

## References

- [`proptest`](https://github.com/proptest-rs/proptest) · [docs](https://docs.rs/proptest/latest/proptest/) · [book](https://proptest-rs.github.io/proptest/intro.html)
- [`cargo-mutants`](https://mutants.rs/) · [GitHub](https://github.com/sourcefrog/cargo-mutants)
- [`trycmd`](https://docs.rs/trycmd) · [GitHub](https://github.com/assert-rs/trycmd)
- [`snapbox`](https://docs.rs/snapbox) · [GitHub](https://github.com/assert-rs/snapbox)
- [`expect-test`](https://docs.rs/expect-test) · [GitHub](https://github.com/rust-analyzer/expect-test)
- [`goldie`](https://github.com/rossmacarthur/goldie)
- [`wiremock`](https://docs.rs/wiremock/) · [GitHub](https://github.com/LukeMathWalker/wiremock-rs)
- [`rexpect`](https://docs.rs/rexpect/) · [GitHub](https://github.com/rust-cli/rexpect)
