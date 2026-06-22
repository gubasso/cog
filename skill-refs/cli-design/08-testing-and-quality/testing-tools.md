# Testing Tools

Per-language tooling reference for the principles laid out in
[08 — Testing Strategy](testing-strategy.md). Pick from the matrix; copy the snippets at the bottom
into the target project.

This file is a directory, not a tutorial. Each tool's home page is one click away; the value here is
the _selection_ and the _wiring_ (when to use what, what plays nicely with what, what to put in
`pre-commit` vs CI vs nightly).

## Opinionated defaults — "if in doubt, start here"

A new project of each shape is unlikely to go wrong starting with this stack. Replace any row when a
real constraint pushes you off it; never start from "every team uses X" alone.

| Language            | Runner                    | Snapshot                | Property-based      | Mutation        | HTTP fake          |
| ------------------- | ------------------------- | ----------------------- | ------------------- | --------------- | ------------------ |
| **Rust**            | `cargo nextest`           | `insta` (`cargo-insta`) | `proptest`          | `cargo-mutants` | `wiremock`         |
| **Python**          | `pytest` (`-n auto`)      | `syrupy`                | `hypothesis`        | `mutmut`        | `vcrpy` or `respx` |
| **TypeScript / JS** | `vitest`                  | `vitest`-snapshot       | `fast-check`        | `stryker`       | `msw`              |
| **Go**              | `go test ./...` (`-race`) | `goldie`                | `gopter` or `rapid` | `gremlins`      | `httpmock`         |
| **Bash**            | `bats-core`               | `bats` `assert_output`  | n/a (table-driven)  | n/a             | `bats-mock`        |

Cover the boundary at the architectural seams (file system stays real-but-sandboxed; HTTP gets a
fake; clock and RNG get injected from `AppContext`). The rest of the matrix below is for when a
project's needs grow past these defaults.

## Tooling matrix

### Unit / integration runner

