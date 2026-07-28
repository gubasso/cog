# Code Quality (Rust)

> Prerequisite: [09 — Coding Style (Rust)](../09-coding-style.md) for lint basics (`pedantic`, `nursery`, `unwrap_used`, `expect_used`). This chapter covers Rust-specific code quality tooling beyond linting: complexity metrics, restriction lints, binary size analysis, unused dependency detection, and architectural boundary enforcement.
>
> General principles: [10 — Regression Safeguards](../../../../cli-design/08-testing-and-quality/regression-safeguards.md) · [10a — Code Quality Tools](../../../../cli-design/08-testing-and-quality/code-quality-tools.md).

## Tool stack

| Concern                       | Tool                     | Tier          | Install                                |
| ----------------------------- | ------------------------ | ------------- | -------------------------------------- |
| Complexity metrics            | `rust-code-analysis-cli` | Pre-push / CI | `cargo install rust-code-analysis-cli` |
| Clippy restriction lints      | `clippy` (built-in)      | Pre-commit    | Bundled with rustup.                   |
| Clippy complexity thresholds  | `clippy.toml`            | Pre-commit    | Config file only.                      |
| Unused dependencies           | `cargo-machete`          | Pre-commit    | `cargo install cargo-machete`          |
| Unused dependencies (precise) | `cargo-udeps`            | Nightly CI    | `cargo install cargo-udeps` (+nightly) |
| Security / license audit      | `cargo-deny`             | Pre-push      | `cargo install cargo-deny`             |
| CVE scanning                  | `cargo-audit`            | Pre-push      | `cargo install cargo-audit`            |
| Binary size analysis          | `cargo-bloat`            | CI            | `cargo install cargo-bloat`            |
| LOC metrics                   | `tokei`                  | CI            | `cargo install tokei`                  |
| Continuous benchmarking       | Bencher + `criterion`    | Nightly CI    | `cargo install cargo-criterion`        |

## Complexity metrics with `rust-code-analysis`

