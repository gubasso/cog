# 06 — Testing & Quality (Rust)

> Part of the [Rust CLI Spec](../README.md).
>
> For the language-agnostic principles, see [09 — Testing & Quality](../../../../cli-design/08-testing-and-quality/).

Rust-specific testing and code quality tooling. These chapters apply the general principles from [`cli-design/08-testing-and-quality/`](../../../../cli-design/08-testing-and-quality/) using the Rust ecosystem.

## Chapters

| Chapter                                   | What it covers                                                           | General principle                                                                         |
| ----------------------------------------- | ------------------------------------------------------------------------ | ----------------------------------------------------------------------------------------- |
| [Testing](./testing.md)                   | `assert_cmd` + `insta` + `tempfile` + `nextest`. Core crate stack.       | [Testing strategy](../../../../cli-design/08-testing-and-quality/testing-strategy.md)     |
| [Advanced testing](./advanced-testing.md) | `proptest` + `cargo-mutants` + `trycmd` + `wiremock` + golden files.     | [Testing tools](../../../../cli-design/08-testing-and-quality/testing-tools.md)           |
| [Code quality](./code-quality.md)         | `rust-code-analysis` + clippy restrictions + `cargo-bloat` + boundaries. | [Code quality tools](../../../../cli-design/08-testing-and-quality/code-quality-tools.md) |

## See also

- [07 — Dependencies (Rust)](../07-dependencies.md) — curated crate list, pinning policy.
- [09 — Coding Style (Rust)](../09-coding-style.md) — base lint config, no-unwrap rule.
