# Rust — Review Guide

## When to load

Any `.rs` file in the diff. Always load for Rust changes.

## Top review heuristics

### Ownership and borrowing

- `clone()` used to escape a borrow-checker error → `[important]` "Clone is acceptable in prototypes but should be justified in shipping code; restructure the borrow if possible."
- `Arc<Mutex<T>>` for data that's only mutated by one thread → `[important]` "Use `RefCell` or single-owner if cross-thread sync isn't needed."
- Lifetime annotations on types that don't store references → `[nit]` "Often a sign the function should own the value."
- `'static` bounds on generic parameters where they're not required → `[important]`.

### Error handling

- `unwrap()` / `expect()` outside `main`, tests, build scripts, once-init blocks → `[blocking]` "Propagate as typed error."
- `panic!` for recoverable conditions → `[blocking]`.
- `?` on a `Result<T, E1>` returned where `E2` is needed without `#[from]` impl → won't compile, but if it does compile via a wide `Box<dyn Error>` boundary → `[important]` "Preserve typed errors; `Box<dyn Error>` loses information."
- Functions returning `Result<T, Box<dyn Error>>` from a library crate → `[important]` "Define a typed error enum with `thiserror`."

### Unsafe

- `unsafe` block without a `// SAFETY:` comment → `[blocking]`.
- `unsafe` block whose justification doesn't match the actual operation → `[blocking]`.
- `transmute` between unrelated types → `[blocking]` unless the safety comment cites the layout invariant being preserved.
- `&*ptr` from raw pointer without lifetime/aliasing analysis → `[blocking]`.

### Async

- `std::sync::Mutex` held across `.await` → `[blocking]` "Use `tokio::sync::Mutex` or restructure to drop the lock before awaiting."
- `block_on` inside an async function → `[blocking]` "Will deadlock; await directly."
- `tokio::spawn` of a future borrowing local data → won't compile, but if seen with `'static` bounds added carelessly → `[important]`.
- Cancel-unsafe operation across `.await` (e.g., partial write to shared state, then await, then second write) → `[blocking]` "Cancellation drops the future mid-sequence."

### Type-system hygiene

- Stringly-typed code where a newtype would help (`String` for an ID, `String` for a URL) → `[important]`.
- `pub` on an item that has no external consumer → `[important]` "Restrict visibility."
- `derive(Clone, Copy, Debug, Default, ...)` blanket on every struct → `[nit]` "Derive only what you use."

### Idiomatic patterns

- `match` on a single `Some(x)` case with `_ => {}` → `[suggestion]` "Use `if let Some(x) = ...`."
- `.iter().map(...).collect::<Vec<_>>()` when chained operations would work without collecting → `[suggestion]`.
- `for i in 0..vec.len() { vec[i] }` → `[suggestion]` "Iterate by reference."
- Implementing both `Display` and `Debug` with the same body → `[nit]`.

### Common bugs

- `Vec::with_capacity(n)` then index-assign instead of `push` (will panic; `with_capacity` reserves but doesn't extend) → `[blocking]`.
- `String::new()` then `push_str` in a tight loop → `[important]` "Use `String::with_capacity` or `write!`."
- Integer overflow on `as` casts → `[important]` "Use `try_into()` for runtime-checked conversion."
- `f32::EPSILON` for general float comparison → `[important]` "Epsilon is only correct for values near 1.0."

## CLI specifics (when `--cli` is active)

For shared CLI design principles see `$(cog skill-refs path cli-design/AGENTS.md)`; prefer the project's own CLI spec when present. Rust CLI patterns to check:

- Standard directory layout.
- clap derive subcommand pattern + four-edit rule.
- `thiserror` + `anyhow` error-handling boundary.
- `tracing` + `tracing-subscriber` logging setup.
- `assert_cmd` + `insta` snapshot tests.

CLI-specific review flags:

- `Command::new()`+`.arg()` builder pattern instead of `#[derive(Parser)]` for new code → `[suggestion]` unless there's a documented reason.
- `clap::Parser` impl with field-level `default_value` AND a `default` const in the same module → `[important]` "Single source of truth for defaults."
- `tracing_subscriber::fmt::init()` in a binary that also wants file logging → `[important]` "Use a layered subscriber with `tracing-appender` for the file sink."
- `RUST_LOG=trace` accidentally enabled by default → `[blocking]`.

## See also

- General: [../code-quality-universal.md](../../code-quality-universal.md), [../common-bugs.md](../../common-bugs.md), [../performance-review.md](../../performance-review.md).
- Upstream guide: <https://github.com/awesome-skills/code-review-skill/blob/main/reference/rust.md>.