[`rust-code-analysis`](https://github.com/mozilla/rust-code-analysis) (Mozilla) is the most comprehensive complexity analysis tool for Rust. It computes per-function metrics:

| Metric        | What it measures                                                  |
| ------------- | ----------------------------------------------------------------- |
| **Cognitive** | How hard the function is for a human to understand (Sonar model). |
| **CC**        | Cyclomatic complexity (linearly independent paths).               |
| **Halstead**  | Effort, difficulty, volume, estimated bugs, time to implement.    |
| **LLOC**      | Logical lines of code (statements, not blanks/comments).          |
| **MI**        | Maintainability Index (composite: Halstead + CC + LLOC).          |
| **NARGS**     | Number of function arguments.                                     |
| **NEXITS**    | Number of exit points (returns, panics, early returns).           |

### Installation

```bash
cargo install rust-code-analysis-cli
```

### Usage

```bash
# Full metrics for all files (JSON output for CI parsing)
rust-code-analysis-cli --metrics -O json -p src/

# Human-readable output for a single file
rust-code-analysis-cli --metrics -p src/domain/widget.rs
```

### CI integration — fail on threshold

```bash
# Fail if any function has cognitive complexity > 25
rust-code-analysis-cli --metrics -O json -p src/ \
  | jq -e '[.[] | .spaces[]? | select(.kind == "function")
           | select(.metrics.cognitive.sum > 25)]
           | if length > 0 then
               "FAIL: \(length) functions exceed cognitive complexity 25:\n"
               + ([.[] | "\(.name) (\(.metrics.cognitive.sum))"] | join("\n"))
               | halt_error(1)
             else empty end'
```

### Thresholds

| Metric    | Recommended max | Rationale                                                              |
| --------- | --------------- | ---------------------------------------------------------------------- |
| Cognitive | 25              | Above this, most developers can't hold the function in working memory. |
| CC        | 20              | Classic threshold from McCabe's original paper.                        |
| LLOC      | 100             | Aligns with the `too-many-lines-threshold` clippy lint.                |
| NARGS     | 7               | Beyond this, introduce a config/options struct.                        |

### justfile recipe

```just
lint-complexity:
    rust-code-analysis-cli --metrics -O json -p src/ \
      | jq -e '[.[] | .spaces[]? | select(.kind == "function") \
               | select(.metrics.cognitive.sum > 25)] | length == 0'
```

## Clippy restriction lints

[09 — Coding Style](../09-coding-style.md) § 5 covers the base lint config (`pedantic`, `nursery`, `unwrap_used`, `expect_used`). This section adds the **restriction** and **complexity** lints that catch AI-agent-specific failure modes.

### Restriction lints to add

These catch patterns AI agents commonly leave behind:

```toml
# Cargo.toml — add to existing [lints.clippy]
[lints.clippy]
# Base (from 09-coding-style.md)
pedantic        = { level = "warn", priority = -1 }
nursery         = { level = "warn", priority = -1 }
unwrap_used     = "warn"
expect_used     = "warn"

# Restriction: catch AI scaffolding
todo            = "deny"
dbg_macro       = "deny"
unimplemented   = "deny"
panic           = "deny"

# Restriction: style discipline
wildcard_imports      = "deny"
string_to_string      = "warn"
redundant_clone       = "warn"
unnecessary_wraps     = "warn"
needless_pass_by_value = "warn"
```

### Complexity thresholds via `clippy.toml`

Create `.clippy.toml` (or `clippy.toml`) at the crate root:

```toml
# .clippy.toml

# cognitive_complexity lint (clippy::cognitive_complexity)
cognitive-complexity-threshold = 25

# too_many_lines lint (clippy::too_many_lines)
too-many-lines-threshold = 100

# too_many_arguments lint (clippy::too_many_arguments)
too-many-arguments-threshold = 7

# type_complexity lint (clippy::type_complexity)
type-complexity-threshold = 250
```

These thresholds are enforced by clippy at the function level. When clippy runs in pre-commit with `-D warnings`, any function exceeding these thresholds fails the gate.

### Interaction with `rust-code-analysis`

Clippy's `cognitive_complexity` lint and `rust-code-analysis` both compute cognitive complexity, but they serve different purposes:

- **Clippy** enforces a per-function threshold inline during the compile/lint cycle (pre-commit). It's a gate.
- **`rust-code-analysis`** produces detailed per-function metrics as JSON (CI/nightly). It's a report.

Use both: clippy for fast gating, `rust-code-analysis` for deeper analysis and trend tracking.

## Unused dependency detection

### `cargo-machete` (fast, stable Rust)

[`cargo-machete`](https://github.com/bnjbvr/cargo-machete) greps `src/` for crate names. If a dependency isn't mentioned, it's likely unused.

```bash
cargo install cargo-machete
cargo machete
```

**False positives:** crates used only via macros (e.g., `tracing` used via `#[instrument]`) may not be found by grep. Allowlist them:

```toml
# Cargo.toml
[package.metadata.cargo-machete]
ignored = ["tracing"]
```

**Tier:** pre-commit (runs in < 1 second).

### `cargo-udeps` (precise, nightly only)

[`cargo-udeps`](https://github.com/est31/cargo-udeps) uses the compiler to find truly unused dependencies. More precise than machete but requires nightly.

```bash
cargo +nightly install cargo-udeps
cargo +nightly udeps --all-targets
```

**Tier:** nightly CI (requires nightly, slower).

### Comparison

| Tool            | Speed  | Precision | Requires nightly | False positives     |
| --------------- | ------ | --------- | ---------------- | ------------------- |
| `cargo-machete` | < 1s   | Good      | No               | Macros, proc-macros |
| `cargo-udeps`   | 10-30s | Excellent | Yes              | Rare                |

Use both: machete in pre-commit for fast feedback, udeps in nightly for precision.

## Security and license auditing with `cargo-deny`

[`cargo-deny`](https://github.com/EmbarkStudios/cargo-deny) is a comprehensive dependency policy engine. It subsumes `cargo-audit` (CVE scanning) and adds license compliance, bans, duplicate detection, and source restrictions.

### Configuration

Create `deny.toml` at the crate root:

```toml
[graph]
targets = []
all-features = true

[advisories]
vulnerability = "deny"
unmaintained = "warn"
unsound = "warn"
yanked = "warn"

[licenses]
allow = [
    "MIT",
    "Apache-2.0",
    "Apache-2.0 WITH LLVM-exception",
    "BSD-2-Clause",
    "BSD-3-Clause",
    "ISC",
    "Zlib",
    "Unicode-3.0",
    "Unicode-DFS-2016",
]

[bans]
multiple-versions = "warn"
deny = [
    { name = "openssl-sys" },  # prefer rustls for static builds
]

[sources]
unknown-registry = "deny"
unknown-git = "deny"
```

### Usage

```bash
cargo deny check              # all checks
cargo deny check advisories   # CVEs only
cargo deny check licenses     # license compliance only
```

**Tier:** pre-push (runs in ~2 seconds).

## Binary size analysis with `cargo-bloat`

[`cargo-bloat`](https://github.com/RazrFalcon/cargo-bloat) shows per-function and per-crate binary size breakdown. Sudden growth often indicates AI-introduced dependency bloat or excessive monomorphization.

### Usage

```bash
# Per-crate breakdown
cargo bloat --release --crates

# Top 20 largest functions
cargo bloat --release -n 20

# Wide output with more detail
cargo bloat --release --crates -n 0 --wide
```

### CI baseline tracking

```bash
# Save baseline on main branch
cargo bloat --release --crates -n 0 --wide > bloat-baseline.txt

# On PR branch, compare
cargo bloat --release --crates -n 0 --wide > bloat-pr.txt
diff bloat-baseline.txt bloat-pr.txt
```

For continuous tracking with statistical regression detection, use [Bencher](https://bencher.dev/) — it tracks binary size across commits and alerts on regressions.

### justfile recipe

```just
bloat:
    cargo bloat --release --crates -n 20
```

## LOC metrics with `tokei`

[`tokei`](https://github.com/XAMPPRocky/tokei) counts lines of code, comments, and blanks by language. Machine-readable output for CI tracking.

```bash
# JSON output for CI
tokei . --output json | jq '.Rust'

# Quick summary
tokei .
```

**CI pattern:** track `.Rust.code` across PRs. A PR that adds > 500 LLOC to a single module is a review flag.

## Continuous benchmarking with `criterion` + Bencher

[`criterion`](https://bheisler.github.io/criterion.rs/book/) is the standard Rust benchmarking framework. [`divan`](https://github.com/nvzqz/divan) is a lighter alternative with attribute macros.

### Setup

```toml
# Cargo.toml
[dev-dependencies]
criterion = { version = "0.5", features = ["html_reports"] }

[[bench]]
name = "widget_bench"
harness = false
```

```rust
// benches/widget_bench.rs
use criterion::{criterion_group, criterion_main, Criterion};

fn bench_parse_widget(c: &mut Criterion) {
    c.bench_function("parse_widget_id", |b| {
        b.iter(|| WidgetId::try_new("test-widget-42".to_string()))
    });
}

criterion_group!(benches, bench_parse_widget);
criterion_main!(benches);
```

### Continuous tracking with Bencher

[Bencher](https://bencher.dev/) integrates with GitHub Actions to track benchmark results and binary size across commits. It detects statistical regressions and posts PR comments.

```yaml
# .github/workflows/bench.yml (nightly)
name: benchmarks
on:
  schedule: [{ cron: '0 4 * * *' }]

jobs:
  bench:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: bencherdev/bencher@main
      - run: |
          bencher run \
            --project codex-session \
            --branch main \
            --testbed ubuntu-latest \
            --adapter rust_criterion \
            "cargo bench"
```

## Architectural boundary enforcement

Rust's module visibility system (`pub(crate)`, `pub(super)`, private) is the primary boundary enforcement mechanism. The compiler catches visibility violations at compile time.

The gap is at the **logical layer level**: the compiler doesn't know that `domain/` shouldn't import from `adapters/`. Fill this gap with grep-based lint rules.

### Standard boundary rules

```bash
# domain/ must be pure — no I/O imports, no adapter imports
! rg -n 'use crate::adapters' src/domain/
! rg -n 'use crate::services' src/domain/
! rg -n 'use std::fs' src/domain/
! rg -n 'use std::net' src/domain/
! rg -n 'use tokio::' src/domain/

# cli/ should not reach into ui/ internals
! rg -n 'use crate::ui::' src/cli/

# No print statements outside ui/, error.rs, logging.rs
! rg -n '(println!|print!|eprint(ln)?!)' \
    --glob '!src/ui/**' --glob '!src/error.rs' --glob '!src/logging.rs' \
    --glob '!tests/**' src/

# No stdout/stderr handle acquisition outside ui/, error.rs, logging.rs
! rg -n '(stdout|stderr)\(\)' \
    --glob '!src/ui/**' --glob '!src/error.rs' --glob '!src/logging.rs' \
    --glob '!tests/**' src/
```

### justfile recipe

```just
lint-boundaries:
    @! rg -n 'use crate::adapters' src/domain/ 2>/dev/null
    @! rg -n 'use crate::services' src/domain/ 2>/dev/null
    @! rg -n 'use std::fs' src/domain/ 2>/dev/null
    @! rg -n 'use std::net' src/domain/ 2>/dev/null
    @! rg -n '(println!|print!|eprint(ln)?!)' \
        --glob '!src/ui/**' --glob '!src/error.rs' --glob '!src/logging.rs' \
        --glob '!tests/**' src/ 2>/dev/null
    @! rg -n '(stdout|stderr)\(\)' \
        --glob '!src/ui/**' --glob '!src/error.rs' --glob '!src/logging.rs' \
        --glob '!tests/**' src/ 2>/dev/null
```

### Pre-commit hook

```yaml
# .pre-commit-config.yaml
- repo: local
  hooks:
    - id: lint-boundaries
      name: layer boundaries
      entry: just lint-boundaries
      language: system
      types: [rust]
      pass_filenames: false
```

## Complete quality gate integration

### justfile (full picture)

Extends the testing recipes from [06 § nextest profiles](./testing.md#test-runner):

```just
# --- Structural quality gates ---

lint-complexity:
    rust-code-analysis-cli --metrics -O json -p src/ \
      | jq -e '[.[] | .spaces[]? | select(.kind == "function") \
               | select(.metrics.cognitive.sum > 25)] | length == 0'

lint-boundaries:
    @! rg -n 'use crate::adapters' src/domain/ 2>/dev/null
    @! rg -n 'use crate::services' src/domain/ 2>/dev/null
    @! rg -n '(println!|print!|eprint(ln)?!)' \
        --glob '!src/ui/**' --glob '!src/error.rs' --glob '!src/logging.rs' \
        --glob '!tests/**' src/ 2>/dev/null

# --- Dependency hygiene ---

machete:
    cargo machete

deny:
    cargo deny check

audit: deny machete

# --- Binary analysis ---

bloat:
    cargo bloat --release --crates -n 20

metrics:
    tokei . --output json | jq '.Rust'

# --- Nightly ---

mutate:
    cargo mutants --test-tool nextest

bench:
    cargo bench

# --- Full gate ---

check: lint lint-complexity lint-boundaries test audit
```

### Tier assignment summary

| Tool                            | Pre-commit | Pre-push | CI (PR) | Nightly |
| ------------------------------- | ---------- | -------- | ------- | ------- |
| `cargo fmt --check`             | x          |          |         |         |
| `clippy` (strict + restriction) | x          |          |         |         |
| `cargo-machete`                 | x          |          |         |         |
| `lint-boundaries`               | x          |          |         |         |
| `cargo nextest` (unit)          | x          |          |         |         |
| `cargo nextest` (integration)   |            | x        |         |         |
| `cargo-deny`                    |            | x        |         |         |
| `rust-code-analysis`            |            | x        | x       |         |
| `cargo nextest` (all)           |            |          | x       |         |
| `cargo-bloat`                   |            |          | x       |         |
| `proptest` (extended)           |            |          |         | x       |
| `cargo-mutants`                 |            |          |         | x       |
| `cargo-udeps` (+nightly)        |            |          |         | x       |
| `criterion` (benchmarks)        |            |          |         | x       |
| `tokei` (metrics)               |            |          | x       |         |

## See also

- [Testing (Rust)](./testing.md) — core test crate stack.
- [Advanced Testing (Rust)](./advanced-testing.md) — proptest, cargo-mutants, trycmd, wiremock.
- [07 — Dependencies (Rust)](../07-dependencies.md) — curated crate list, pinning policy.
- [09 — Coding Style (Rust)](../09-coding-style.md) — base lint config, no-unwrap rule, CI lint for no-println.
- General principles:
  - [10 — Regression Safeguards](../../../../cli-design/08-testing-and-quality/regression-safeguards.md) — safeguard categories, layering model, TDD-for-agents.
  - [10a — Code Quality Tools](../../../../cli-design/08-testing-and-quality/code-quality-tools.md) — per-language quality tool matrix.

## References

- [`rust-code-analysis`](https://github.com/mozilla/rust-code-analysis) · [docs](https://mozilla.github.io/rust-code-analysis/) · [metrics](https://mozilla.github.io/rust-code-analysis/metrics.html)
- [`clippy` lint database](https://rust-lang.github.io/rust-clippy/master/index.html) · [`clippy.toml` reference](https://doc.rust-lang.org/clippy/lint_configuration.html)
- [`cargo-machete`](https://github.com/bnjbvr/cargo-machete) · [`cargo-udeps`](https://github.com/est31/cargo-udeps)
- [`cargo-deny`](https://github.com/EmbarkStudios/cargo-deny) · [docs](https://embarkstudios.github.io/cargo-deny/)
- [`cargo-bloat`](https://github.com/RazrFalcon/cargo-bloat)
- [`tokei`](https://github.com/XAMPPRocky/tokei) · [`scc`](https://github.com/boyter/scc)
- [`criterion`](https://bheisler.github.io/criterion.rs/book/) · [`divan`](https://github.com/nvzqz/divan) · [Bencher](https://bencher.dev/)
