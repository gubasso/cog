# Code Quality Tools

Per-language tooling reference for the structural quality gates described in
[10 — Regression Safeguards](regression-safeguards.md). This file covers the **non-testing** quality
gates: complexity metrics, dependency hygiene, binary analysis, architectural enforcement, dead code
detection, and code churn tracking.

For testing tools (runners, snapshot, property-based, mutation, recording, contract), see
**[08a — Testing Tools](testing-tools.md)**.

## Opinionated defaults — "if in doubt, start here"

| Language            | Complexity             | Unused deps     | Security/license | Binary size         | Benchmarking     |
| ------------------- | ---------------------- | --------------- | ---------------- | ------------------- | ---------------- |
| **Rust**            | `rust-code-analysis`   | `cargo-machete` | `cargo-deny`     | `cargo-bloat`       | `criterion`      |
| **Python**          | `radon` + `flake8`     | `deptry`        | `pip-audit`      | n/a                 | `pytest-bench`   |
| **TypeScript / JS** | `eslint` (complexity)  | `depcheck`      | `npm audit`      | `size-limit`        | `vitest bench`   |
| **Go**              | `gocyclo` + `gocognit` | `depguard`      | `govulncheck`    | `go build -ldflags` | `go test -bench` |
| **Bash**            | `shellcheck`           | n/a             | n/a              | n/a                 | n/a              |

## Complexity metrics

Complexity metrics measure how hard code is to understand and maintain. The two most useful metrics
for catching AI-agent overengineering:

- **Cognitive complexity** (Sonar model): measures how hard a function is for a human to understand.
  Penalizes nesting, breaks in linear flow, and boolean operator mixing. The best single metric for
  flagging AI-generated spaghetti.
- **Cyclomatic complexity** (McCabe): counts linearly independent paths through a function. Classic
  metric; useful but doesn't penalize nesting depth.

Additional metrics worth tracking on critical modules:

- **Halstead metrics** — effort, difficulty, estimated bugs, time to implement. Derived from
  operator/operand counts.
- **LLOC** (Logical Lines of Code) — statements, not blank lines. Sudden jumps signal bloat.
- **Maintainability Index** — combined metric (Halstead + cyclomatic + LLOC); single number for
  overall health.
- **NARGS** — function argument count. Functions with > 5 arguments often need a struct.
- **NEXITS** — exit points (returns, panics, early returns). Many exits increase cognitive load.

### Thresholds

These are starting points; calibrate to your codebase:

| Metric                | Green     | Yellow | Red (fail CI) |
| --------------------- | --------- | ------ | ------------- |
| Cognitive complexity  | <= 15     | 16–25  | > 25          |
| Cyclomatic complexity | <= 10     | 11–20  | > 20          |
| Function length       | <= 60 LOC | 61–100 | > 100         |
| NARGS                 | <= 5      | 6–7    | > 7           |

**Enforcement pattern:** run on modified files in pre-push; run on all files nightly. Fail CI only
on red thresholds. Yellow thresholds produce warnings in the PR comment.

### Per-language tools