| Lang   | Tools                                                                                                          | Notes                                                                                                                 |
| ------ | -------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------- |
| Rust   | [`cargo test`](https://doc.rust-lang.org/cargo/commands/cargo-test.html), [`cargo nextest`](https://nexte.st/) | `nextest` is parallel-by-default, fail-fast, and has a flat summary; use it.                                          |
| Python | [`pytest`](https://docs.pytest.org/), [`pytest-xdist`](https://pytest-xdist.readthedocs.io/)                   | `pytest -n auto` parallelizes across CPUs. Stick with the `pytest` default unless a library forces `unittest`.        |
| TS/JS  | [`vitest`](https://vitest.dev/), [`jest`](https://jestjs.io/), [`node:test`](https://nodejs.org/api/test.html) | `vitest` is the default for new TS projects (fast, ESM-native). `node:test` is fine for libraries with no extra deps. |
| Go     | `go test ./...`, `-parallel N`, `-race`                                                                        | Built-in; `-race` always on in CI.                                                                                    |
| Bash   | [`bats-core`](https://bats-core.readthedocs.io/)                                                               | Standard. Use `bats-assert` and `bats-support` for readable assertions.                                               |

### CLI testing

For testing the binary or runtime invocation of your CLI.

| Lang   | Tools                                                                                                                                                                                                                                                       |
| ------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Rust   | [`assert_cmd`](https://docs.rs/assert_cmd/), [`assert_fs`](https://docs.rs/assert_fs/), [`predicates`](https://docs.rs/predicates/)                                                                                                                         |
| Python | [`typer.testing.CliRunner`](https://typer.tiangolo.com/tutorial/testing/), [`click.testing.CliRunner`](https://click.palletsprojects.com/en/stable/testing/), [`subprocess`](https://docs.python.org/3/library/subprocess.html) + `pytest` for binary tests |
| TS/JS  | [`@oclif/test`](https://github.com/oclif/test), [`execa`](https://github.com/sindresorhus/execa)                                                                                                                                                            |
| Go     | `os/exec` + golden files, [`testscript`](https://pkg.go.dev/github.com/rogpeppe/go-internal/testscript)                                                                                                                                                     |
| Bash   | `bats-core` `run` builtin, fixture stubs on `PATH`                                                                                                                                                                                                          |

### Snapshot testing

| Lang   | Tools                                                                                                                | Notes                                                                 |
| ------ | -------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------- |
| Rust   | [`insta`](https://insta.rs/) (CLI: [`cargo-insta`](https://insta.rs/docs/cli/))                                      | Inline + file snapshots; `cargo insta review` for interactive triage. |
| Python | [`syrupy`](https://github.com/syrupy-project/syrupy), [`pytest-snapshot`](https://pypi.org/project/pytest-snapshot/) | `syrupy` is the modern default; pluggable serializers.                |
| TS/JS  | [`vitest`](https://vitest.dev/guide/snapshot.html) / [`jest`](https://jestjs.io/docs/snapshot-testing) snapshots     | Built-in; review diffs in PR like code.                               |
| Go     | [`goldie`](https://github.com/sebdah/goldie), [`cupaloy`](https://github.com/bradleyjkemp/cupaloy)                   | `goldie` is the most popular; `-update` flag for refresh.             |
| Bash   | `bats` `assert_output` against a checked-in golden file                                                              | Manual but trivial; commit golden files alongside the test.           |

**Rule for every snapshot tool:** never auto-update in CI. Updates happen locally, with the diff
reviewed line by line, and the PR includes both the code change and the snapshot change.

### Property-based testing

| Lang   | Tools                                                                                                        |
| ------ | ------------------------------------------------------------------------------------------------------------ |
| Rust   | [`proptest`](https://proptest-rs.github.io/proptest/intro.html), [`quickcheck`](https://docs.rs/quickcheck/) |
| Python | [`hypothesis`](https://hypothesis.readthedocs.io/)                                                           |
| TS/JS  | [`fast-check`](https://fast-check.dev/)                                                                      |
| Go     | [`gopter`](https://github.com/leanovate/gopter), [`rapid`](https://github.com/flyingmutant/rapid)            |
| Bash   | n/a — use a table-driven loop with hand-picked edge cases                                                    |

`proptest` and `hypothesis` both shrink failing inputs to a minimal counterexample and persist
failing seeds in a regression file — check that file into the repo so the regression is locked down.
See [08 § Property-based testing](testing-strategy.md#property-based-testing) for when to reach for
it.

### Mutation testing

| Lang        | Tools                                                                                          | Notes                                                          |
| ----------- | ---------------------------------------------------------------------------------------------- | -------------------------------------------------------------- |
| Rust        | [`cargo-mutants`](https://mutants.rs/)                                                         | Fast, modern, integrates with `cargo`.                         |
| Python      | [`mutmut`](https://mutmut.readthedocs.io/), [`cosmic-ray`](https://cosmic-ray.readthedocs.io/) | `mutmut` for most projects; `cosmic-ray` for distributed runs. |
| TS/JS       | [`stryker`](https://stryker-mutator.io/)                                                       | The mature option; also supports .NET, Scala.                  |
| Go          | [`gremlins`](https://gremlins.dev/)                                                            | Newer, single-binary.                                          |
| Java/Kotlin | [`PIT`](https://pitest.org/)                                                                   | Industry standard for the JVM.                                 |
| C/C++       | [`Mull`](https://mull.readthedocs.io/)                                                         | Clang plugin.                                                  |
| Bash        | n/a                                                                                            |                                                                |

**Rule:** run mutation testing nightly in CI, not on every PR. Cap mutants per module so a run
finishes in minutes. Track score per critical module; a drop is a regression in test quality even if
all tests pass. See [08 § Mutation testing](testing-strategy.md#mutation-testing-as-quality-gate).

### Recording / HTTP fakes

For the network-boundary tests where you want real wire-format behavior without hitting a live
service.

| Lang   | Tools                                                                                                                                                   | Notes                                                                                                |
| ------ | ------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------- |
| Rust   | [`wiremock`](https://docs.rs/wiremock/), [`mockito`](https://docs.rs/mockito/), [`httpmock`](https://docs.rs/httpmock/)                                 | All in-process HTTP servers.                                                                         |
| Python | [`vcrpy`](https://vcrpy.readthedocs.io/), [`respx`](https://lundberg.github.io/respx/), [`responses`](https://github.com/getsentry/responses)           | `vcrpy` records once, replays forever (commit the cassette); `respx` is request-mocking for `httpx`. |
| TS/JS  | [`msw`](https://mswjs.io/), [`nock`](https://github.com/nock/nock), [`pollyjs`](https://netflix.github.io/pollyjs/)                                     | `msw` works in both Node and the browser; `nock` is Node-only.                                       |
| Go     | [`httpmock`](https://github.com/jarcoal/httpmock), [`gock`](https://github.com/h2non/gock), [`httptest`](https://pkg.go.dev/net/http/httptest) (stdlib) | `httptest` is built-in; reach for `gock` for richer matchers.                                        |
| Bash   | `bats-mock`, hand-rolled stub script on `PATH`                                                                                                          | A 5-line shell script that records `$@` to a tmpfile is enough for argv-contract tests.              |

**Pattern:** "record once, replay forever" is the cheapest fake for HTTP. The recorded cassette goes
into version control; refreshing requires intent (a deliberate re-record commit), so silent
upstream-shape drift can't sneak into the suite.

### Contract testing

For services that talk to other services (honeycomb shape; rarely relevant to a single CLI).

| Lang   | Tools                                                                                                                                |
| ------ | ------------------------------------------------------------------------------------------------------------------------------------ |
| Rust   | [`pact-rust`](https://github.com/pact-foundation/pact-reference)                                                                     |
| Python | [`pact-python`](https://github.com/pact-foundation/pact-python)                                                                      |
| TS/JS  | [`pact-js`](https://github.com/pact-foundation/pact-js)                                                                              |
| Go     | [`pact-go`](https://github.com/pact-foundation/pact-go)                                                                              |
| Java   | [`pact-jvm`](https://github.com/pact-foundation/pact-jvm), [Spring Cloud Contract](https://spring.io/projects/spring-cloud-contract) |

Pact is the canonical consumer-driven contract framework. Out of scope for a single-binary CLI;
relevant the moment your CLI talks to a service you also own.

### Coverage

| Lang   | Tools                                                                                                               |
| ------ | ------------------------------------------------------------------------------------------------------------------- |
| Rust   | [`cargo-llvm-cov`](https://github.com/taiki-e/cargo-llvm-cov), [`tarpaulin`](https://github.com/xd009642/tarpaulin) |
| Python | [`coverage`](https://coverage.readthedocs.io/), [`pytest-cov`](https://pytest-cov.readthedocs.io/)                  |
| TS/JS  | [`c8`](https://github.com/bcoe/c8), [`istanbul`](https://istanbul.js.org/)                                          |
| Go     | `go test -cover`, `go tool cover -html=cover.out`                                                                   |
| Bash   | [`kcov`](http://simonkagstrom.github.io/kcov/), [`bashcov`](https://github.com/infertux/bashcov)                    |

Coverage as a _floor_ against accidental regressions is fine; coverage as a _goal_ is the road to
[the third-party-library testing anti-pattern](testing-strategy.md#detecting-testing-the-third-party-library).
Pair it with mutation testing for real signal.

## Pre-commit / CI tiering

The principle from [08 § CI essentials](testing-strategy.md#ci-essentials): each tier has a time
budget; assign each test type to the tier whose budget it fits.

| Tier       | Time budget      | Tests run                                |
| ---------- | ---------------- | ---------------------------------------- |
| pre-commit | < 1 s total      | Lint, format-check, unit tests only      |
| pre-push   | < 10 s total     | Lint, format, unit + integration         |
| CI (PR)    | minutes          | Everything above + E2E + coverage gate   |
| CI nightly | hours acceptable | Mutation testing + slower property tests |

### Tuning test-runner output for CI + AI agents

CI logs and agent-read transcripts both pay a token cost for noise that a human-in-the-terminal
would skim past. Most test runners can be tuned along the same axes; the concrete keys differ per
tool, but the pattern is uniform. See your runner's reference for the exact configuration mechanism
(e.g. `[profile.X]` in nextest's `.config/nextest.toml`, `[tool.pytest.ini_options]` plus `-c` in
pytest, `vitest.config.*` plus `--config`, jest's `--config`, `go test -tags`).

**Foot-gun — profiles/presets are dead config unless invoked explicitly.** Most runners load a
_default_ profile/config and ignore the per-stage one until the invocation passes the right flag.
Pattern: pre-commit, pre-push, and CI each invoke the runner with the matching
`--profile`/`--config`/preset name. A workflow that runs the bare command silently falls back to
defaults and ignores every retry, timeout, and output tweak you encoded for that stage. This is the
single most common reason CI behaves nothing like the config that "should" be active.

**Four output axes that govern token efficiency.** Every reasonable test runner exposes these, even
if the keys are named differently:

| Axis                                    | Token-efficient value                                        | Why                                                                                                                    |
| --------------------------------------- | ------------------------------------------------------------ | ---------------------------------------------------------------------------------------------------------------------- |
| Per-test status during execution        | Show **failures only**, suppress pass lines                  | A 5k-test suite that prints one line per pass is 5k lines of noise; agents and reviewers triage from the failure list. |
| End-of-run summary                      | **Failures only**, not the full pass roll-up                 | The summary's job is "what broke", not "what worked".                                                                  |
| Captured stdout/stderr of passing tests | **Never display**                                            | Passing tests' chatter is noise by definition.                                                                         |
| Captured stdout/stderr of failing tests | **Always display**, ideally both inline AND in final summary | Agents triaging a failure find the output wherever they're looking.                                                    |

**Progress bars in captured logs.** Most runners auto-suppress progress redraws when stdout is not a
TTY (GitHub Actions et al. detect this correctly). Some CI systems emulate a TTY — when they do, the
redraw stream bloats captured logs. Look for a `--no-progress` / `--reporter=dot` /
`HIDE_PROGRESS=1`-style escape hatch and set it in CI env as belt-and-suspenders.

**Layered presets by hook stage.** Pair the four output axes with the tier table above:

- _pre-commit_ — fail-fast on, run unit only, quietest output (failure on a single test should kill
  the run immediately).
- _pre-push_ — fail-fast off, run unit + integration, still quiet (surface every regression, not
  just the first).
- _CI_ — fail-fast off, run everything, retries for known-flaky network tests, quietest output (logs
  are read by humans and agents long after the run).
- _interactive/ad-hoc_ — verbosity OK; this is the one tier where pass lines and progress bars carry
  signal.

**Machine-readable output for downstream parsers.** When an agent or dashboard consumes test
results, prefer the runner's structured-output format (JUnit XML, TAP, JSON event streams like
libtest-json) over scraping human text. Don't enable it prophylactically — adopt it the moment
something downstream actually parses it.

**No first-class "AI mode" exists in any major runner** as of late 2025. The composition above is
hand-rolled across tools. If a runner ever ships a `--quiet-for-agents` preset, prefer that to a
hand-tuned profile.

For the concrete keys, profile names, and reference TOML in each language, see the per-language
testing spec — Rust:
[cli-spec § Test runner](../../../languages/rust/cli-spec/06-testing-and-quality/testing.md#test-runner).

### `.pre-commit-config.yaml` — fast unit tests on every commit

Copy into the target project's `.pre-commit-config.yaml`:

```yaml
repos:
  # Python
  - repo: local
    hooks:
      - id: pytest-unit
        name: pytest (unit)
        entry: pytest
        language: system
        args: [tests/unit, -x, -q, -n, auto]
        types: [python]
        pass_filenames: false
        stages: [pre-commit]

  # Rust
  - repo: local
    hooks:
      - id: cargo-nextest-unit
        name: cargo nextest (unit, pre-commit profile)
        entry: cargo
        language: system
        # Profiles live in .config/nextest.toml. Without `--profile pre-commit`
        # nextest silently uses `[profile.default]` and ignores the unit-only
        # filterset, fail-fast, and quieter status-level configured for this tier.
        args: [nextest, run, --profile, pre-commit]
        types_or: [rust, toml]
        pass_filenames: false
        stages: [pre-commit]

  # TypeScript
  - repo: local
    hooks:
      - id: vitest-unit
        name: vitest run (unit)
        entry: pnpm
        language: system
        args: [vitest, run, --reporter=dot, src/]
        types: [ts]
        pass_filenames: false
        stages: [pre-commit]

  # Bash
  - repo: local
    hooks:
      - id: bats-unit
        name: bats (unit)
        entry: bats
        language: system
        args: [tests/unit]
        types: [shell]
        pass_filenames: false
        stages: [pre-commit]
```

Match exactly one block to your project's language; delete the rest. Add a `pre-push` block with the
integration suite — same shape, just `stages: [pre-push]` and the integration directory.

### `pre-push` — integration tests

```yaml
- repo: local
  hooks:
    - id: pytest-integration
      name: pytest (integration)
      entry: pytest
      language: system
      args: [tests/integration, -q, -n, auto]
      types: [python]
      pass_filenames: false
      stages: [pre-push]
```

### `Makefile` / `justfile` target for mutation testing

A `make mutate` (or `just mutate`) entry point keeps the invocation discoverable and consistent. The
target's command differs by language; the _interface_ is uniform.

```makefile
# Makefile

.PHONY: test test-unit test-integration test-e2e mutate cover

test:        ; @$(MAKE) test-unit && $(MAKE) test-integration
test-unit:   ; pytest tests/unit -n auto
test-integration: ; pytest tests/integration -n auto
test-e2e:    ; pytest tests/e2e
cover:       ; pytest --cov=myapp --cov-report=term-missing
mutate:      ; mutmut run && mutmut results
```

```just
# justfile

test:               (test-unit) (test-integration)
test-unit:          pytest tests/unit -n auto
test-integration:   pytest tests/integration -n auto
test-e2e:           pytest tests/e2e
cover:              pytest --cov=myapp --cov-report=term-missing
mutate:             mutmut run && mutmut results
```

Rust equivalent:

```just
test:        cargo nextest run
test-int:    cargo nextest run --test '*'
cover:       cargo llvm-cov --all-features --workspace --lcov --output-path lcov.info
mutate:      cargo mutants --in-place --no-shuffle
```

### GitHub Actions — nightly mutation testing

Mutation runs are slow; put them on a schedule, not on every PR.

```yaml
# .github/workflows/mutation.yml
name: mutation-testing
on:
  schedule: [{ cron: '0 4 * * *' }]   # 04:00 UTC daily
  workflow_dispatch: {}                 # manual trigger from the Actions tab

jobs:
  mutate:
    runs-on: ubuntu-latest
    timeout-minutes: 120
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with: { python-version: '3.x' }
      - run: pip install -e . mutmut
      - run: mutmut run --paths-to-mutate=src/myapp || true
      - run: mutmut results
      - name: Upload report
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: mutation-report
          path: .mutmut-cache
```

The `|| true` is intentional — surviving mutants are reported, not fatal. Treat the report as a
quality metric to triage, not a gate. Once the score is stable on a critical module, you can promote
that module to gated.

### Test-isolation enforcement snippets

For each language, a snippet that enforces the "no shared state, no global env, no real clock" rules
from [08 § Test isolation](testing-strategy.md#test-isolation--the-single-most-important-rule).

**Python — `conftest.py`:**

```python
# tests/conftest.py
import os
import pytest

CURATED_ENV = {"PATH", "HOME", "LANG", "TZ"}

@pytest.fixture(autouse=True)
def isolate_env(monkeypatch, tmp_path):
    """Every test gets a scrubbed env and a fresh HOME pointing at tmp_path."""
    monkeypatch.setenv("HOME", str(tmp_path))
    for key in list(os.environ):
        if key not in CURATED_ENV:
            monkeypatch.delenv(key, raising=False)
    yield
```

**Rust — `tests/support/fixture.rs`:**

```rust
use assert_cmd::Command;
use std::env;
use tempfile::TempDir;

pub struct Fixture {
    pub tmp: TempDir,
}

impl Fixture {
    pub fn new() -> Self {
        Self { tmp: TempDir::new().unwrap() }
    }

    pub fn cmd(&self) -> Command {
        let mut c = Command::cargo_bin(env!("CARGO_PKG_NAME")).unwrap();
        c.env_clear()
            .env("HOME", self.tmp.path())
            .env("PATH", env::var_os("PATH").unwrap());
        c
    }
}
```

**Bash — `tests/setup.bash`:**

```bash
# tests/setup.bash — sourced by every .bats file
setup() {
  TMPDIR="$(mktemp -d)"
  export HOME="$TMPDIR"
  export XDG_CONFIG_HOME="$TMPDIR/.config"
  export PATH="$BATS_TEST_DIRNAME/../stubs:$PATH"
  unset LANG TZ RUST_LOG PYTHONPATH 2>/dev/null || true
}

teardown() {
  rm -rf "$TMPDIR"
}
```

## Tool selection by failure mode

When the symptom is X, reach for tool Y. Pairing this with the heuristics in
[08 § Detecting "testing the third-party library"](testing-strategy.md#detecting-testing-the-third-party-library)
covers the most common test-quality failures.

| Symptom                                                                              | Likely cause                                                                                      | Tool / pattern to reach for                                          |
| ------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------- |
| High coverage, regressions still slip through                                        | Tests cover lines but don't check behavior.                                                       | **Mutation testing** (`stryker`, `mutmut`, `cargo-mutants`).         |
| Flaky integration tests on CI but not locally                                        | Test pollution: shared env, shared tmpdir, real clock.                                            | **Isolation snippets** above + `env_clear` discipline.               |
| HTTP tests break the moment the upstream service is down                             | Live network calls in the suite.                                                                  | **Recording fakes** (`vcrpy`, `msw`, `wiremock`).                    |
| Test file is 90% setup, 10% assertions                                               | Over-DRY scenarios, or every test rebuilds the world.                                             | **DAMP refactor** + a single shared `Fixture` mechanic.              |
| Hand-written assertion for every field of a 30-field struct                          | Brittle, painful, drifts from reality.                                                            | **Snapshot testing** (`insta`, `syrupy`, `vitest`-snap).             |
| Parser handles "common" inputs but crashes on weird ones                             | Example tests miss the input space.                                                               | **Property-based testing** (`proptest`, `hypothesis`, `fast-check`). |
| Wrapper CLI passed the wrong argv to the child after a refactor                      | argv builder isn't pinned.                                                                        | **Argv-contract tests** + recording stub on `PATH`.                  |
| Test asserts on `mock.call_args` and never on the SUT's return value                 | The mock is the only subject — [heuristic 2](testing-strategy.md#2-the-mock-is-the-only-subject). | **Rewrite with a fake at the boundary**, assert on the return value. |
| AI-generated test file with 100% coverage but readers can't tell what's being tested | Doc-mirroring + over-stubbing — [heuristics 3 & 4](testing-strategy.md#3-doc-mirroring).          | **Run the `test-review` skill**; refactor against the heuristics.    |

## References

Per-tool documentation links are inline in the matrix above. For _why_ you'd reach for each tool
category, see the cross-references back to [08 — Testing Strategy](testing-strategy.md):

- [§ Non-negotiable principles](testing-strategy.md#non-negotiable-principles)
- [§ Test-shape models](testing-strategy.md#test-shape-models--pyramid-vs-trophy-vs-honeycomb)
- [§ Test-structure vocabulary](testing-strategy.md#test-structure-vocabulary)
- [§ DRY vs DAMP in tests](testing-strategy.md#dry-vs-damp-in-tests)
- [§ Detecting "testing the third-party library"](testing-strategy.md#detecting-testing-the-third-party-library)
- [§ Mutation testing as quality gate](testing-strategy.md#mutation-testing-as-quality-gate)
- [§ Property-based testing](testing-strategy.md#property-based-testing)
- [§ CI essentials](testing-strategy.md#ci-essentials)
