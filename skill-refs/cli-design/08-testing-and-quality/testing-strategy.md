# Testing Strategy

The CLI testing pyramid. Where each kind of test lives, what it covers, how to keep tests isolated,
and why every subcommand earns one integration test from day one.

For concrete per-language tooling (runners, snapshot libraries, property-based libraries,
mutation-testing tools, recording stubs, pre-commit and CI snippets), see the companion file
**[08a — Testing Tools](testing-tools.md)**.

## Non-negotiable principles

1. **Best practices first.** Clean, maintainable tests, written in the idioms the language community
   considers standard.
1. **Test major public APIs and core interfaces** — the behavior that defines the product, not
   incidental helpers.
1. **Test behavior and contracts, not implementation details.** Don't overfit to private internals;
   if you can refactor without changing the public contract, the test should still pass.
1. **Don't test third-party libraries.** Assume they're correct. Mock or fake them at their boundary
   (see [What to mock, what not to mock](#what-to-mock-what-not-to-mock) and
   [Detecting "testing the third-party library"](#detecting-testing-the-third-party-library)).
1. **Deterministic and fast.** Isolate side effects with fixtures; no shared state, no real clock,
   no network, no order dependence.
1. **Meaningful coverage driven by risk and impact**, not line-count. 100% coverage of trivial
   getters is wasteful; cover what breaks production.
1. **Clear names, minimal mocking, readable assertions.** A test reads as documentation of the
   contract it locks down.

Every rule below is an application of one of these.

## Test-shape models — pyramid vs trophy vs honeycomb

The pyramid is the default. Two well-known alternatives exist for codebases shaped differently from
a CLI; know when to reach for them.

| Shape         | Coined by            | Where the weight sits                                                                       | Best fit                                                                                                                         |
| ------------- | -------------------- | ------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------- |
| **Pyramid**   | Mike Cohn (2009)     | Wide base of unit tests, narrowing toward integration, thin E2E apex.                       | CLIs, libraries, monoliths with rich domain logic. **Default for everything in this guide.**                                     |
| **Trophy**    | Kent C. Dodds (2018) | Wide middle of integration tests on top of a static-analysis base; thin unit and E2E tiers. | UIs and apps whose logic is mostly orchestrating I/O across libraries — a unit test that mocks every collaborator tests nothing. |
| **Honeycomb** | Spotify (2018)       | Equal weight on intra-service unit, contract / integration, and inter-service E2E.          | Microservice fleets where complexity lives at the seams between services.                                                        |

**Decision rule:**

- If you're writing a CLI tool, a library, or anything with substantial in-process logic →
  **pyramid**.
- If you're writing a service that mostly orchestrates calls to other services → **trophy** (and
  lean on contract tests at the seams).
- If you own a fleet of services that talk to each other → **honeycomb**.

The principles in this chapter — isolation, determinism, "don't test what you don't own", behavior
over implementation — are shape-neutral. They apply equally to all three. The shape only changes
_which tier_ gets the most cycles.

Sources:
[Martin Fowler — Practical Test Pyramid](https://martinfowler.com/articles/practical-test-pyramid.html)
·
[Kent C. Dodds — The Testing Trophy](https://kentcdodds.com/blog/the-testing-trophy-and-testing-classifications)
·
[Spotify — Testing of Microservices](https://engineering.atspotify.com/2018/01/testing-of-microservices/).

## The pyramid (CLI default)

```text
▲
|   compile-fail / typestate    ◄── only when typestate exists
|
|   integration (one per subcmd) ◄── against the real binary
|
|   snapshot (structured output) ◄── inside integration suite
|
|   unit (colocated)             ◄── every module with logic
▼
```

- **Unit** — colocated tests inside each module. Cover newtype constructors, parse-shape →
  runtime-shape projection, state-machine transitions, pure pipelines. Tests live next to the code
  they test, share its visibility, and run on every change.
- **Integration** — one process-level test file per subcommand. Spawns the real binary in a
  sandboxed environment, asserts on `stdout` / `stderr` / exit code / side effects. The most
  valuable rung of the pyramid for CLIs.
- **Snapshot** — assertions on long structured output (JSON, YAML, tables, full error messages).
  Lives inside the unit and integration suites.
- **Compile-fail / typestate** — only when you have a typestate API (builder where the type changes
  per `.with_x()` call) and want to lock down invalid call sequences. Skip otherwise.

End-to-end black-box tests sit above this pyramid and run in a separate CI pipeline; they're useful
for distribution-shape and live-dependency contracts but are not a substitute for the per-subcommand
integration tests. See [E2E tests](#e2e-tests).

## Tiers at a glance

| Tier         | What it tests                                                            | External deps                                                      | Speed          | Runs in    |
| ------------ | ------------------------------------------------------------------------ | ------------------------------------------------------------------ | -------------- | ---------- |
| Unit         | One function/module in isolation                                         | None (or fully faked)                                              | ms             | pre-commit |
| Integration  | Two-or-more components together, OR your code's seam to one external dep | Stubs/fakes of the boundary, or a real contained dep               | tens of ms – s | pre-push   |
| E2E (system) | The whole product through its public CLI entry point, against real state | The actual real things (live binary, real network, real container) | s – min        | CI only    |

**The framing that trips people up: integration ≠ "touches real things." Integration = "tests the
interaction between things."**

A test that asserts your CLI wrapper passes the right argv to `podman` — with `podman` replaced by a
recording stub — is _integration_, not unit. It tests the seam between two components (your argv
builder and the subprocess executor), even though no live `podman` runs. See
[Argv-contract tests](#argv-contract-tests-for-clis-that-wrap-other-binaries).

A test that runs the real binary, which spawns real `podman`, which launches a real container —
that's _E2E_. See [E2E tests](#e2e-tests).

## Test-structure vocabulary

Use this vocabulary in commit messages, code review comments, and test names. Consistent terms let
humans and coding agents reason about test code the same way.

### FIRST — properties every test should have

- **F**ast — milliseconds; if a test is slow it stops being run.
- **I**ndependent — order doesn't matter; tests don't share state.
- **R**epeatable — same result every time, same environment or different.
- **S**elf-validating — pass/fail is a binary; no human reads output to decide.
- **T**imely — written with the code (or before it), not bolted on later.

Source: Robert C. Martin, _Clean Code_; codified in
[Agile in a Flash](http://agileinaflash.blogspot.com/2009/02/first.html).

### AAA / Given-When-Then — structure inside one test

Two names for the same shape:

- **Arrange-Act-Assert** (AAA) — the mechanical framing.
- **Given-When-Then** — the BDD framing, reads as specification prose.

Pick one per project and stick to it. Use blank lines or short comments to mark the boundaries; a
reader should never need to guess which line is the act.

```python
def test_widget_id_rejects_empty():
    # Arrange
    invalid = ""

    # Act + Assert
    with pytest.raises(ValueError):
        WidgetId.try_new(invalid)
```

### Test-doubles taxonomy (Meszaros)

When this chapter or your code review says "stub" or "fake", mean these:

| Term      | What it does                                                                                                                       |
| --------- | ---------------------------------------------------------------------------------------------------------------------------------- |
| **Dummy** | Filler that's never actually used (passed to satisfy a signature).                                                                 |
| **Stub**  | Returns canned answers. No verification.                                                                                           |
| **Spy**   | Stub that also records how it was called, so the test can assert on the calls.                                                     |
| **Mock**  | Stub with built-in expectations — verifies the call shape was as expected; fails the test if not.                                  |
| **Fake**  | A working but simplified implementation (in-memory database, recording HTTP server). Behaves correctly; just not production-grade. |

Source: Gerard Meszaros, _xUnit Test Patterns_; popularized by
[Martin Fowler — Mocks Aren't Stubs](https://martinfowler.com/articles/mocksArentStubs.html).

**The default for boundaries is a fake, not a mock.** A fake (an in-memory queue, a sqlite tempfile,
a recording HTTP server) survives refactors; a mock with rigid expectations re-asserts
implementation choices every time the test runs.

## DRY vs DAMP in tests

Production code is DRY: shared logic lives in one place. Test code is **DAMP — Descriptive And
Meaningful Phrases**. The two pull in opposite directions, and that's by design.

- **Apply DRY only to test mechanics** — fixture builders, custom matchers, sandbox helpers,
  recording-stub harnesses.
- **Keep scenarios DAMP** — the arrange/act/assert body of each test should read top-to-bottom
  without the reader chasing through helpers to learn what's being tested.

**Bad (over-DRY):**

```python
def test_widget_dry_run():
    expect_dry_run("widget", outputs="would create", state_unchanged=True)

def test_widget_apply():
    expect_apply("widget", outputs="created", state_changed=True)
```

A regression in `expect_apply` now silently breaks every test that uses it, and you cannot read what
either test actually verifies without opening the helper.

**Good (DAMP at the scenario level, DRY at the mechanic level):**

```python
def test_widget_dry_run_does_not_modify_state():
    fx = Fixture()                                  # DRY mechanic
    result = fx.cmd("widget", "--dry-run")          # DAMP scenario
    assert result.returncode == 0
    assert b"would create" in result.stdout
    assert not list(fx.work_dir.iterdir())          # DAMP assertion

def test_widget_apply_creates_widget_dir():
    fx = Fixture()
    result = fx.cmd("widget", "--name", "alpha")
    assert result.returncode == 0
    assert (fx.work_dir / "alpha").is_dir()
```

The mechanic (`Fixture`) is reused. The scenario (the argv, the assertions, the post-conditions) is
right there in front of you.

Source: Vladimir Khorikov, _Unit Testing Principles, Practices, and Patterns_ —
[DRY vs DAMP in unit tests](https://enterprisecraftsmanship.com/posts/dry-unit-tests/).

## Test isolation — the single most important rule

Every test runs in a **clean, hermetic environment**:

- Fresh temporary directory (no test ever writes to `$HOME`, the real config dir, or a shared
  fixture).
- Cleared environment variables — every CLI inherits the parent shell's env, so an active
  `RUST_LOG=trace` in your shell will break CI snapshots if tests don't scrub.
- No network calls. Mock the adapter, or use a recording library (see
  [08a — Recording / HTTP fakes](testing-tools.md#recording--http-fakes)).
- No clock dependencies. Use the abstracted `Clock` from `AppContext` so tests can pin the time.

The defense against test pollution is a shared `support/` module that builds a per-test fixture:

```python
# tests/support.py
class Fixture:
    def __init__(self):
        self.tmp = tempfile.mkdtemp()
        self.home = os.path.join(self.tmp, "home")
        os.makedirs(self.home, exist_ok=True)

    def cmd(self, *args):
        env = {"HOME": self.home, "PATH": os.environ["PATH"]}  # curated env
        return subprocess.run(["myapp", *args], env=env, capture_output=True)
```

```rust
// tests/support/mod.rs
pub struct Fixture {
    pub tmp: TempDir,
    pub home: PathBuf,
}

impl Fixture {
    pub fn cmd(&self) -> assert_cmd::Command {
        let mut c = assert_cmd::Command::cargo_bin("myapp").unwrap();
        c.env_clear()
            .env("HOME", &self.home)
            .env("PATH", std::env::var_os("PATH").unwrap());
        c
    }
}
```

`env_clear` is non-negotiable. Without it, your local shell environment leaks into every test.

## Unit tests

Live colocated, named after behavior not implementation.

```python
# src/widget.py
class WidgetId:
    @classmethod
    def try_new(cls, s: str) -> "WidgetId": ...

# tests/test_widget.py — or a `tests/` block inline if your language supports it
def test_widget_id_rejects_empty():
    with pytest.raises(ValueError):
        WidgetId.try_new("")
```

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

**Targets**:

- Every parse-shape → runtime-shape projection (one test per illegal combination).
- Every newtype constructor (boundary inputs, invalid inputs).
- Every state-machine transition (valid + invalid).
- Pure transforms (rendering, formatting, parsing).

**Non-targets**:

- Stateful integration of multiple components — that's integration territory.
- Anything that talks to a real adapter — use a fake.

## Integration tests — one per subcommand

The contract: when a developer adds subcommand `widget`, they also add `tests/cmd_widget.<ext>`. The
compiler / linter can't enforce this; code review does.

```rust
// tests/cmd_widget.rs

#[test]
fn widget_dry_run_does_not_modify_state() {
    let fixture = Fixture::new();
    fixture.cmd()
        .arg("widget").arg("--dry-run")
        .assert()
        .success()
        .stdout(predicate::str::contains("would create"));
    assert!(fixture.tmp.path().read_dir().unwrap().next().is_none());
}
```

```python
# tests/test_cmd_widget.py

def test_widget_dry_run_does_not_modify_state():
    fixture = Fixture()
    result = fixture.cmd("widget", "--dry-run")
    assert result.returncode == 0
    assert b"would create" in result.stdout
    assert not list(fixture.work_dir.iterdir())
```

**Rules**:

- One file per subcommand. Test names describe behavior, not implementation.
- Every test gets its own temp dir. Never share state.
- Use string-contains predicates for stdout matching; reserve exact-equality for tiny stable
  strings.
- Cover at least: golden path, the most common error path, the most common edge case (empty input,
  --help).

## Argv-contract tests (for CLIs that wrap other binaries)

When your CLI invokes a subprocess (`podman`, `git`, `ssh`, `kubectl`), the argv you construct _is_
a public contract. Lock it down with an integration test that replaces the child with a recording
stub and asserts on the argv:

```bash
# Replace `podman` on PATH with a stub that records argv as JSON.
fixture::with_recording_stub podman
run mycli ws up --name foo --mem 4G
[ "$status" -eq 0 ]
assert_argv_equals podman '["run","--name","foo","--memory","4G",...]'
```

This is **integration**, not unit: it tests the seam between the argv builder and the subprocess
executor. The fact that no live `podman` ran doesn't change its tier — what matters is that two
components were composed.

Cross-reference: the Rust/Zig wrapper testing patterns (`Spawner` trait, golden argv snapshots) live
in
[06 — CLI Wrapper Design § 9 Testability](../06-cli-wrapper-design/process-and-posix.md#9-testability).

## Snapshot tests

For any structured output you'd otherwise verify with a hand-maintained 20-line assertion:

```rust
#[test]
fn widget_report_renders() {
    let report = make_test_report();
    insta::assert_yaml_snapshot!(report);
}
```

```python
def test_widget_report_renders(snapshot):
    report = make_test_report()
    snapshot.assert_match(report.to_yaml(), "widget_report.yaml")
```

**When to use**:

- JSON/YAML output from `--format json`.
- Rendered tables.
- Long error messages with chains.
- CLI help text (catches accidental regressions in `--help`).

**Review snapshot diffs as carefully as code diffs** — they're behavior, not implementation noise.

See [08a — Snapshot](testing-tools.md#snapshot-testing) for `insta` / `syrupy` / `vitest`-snapshot /
`goldie` specifics and the "never auto-update snapshots in CI" rule.

## Compile-fail / typestate (optional)

Only when you have a typestate API that should reject certain call sequences at compile time. In
Rust: `trybuild`. In Python: not idiomatic; skip.

```rust
// tests/trybuild.rs
#[test]
fn ui() {
    let t = trybuild::TestCases::new();
    t.compile_fail("tests/trybuild/*.rs");
}
```

If your codebase has no typestate, omit this rung entirely. It exists to lock down a deliberate
compile-time invariant — not as general-purpose API regression catching.

## E2E tests

End-to-end tests run the whole product through its user-facing entry point against real external
systems: real subprocess execution, real network, real container runtime, real filesystem mounts.

**When to write them:**

- Distribution-shape: the binary builds, installs, and launches on every supported OS.
- Contract with a live external dependency that can't be faithfully faked (real container runtime,
  real cloud API).
- Catastrophic regressions you can't catch otherwise (e.g., the binary crashes immediately on macOS
  due to a dynamic-linker bug).

**When not to write them:**

- Anywhere an integration test with a fake would catch the same regression. E2E is the slowest,
  flakiest tier — reach for it only when fakes can't model the behavior.

**Where they run:**

- CI only. Never in pre-commit or pre-push: too slow, too dependent on host state, too flaky to gate
  local commits.
- A separate CI job from unit + integration, ideally per-OS.

**Worked example — a CLI that launches a container:**

```bash
# tests/e2e/cmd_ws_up.bats
@test "ws up launches a real krun container and exec works" {
  skip_if_no_podman
  run dctl ws up --name e2e-smoke
  [ "$status" -eq 0 ]

  run podman ps --filter name=e2e-smoke --format '{{.Status}}'
  [ "$status" -eq 0 ]
  [[ "$output" == Up* ]]

  run dctl ws exec e2e-smoke -- echo hello
  [ "$status" -eq 0 ]
  [ "$output" = "hello" ]
}

teardown() {
  podman rm -f e2e-smoke 2>/dev/null || true
}
```

The same shape applies in any language: invoke the installed binary, assert on real external state
(`podman ps`), clean up. If the test can pass without ever touching the live dependency, it isn't
E2E — relabel it integration.

## Property-based testing

For any function with an invariant — round-trip serialization, parser/unparser pairs, state-machine
transitions, sort/merge operations, anything that should hold "for all inputs of a shape" —
example-based tests scratch the surface. Property-based tests generate thousands of cases per run
and **shrink** failing inputs to a minimal counterexample.

**When to reach for it:**

- Parsers, codecs, encoders/decoders (round-trip: `decode(encode(x)) == x`).
- Pure transforms with algebraic laws (associativity, commutativity, idempotence).
- State machines (any reachable state from any starting state is consistent).
- Newtype constructors (every value the type accepts behaves under operations).
- Argv builders for wrapper CLIs (constructed argv parses back to the input model).

**When not to:**

- UI flows, side-effectful integrations — the input space is too entangled; example tests are
  clearer.
- Anything whose oracle is expensive to compute.
- Slow suites — property tests run hundreds of cases; treat the slowest properties as
  integration-tier.

```python
from hypothesis import given, strategies as st

@given(st.text())
def test_widget_id_roundtrip(s):
    if not s.strip():
        return  # explicit invariant: empty rejected
    wid = WidgetId.try_new(s)
    assert wid.as_str() == s
    assert WidgetId.try_new(wid.as_str()) == wid
```

When a property test fails, the framework shrinks the input to the smallest failing case (often a
single character or an empty list) — and you get a concrete bug, not a tangled megabyte of generated
data. **Pin the failing seed in the regression suite** so the bug stays fixed.

See [08a — Property-based testing](testing-tools.md#property-based-testing) for `proptest` /
`hypothesis` / `fast-check` / `gopter` specifics.

## Mutation testing as quality gate

Coverage measures whether your tests _executed_ a line. Mutation testing measures whether they would
have _noticed_ if the line were wrong.

The tool mutates your source (flips `<` to `<=`, replaces `+` with `-`, deletes a statement) and
re-runs the suite. Each mutant that survives — i.e., the suite still passes — is a hole in your
tests: a line that's covered but not actually checked. The score is the percentage of mutants
killed.

**Why it matters here:** AI-generated test suites are notorious for high line coverage with low
mutation score. The shape is: the agent stubs the whole dependency, asserts on the stub's recorded
calls, and never touches the project's actual logic. Coverage looks great; mutation score collapses.
The "third-party-library testing" anti-pattern below is the same failure surfaced through mutation
testing.

**When to use:**

- On critical modules (parsers, exit-code logic, security-sensitive code, state machines).
- After a big test refactor — confirms the new tests catch what the old ones did.
- Nightly in CI on the slow path. Not on every PR (mutation runs are slow).

**When not to:**

- Early prototyping — the suite churns too fast.
- Slow test suites — mutation runs N×T where N is the mutant count. Cap mutants per module.
- Generated code, trivial getters, glue.

Aim for ≥ 60% mutation score on critical modules. Treat surviving mutants like uncovered branches:
triage, fix the test or kill the mutant by adding a test.

Sources: [Stryker — Mutation testing intro](https://stryker-mutator.io/docs/) ·
[Microsoft Learn — Mutation testing](https://learn.microsoft.com/en-us/dotnet/core/testing/mutation-testing).
Tooling per language: see [08a — Mutation testing](testing-tools.md#mutation-testing).

## Detecting "testing the third-party library"

The dominant failure mode of AI-generated test suites (and a common one even without AI) is tests
that exercise a third-party library's API instead of the project's own behavior. They achieve
coverage, look thorough in a PR, and verify nothing.

Use these five heuristics — they generalize across Python, Rust, TypeScript, Go, Bash — both when
writing tests and when auditing existing ones.

### 1. Assertion subject is a non-project import

The left-hand side of the assertion is a symbol that came from `import`-ing something you don't own.

```python
# Bad — testing the json library
def test_serializes_widget():
    assert json.dumps({"id": 1}) == '{"id": 1}'

# Good — testing your serializer
def test_serializes_widget():
    assert WidgetSerializer().serialize(Widget(id=1)) == '{"id": 1}'
```

### 2. The mock is the only subject

The test fully stubs an external dependency and the assertions only check the stub's call shape. The
project code under test is bypassed entirely.

```python
# Bad — asserts on the mock, not on fetch_data's behavior
def test_fetch_data():
    m = MagicMock()
    m.get.return_value.json.return_value = {"ok": True}
    with patch("myapp.client.requests", m):
        fetch_data()
    m.get.assert_called_once_with("https://api.example.com/data")

# Good — assert on fetch_data's return value (a domain object), with a fake at the boundary
def test_fetch_data_returns_widget():
    fake_http = RecordingHttpFake.serving({"ok": True, "id": 7})
    widget = fetch_data(client=fake_http)
    assert widget == Widget(id=7)
```

### 3. Doc-mirroring

The test body reads like the library's published "usage" example with the names lightly changed. The
test code is teaching the reader how the library works, not what your code does.

If the test would still make sense pasted into the third-party library's README, it's not testing
your project.

### 4. Mocking your own pure function

You patched a project-internal pure function instead of calling it. Pure functions are the cheapest
thing in the universe to test directly.

```python
# Bad
def test_widget_handler():
    with patch("myapp.widget.serialize", return_value='{"id": 1}'):
        result = handle(Widget(id=1))
    assert result == '{"id": 1}'

# Good — call the pure function in the assertion
def test_widget_handler():
    result = handle(Widget(id=1))
    assert result == serialize(Widget(id=1))   # or assert on the literal string
```

### 5. The import-removal test

Mentally delete the third-party import the test sets up. Would the test still pass?

If **yes**, the test isn't covering the boundary between your code and the library — it's covering
the mock. Delete the test or convert it to a real integration test against a fake. If **no**, the
test does cover the boundary; keep it.

This is the most useful heuristic for review: it forces you to identify what the test is _actually_
asserting about.

---

These heuristics drive the lint rules in the
[`test-review` skill](../../../.../dotfiles/claude/.claude/skills/test-review/) (Claude planner +
Codex implementer, ships with the dotfiles). Invoke the skill on any project to audit the suite
against this principles file and produce a refactor plan.

## What to mock, what not to mock

| Subject                               | Default                                                                                                                                        |
| ------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------- |
| Filesystem                            | Real, sandboxed in tempdir. Don't mock.                                                                                                        |
| Network HTTP                          | Fake at the adapter trait. Or use a recording library (vcr-style). See [08a — Recording / HTTP fakes](testing-tools.md#recording--http-fakes). |
| Clock / time                          | Mock via the `Clock` trait on `AppContext`.                                                                                                    |
| Subprocess invocations (wrapped CLIs) | Fake at the `Process` adapter trait.                                                                                                           |
| Database                              | Use a sqlite tempfile in-process; don't run a real server in tests.                                                                            |
| Random                                | Inject a seeded RNG into `AppContext`.                                                                                                         |
| Environment variables                 | Use `env_clear` + curated env in fixtures (never modify global env in a test).                                                                 |
| CLI subprocess argv contract          | Replace the child with a recording stub; assert on argv. This is an integration test, not a unit test.                                         |
| Third-party library symbols           | Never assert on them directly — see [Detecting "testing the third-party library"](#detecting-testing-the-third-party-library).                 |

Test pollution from a live process modifying global state is the #1 source of flaky CI. Treat
`os.environ`, `chdir`, and global singletons as radioactive in tests.

## Test runner

Use a parallel-by-default runner with fail-fast and a flat summary. The complete per-language list
with rationale lives in [08a — Unit/integration runner](testing-tools.md#unit--integration-runner);
short version:

| Language      | Runner                                   |
| ------------- | ---------------------------------------- |
| Rust          | `cargo nextest`                          |
| Python        | `pytest` with `-n auto` (`pytest-xdist`) |
| Go            | `go test ./...` with `-parallel N`       |
| TypeScript/JS | `vitest`, `jest`, or `node:test`         |
| Bash          | `bats-core`                              |

Wire it through a one-liner (`just test`, `make test`, `task test`). New contributors find it
immediately.

## CI essentials

- Lint (clippy / ruff / shellcheck) → format-check (rustfmt / black / shfmt) → unit + integration
  tests → coverage gate.
- Cache the dependency build between runs.
- Run on at least one Linux + one macOS runner if the CLI is end-user-facing.
- Lock the toolchain version (`rust-toolchain.toml`, `.python-version`, `go.mod` toolchain
  directive).
- Fail loudly on warnings (`-Dwarnings` / `--strict`); don't paper over with global allows.
- **Tier-to-hook mapping**:
  - **pre-commit**: unit tests only (parallel, sub-second budget).
  - **pre-push**: unit + integration (still parallel, single-digit-seconds budget).
  - **CI**: everything — unit, integration, E2E, lint, format-check, coverage gate.
  - **CI nightly**: mutation testing on critical modules.

Ready-to-paste config snippets (pre-commit, GitHub Actions, Makefile / justfile targets) live in
[08a — Pre-commit / CI tiering](testing-tools.md#pre-commit--ci-tiering).

## Coverage philosophy

Coverage is a tool, not a goal. Aim for **behavior coverage of high-risk paths** — parse errors,
state-machine transitions, error-handling branches, public API contracts — driven by risk and
impact, not by chasing a line-count percentage.

- 100% line coverage of trivial getters or generated code is waste.
- 60% line coverage that hits every error branch and every documented exit code is excellent.
- A coverage gate in CI is fine as a _floor_ against accidental regressions; it should never be the
  metric you optimize.
- **For real test-quality signal, pair coverage with
  [mutation testing](#mutation-testing-as-quality-gate).** Coverage tells you what was executed;
  mutation testing tells you what was actually checked.

If a coverage report shows an uncovered branch in a critical path (error handling,
security-sensitive code, the exit-code matrix), add a test. If it shows uncovered branches in
trivial helpers, ignore.

## Anti-patterns

General:

- **Tests that share a temp dir.** Order-dependent, fragile, painful to debug.
- **Tests that mutate global env / cwd.** Leaks across the suite.
- **One giant integration test that runs every subcommand.** Hides which command broke. Split per
  file.
- **Mocking the filesystem.** Use a real tempdir.
- **Mocking your own pure functions.** Test them directly.
- **Letting `--help` text drift untested.** Snapshot it.
- **Skipping the integration test for "trivial" subcommands.** Trivial today, regression source
  tomorrow.
- **Sleeping in tests.** Use the abstracted `Clock` instead.
- **Over-DRY scenarios.** If a reader has to follow three helpers to learn what one test asserts,
  you've optimized for the wrong axis — see [DRY vs DAMP](#dry-vs-damp-in-tests).

LLM-era specific (the failure modes AI agents fall into most often):

- **Asserting on a third-party library's symbols** instead of on your code's behavior — see
  [heuristic 1](#1-assertion-subject-is-a-non-project-import).
- **Mock-only assertions** — the test fully stubs the dependency and only checks the mock — see
  [heuristic 2](#2-the-mock-is-the-only-subject).
- **Doc-mirroring tests** that read like the library's README — see [heuristic 3](#3-doc-mirroring).
- **Chasing line coverage** with tests that don't kill mutants — see
  [Mutation testing](#mutation-testing-as-quality-gate).

## See also

- [00 — Architecture](../00-architecture.md) — where `tests/`, `support/`, and `snapshots/` sit.
- [02 — Error Messages](../02-error-messages.md) — exit-code matrix is unit-tested.
- [05 — Designing for LLM Agents § Test-writing hazards](../05-designing-for-llm-agents.md#test-writing-hazards-for-ai-agents)
  — agent-specific failure modes.
- [06 — CLI Wrapper Design § 9 Testability](../06-cli-wrapper-design/process-and-posix.md#9-testability)
  — wrapper-specific seams (Spawner trait, golden argv).
- [08a — Testing Tools](testing-tools.md) — per-language tooling matrix and pre-commit/CI snippets.
- [99 — Checklist § Testing](../99-checklist.md#testing) — one-page sanity checklist.
- Language-specific guides:
  - [`rust/cli-spec/06-testing.md`](../../../languages/rust/cli-spec/06-testing-and-quality/testing.md)
    — `assert_cmd` + `insta` + `tempfile` + `nextest`.
  - [`python/cli-spec/typer-patterns.md`](../../../languages/python/cli-spec/typer-patterns.md) —
    `pytest` + `typer.testing.CliRunner`.
  - [`bash/cli-spec/bash-cli-project-specs.md`](../../../languages/bash/cli-spec/bash-cli-project-specs.md)
    — `bats-core`.

## References

For per-language tool URLs and pre-commit / CI snippets, see
[08a — Testing Tools](testing-tools.md#references).

Foundational reading:

- [Martin Fowler — Practical Test Pyramid](https://martinfowler.com/articles/practical-test-pyramid.html)
- [Martin Fowler — Mocks Aren't Stubs](https://martinfowler.com/articles/mocksArentStubs.html)
- [Kent C. Dodds — The Testing Trophy](https://kentcdodds.com/blog/the-testing-trophy-and-testing-classifications)
- [Spotify — Testing of Microservices (honeycomb)](https://engineering.atspotify.com/2018/01/testing-of-microservices/)
- [Hynek Schlawack — On Mocking (don't mock what you don't own)](https://hynek.me/articles/what-to-mock-in-5-mins/)
- [Vladimir Khorikov — DRY vs DAMP in unit tests](https://enterprisecraftsmanship.com/posts/dry-unit-tests/)
  · _Unit Testing Principles, Practices, and Patterns_ (Manning)
- [Google Testing Blog — Small/Medium/Large tests](https://testing.googleblog.com/2010/12/test-sizes.html)
- [Agile in a Flash — FIRST](http://agileinaflash.blogspot.com/2009/02/first.html)
- Gerard Meszaros, _xUnit Test Patterns_ — test-doubles taxonomy
- [Stryker — Mutation testing intro](https://stryker-mutator.io/docs/)