| Language | Tool                                                                                    | Metrics                                          | Notes                                                               |
| -------- | --------------------------------------------------------------------------------------- | ------------------------------------------------ | ------------------------------------------------------------------- |
| Rust     | [`rust-code-analysis`](https://github.com/mozilla/rust-code-analysis)                   | CC, cognitive, Halstead, LLOC, MI, NARGS, NEXITS | Mozilla. CLI: `rust-code-analysis-cli`. JSON output.                |
| Rust     | [`complexity`](https://github.com/rossmacarthur/complexity) crate                       | Cognitive only                                   | Lightweight; embeddable in custom lints.                            |
| Rust     | `clippy` `cognitive_complexity` lint                                                    | Cognitive (built into clippy)                    | Threshold via `clippy.toml`: `cognitive-complexity-threshold = 25`. |
| Rust     | `clippy` `too_many_lines` lint                                                          | Function length                                  | Threshold via `clippy.toml`: `too-many-lines-threshold = 100`.      |
| Python   | [`radon`](https://radon.readthedocs.io/)                                                | CC, Halstead, MI, raw LOC                        | `radon cc -s -a` for per-function CC.                               |
| Python   | [`flake8-cognitive-complexity`](https://github.com/Melevir/flake8-cognitive-complexity) | Cognitive                                        | Plugin for flake8 / ruff.                                           |
| Python   | [`wily`](https://github.com/tonybaloney/wily)                                           | CC, MI, Halstead over time (git history)         | Tracks trends; detects drift.                                       |
| TS/JS    | [`eslint` complexity rule](https://eslint.org/docs/rules/complexity)                    | CC                                               | Built-in; set `"complexity": ["error", 15]`.                        |
| TS/JS    | [`eslint-plugin-sonarjs`](https://github.com/SonarSource/eslint-plugin-sonarjs)         | Cognitive                                        | Sonar's cognitive complexity model as an ESLint plugin.             |
| Go       | [`gocyclo`](https://github.com/fzipp/gocyclo)                                           | CC                                               | `gocyclo -over 15 .` to flag high-CC functions.                     |
| Go       | [`gocognit`](https://github.com/uudashr/gocognit)                                       | Cognitive                                        | Same interface as gocyclo but cognitive model.                      |
| Bash     | No dedicated tool; ShellCheck catches some complexity symptoms (nested `if`).           | —                                                | Enforce function length manually.                                   |

### Usage pattern (CI)

```bash
# Rust — fail on cognitive complexity > 25 in any function
rust-code-analysis-cli --metrics -O json -p src/ \
  | jq -e '[.[] | select(.metrics.cognitive.average > 25)] | length == 0'

# Python — fail on CC grade C or worse
radon cc src/ -s -n C --total-average \
  && echo "OK" || exit 1

# Go — fail on cyclomatic complexity > 15
gocyclo -over 15 . && echo "OK" || exit 1
```

## Restriction lints

Beyond standard linting (format + correctness), restriction lints catch patterns AI agents commonly
leave behind. These are cheap to run and should be in pre-commit.

### What to restrict

| Pattern                  | Why it's dangerous                               | Rust lint                  | Python (ruff)        |
| ------------------------ | ------------------------------------------------ | -------------------------- | -------------------- |
| `todo!()` / `TODO`       | Unfinished code in production.                   | `clippy::todo`             | `FIX001` / `TD003`   |
| `dbg!()` / debug prints  | Debug output leaking to users.                   | `clippy::dbg_macro`        | `T201` (`print`)     |
| `unwrap()` / bare except | Panic on error instead of handling.              | `clippy::unwrap_used`      | `B001` (bare except) |
| `panic!()` / `exit()`    | Abrupt termination without cleanup.              | `clippy::panic`            | —                    |
| `unimplemented!()`       | Stub code in production.                         | `clippy::unimplemented`    | —                    |
| Wildcard imports         | Namespace pollution; hides what's actually used. | `clippy::wildcard_imports` | `F403`               |
| `unsafe` blocks          | Memory safety bypass.                            | `unsafe_code = "forbid"`   | —                    |

### Configuration

**Rust** (`Cargo.toml`):

```toml
[lints.rust]
unused_must_use = "deny"
unsafe_code     = "forbid"

[lints.clippy]
pedantic        = { level = "warn", priority = -1 }
nursery         = { level = "warn", priority = -1 }
todo            = "deny"
dbg_macro       = "deny"
unwrap_used     = "deny"
panic           = "deny"
unimplemented   = "deny"
```

**Rust** (`clippy.toml` / `.clippy.toml`):

```toml
cognitive-complexity-threshold = 25
too-many-lines-threshold = 100
```

**Python** (`pyproject.toml`):

```toml
[tool.ruff.lint]
select = ["E", "F", "B", "S", "C90", "RUF"]

[tool.ruff.lint.mccabe]
max-complexity = 15

[tool.ruff.lint.pylint]
max-args = 7
```

**Go** (`.golangci.yml`):

```yaml
linters:
  enable:
    - gocyclo
    - gocognit
    - funlen
    - nestif
linters-settings:
  gocyclo:
    min-complexity: 15
  funlen:
    lines: 100
  nestif:
    min-complexity: 5
```

## Unused dependency detection

Unused dependencies are a common AI-agent artifact: the agent adds a crate to solve a subproblem,
then refactors the solution to not need it, but forgets to remove the dependency.

| Language | Tool                                                       | Approach              | Speed  | Notes                                              |
| -------- | ---------------------------------------------------------- | --------------------- | ------ | -------------------------------------------------- |
| Rust     | [`cargo-machete`](https://github.com/bnjbvr/cargo-machete) | Grep for crate names  | Fast   | Stable Rust. Occasional false positives on macros. |
| Rust     | [`cargo-udeps`](https://github.com/est31/cargo-udeps)      | Compiler analysis     | Medium | Requires nightly. More precise.                    |
| Python   | [`deptry`](https://github.com/fpgmaas/deptry)              | AST + import analysis | Fast   | Modern replacement for `pipdeptree`.               |
| TS/JS    | [`depcheck`](https://github.com/depcheck/depcheck)         | Import analysis       | Fast   | Handles CJS + ESM.                                 |
| Go       | `go mod tidy` (built-in)                                   | Compiler analysis     | Fast   | Part of the standard toolchain.                    |

**Tier placement:** `cargo-machete` / `deptry` / `depcheck` in pre-commit (fast enough).
`cargo-udeps` in nightly CI (requires nightly, slower).

**Configuration** (`Cargo.toml` for machete):

```toml
[package.metadata.cargo-machete]
ignored = ["tracing"]  # used via macros only, machete can't see it
```

## Security and license auditing

| Language | Tool                                                                  | What it checks                            | Notes                                                |
| -------- | --------------------------------------------------------------------- | ----------------------------------------- | ---------------------------------------------------- |
| Rust     | [`cargo-deny`](https://github.com/EmbarkStudios/cargo-deny)           | CVEs, licenses, bans, duplicates, sources | Comprehensive policy engine. Subsumes `cargo-audit`. |
| Rust     | [`cargo-audit`](https://rustsec.org/)                                 | CVEs only (RustSec advisory DB)           | Simpler; use `cargo-deny` for full policy.           |
| Python   | [`pip-audit`](https://github.com/pypa/pip-audit)                      | CVEs (OSV database)                       | Official PyPA tool.                                  |
| TS/JS    | `npm audit` / `pnpm audit`                                            | CVEs (npm advisory DB)                    | Built-in.                                            |
| Go       | [`govulncheck`](https://pkg.go.dev/golang.org/x/vuln/cmd/govulncheck) | CVEs (Go Vulnerability Database)          | Official Go team tool.                               |

**Tier placement:** pre-push (fast, catches serious issues before they reach CI).

**Configuration** (`deny.toml` for cargo-deny):

```toml
[advisories]
vulnerability = "deny"
unmaintained = "warn"
unsound = "warn"
yanked = "warn"

[licenses]
allow = ["MIT", "Apache-2.0", "BSD-2-Clause", "BSD-3-Clause", "ISC", "Zlib"]
deny = ["GPL-2.0", "GPL-3.0", "AGPL-3.0"]

[bans]
deny = [
    { name = "openssl-sys" },  # prefer rustls
]
```

## Binary size analysis

Binary size is a proxy for complexity. Sudden growth often indicates added dependencies, excessive
monomorphization (generics bloat), or unnecessary features. Track it to catch AI-introduced bloat
early.

| Language | Tool                                                       | What it shows                             | Notes                                 |
| -------- | ---------------------------------------------------------- | ----------------------------------------- | ------------------------------------- |
| Rust     | [`cargo-bloat`](https://github.com/RazrFalcon/cargo-bloat) | Per-function and per-crate size breakdown | `--release` for meaningful numbers.   |
| TS/JS    | [`size-limit`](https://github.com/ai/size-limit)           | Bundle size with budget enforcement       | Integrates with CI via GitHub Action. |
| Go       | `go build -ldflags` + `bloaty`                             | Section and symbol-level analysis         | `bloaty` is language-agnostic (ELF).  |

**CI integration pattern:**

```bash
# Baseline (main branch, cached in CI artifacts)
cargo bloat --release --crates -n 0 --wide > baseline-bloat.txt

# PR branch
cargo bloat --release --crates -n 0 --wide > pr-bloat.txt

# Compare total binary size; fail on > 5% growth
BASELINE=$(grep 'file-size' baseline-bloat.txt | awk '{print $2}')
CURRENT=$(grep 'file-size' pr-bloat.txt | awk '{print $2}')
# ... threshold comparison logic
```

**Continuous tracking:** [Bencher](https://bencher.dev/) tracks binary size (and benchmarks) across
commits with statistical regression detection. See
[10a § Continuous benchmarking](#continuous-benchmarking).

## Architectural boundary enforcement

Architectural boundaries prevent layer violations — `cli/` importing from `domain/` internals,
`domain/` making I/O calls, `commands/` bypassing `services/`. In languages with strong module
systems (Rust, Go), the compiler enforces visibility. The gap is at the logical layer level: the
compiler doesn't know that `adapters/` is the only place that should make HTTP calls.

### Approaches by language

| Language | Primary tool                             | Notes                                                                   |
| -------- | ---------------------------------------- | ----------------------------------------------------------------------- |
| Rust     | `pub(crate)` / `pub(super)` + grep lints | Compiler enforces visibility; grep-based rules enforce layer semantics. |
| Python   | `import-linter`                          | Declarative layer contracts in `pyproject.toml`.                        |
| TS/JS    | `eslint-plugin-boundaries`               | Define zones and allowed imports via ESLint config.                     |
| Go       | `depguard` (via `golangci-lint`)         | Allowlist/blocklist imports per package.                                |
| Java     | `ArchUnit`                               | The gold standard; nothing this mature exists elsewhere.                |

### Rust pattern: grep-based boundary checks

```bash
# domain/ must not import from adapters/ or services/
! rg -n 'use crate::adapters' src/domain/ 2>/dev/null
! rg -n 'use crate::services' src/domain/ 2>/dev/null

# cli/ must not import from ui/ internals
! rg -n 'use crate::ui::' src/cli/ 2>/dev/null

# No print statements outside ui/ and error.rs
! rg -n '(println!|print!|eprint(ln)?!)' \
    --glob '!src/ui/**' --glob '!src/error.rs' --glob '!src/logging.rs' \
    --glob '!tests/**' src/
```

Add these as a `justfile` recipe (`just lint-boundaries`) and wire into pre-commit. They're fast,
deterministic, and catch the most common layer violations.

## Dead code detection

| Language | Tool                                                 | Notes                                                       |
| -------- | ---------------------------------------------------- | ----------------------------------------------------------- |
| Rust     | `#[warn(dead_code)]` (built-in)                      | Compiler catches unused functions/types. Enable by default. |
| Rust     | [`warnalyzer`](https://github.com/est31/warnalyzer)  | Cross-crate dead code analysis. Experimental.               |
| Python   | [`vulture`](https://github.com/jendrikseipp/vulture) | Finds unused code via AST analysis.                         |
| TS/JS    | [`ts-prune`](https://github.com/nadeesha/ts-prune)   | Finds unused exports.                                       |
| Go       | `go vet` + `staticcheck` (unused analyzer)           | Built into the standard toolchain.                          |

**Rust note:** `#![allow(dead_code)]` at the crate root should never appear in production code.
Scope `allow` to the specific item with a justifying comment. See
[rust/cli-spec/09 § No crate-root allow](../../../languages/rust/cli-spec/09-coding-style.md#4-no-crate-root-allowdead_code).

## Code metrics and churn tracking

Track LLOC, comment ratio, and file size trends over time. Sudden changes correlate with AI-agent
bulk edits.

| Language | Tool                                           | Output formats   | Notes                                     |
| -------- | ---------------------------------------------- | ---------------- | ----------------------------------------- |
| Any      | [`tokei`](https://github.com/XAMPPRocky/tokei) | JSON, YAML, TOML | Fast, accurate LOC counting by language.  |
| Any      | [`scc`](https://github.com/boyter/scc)         | JSON, CSV, HTML  | Includes complexity estimates and COCOMO. |

**Usage:**

```bash
# Machine-readable LLOC for CI tracking
tokei . --output json | jq '.Rust.code'

# Full report with complexity
scc --format json .
```

**CI pattern:** compare LLOC between `main` and the PR branch. A PR that adds > 500 LLOC to a single
module is a review flag, not an automatic failure.

## Continuous benchmarking

Performance regressions are invisible without benchmarks. AI agents routinely introduce O(n^2)
loops, unnecessary allocations, and redundant clones that look correct but perform poorly.

| Language | Benchmark framework                                                   | CI tracking                     |
| -------- | --------------------------------------------------------------------- | ------------------------------- |
| Rust     | [`criterion`](https://bheisler.github.io/criterion.rs/book/)          | [Bencher](https://bencher.dev/) |
| Rust     | [`divan`](https://github.com/nvzqz/divan)                             | Bencher (adapters exist)        |
| Python   | [`pytest-benchmark`](https://pytest-benchmark.readthedocs.io/)        | Bencher, Codspeed               |
| Go       | `go test -bench` (built-in)                                           | Bencher                         |
| TS/JS    | [`vitest bench`](https://vitest.dev/guide/features.html#benchmarking) | Bencher                         |

[**Bencher**](https://bencher.dev/) is a continuous benchmarking service that tracks results across
commits, detects statistical regressions, and integrates with GitHub via PR comments. It supports
adapters for all major benchmark frameworks.

**Tier placement:** nightly CI. Benchmarks are too slow for pre-commit/pre-push. Statistical
regression detection needs a history of measurements, so run consistently.

## Pre-commit / CI integration

### justfile pattern (Rust)

```just
# --- Quality gates (structural) ---

lint-complexity:
    rust-code-analysis-cli --metrics -O json -p src/ \
      | jq -e '[.[] | select(.metrics.cognitive.average > 25)] | length == 0'

lint-boundaries:
    @! rg -n 'use crate::adapters' src/domain/ 2>/dev/null
    @! rg -n 'use crate::services' src/domain/ 2>/dev/null
    @! rg -n '(println!|print!|eprint(ln)?!)' \
        --glob '!src/ui/**' --glob '!src/error.rs' --glob '!src/logging.rs' \
        --glob '!tests/**' src/

lint-all: lint lint-complexity lint-boundaries

# --- Dependency hygiene ---

machete:
    cargo machete

deny:
    cargo deny check

audit: deny machete

# --- Binary analysis ---

bloat:
    cargo bloat --release --crates -n 20

# --- Nightly ---

mutate:
    cargo mutants --test-tool nextest

bench:
    cargo bench
```

### `.pre-commit-config.yaml` additions

```yaml
# Structural quality gates (add to existing config)
- repo: local
  hooks:
    - id: cargo-machete
      name: unused deps
      entry: cargo machete
      language: system
      types: [toml]
      pass_filenames: false

    - id: lint-boundaries
      name: layer boundaries
      entry: just lint-boundaries
      language: system
      types: [rust]
      pass_filenames: false
```

### GitHub Actions — nightly quality gates

```yaml
# .github/workflows/quality.yml
name: quality-gates
on:
  schedule: [{ cron: '0 4 * * *' }]
  workflow_dispatch: {}

jobs:
  mutation:
    runs-on: ubuntu-latest
    timeout-minutes: 120
    steps:
      - uses: actions/checkout@v4
      - run: cargo install cargo-mutants
      - run: cargo mutants --test-tool nextest
      - uses: actions/upload-artifact@v4
        if: always()
        with:
          name: mutation-report
          path: mutants.out/

  complexity:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: cargo install rust-code-analysis-cli
      - run: |
          rust-code-analysis-cli --metrics -O json -p src/ > complexity.json
          jq -e '[.[] | select(.metrics.cognitive.average > 25)] | length == 0' \
            complexity.json
      - uses: actions/upload-artifact@v4
        if: always()
        with:
          name: complexity-report
          path: complexity.json
```

## See also

- [10 — Regression Safeguards](regression-safeguards.md) — principles and layering model.
- [08a — Testing Tools](testing-tools.md) — testing tool matrix (runners, snapshot, mutation,
  property-based, recording).
- [04 — Coding Style](../04-coding-style-rust-zig.md) § 16 — strict lints.
- [99 — Checklist](../99-checklist.md) — one-page sanity check.
- Language-specific guides:
  - [`rust/cli-spec/06b-code-quality.md`](../../../languages/rust/cli-spec/06-testing-and-quality/code-quality.md)
    — Rust config and integration details.

## References

- [rust-code-analysis](https://github.com/mozilla/rust-code-analysis) ·
  [docs](https://mozilla.github.io/rust-code-analysis/)
- [radon](https://radon.readthedocs.io/) · [gocyclo](https://github.com/fzipp/gocyclo) ·
  [gocognit](https://github.com/uudashr/gocognit)
- [cargo-deny](https://github.com/EmbarkStudios/cargo-deny) ·
  [cargo-machete](https://github.com/bnjbvr/cargo-machete) ·
  [cargo-udeps](https://github.com/est31/cargo-udeps)
- [cargo-bloat](https://github.com/RazrFalcon/cargo-bloat) · [Bencher](https://bencher.dev/)
- [tokei](https://github.com/XAMPPRocky/tokei) · [scc](https://github.com/boyter/scc)
- [clippy lint database](https://rust-lang.github.io/rust-clippy/master/index.html) ·
  [clippy.toml reference](https://doc.rust-lang.org/clippy/lint_configuration.html)
- [criterion](https://bheisler.github.io/criterion.rs/book/) ·
  [divan](https://github.com/nvzqz/divan)
