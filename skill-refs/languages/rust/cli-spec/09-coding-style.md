# 09 — Coding Style (Rust)

> Prerequisite: [General principles — Coding Style](../../../cli-design/04-coding-style-rust-zig.md) is canonical. It covers explicit errors, parse-don't-validate, newtypes, composition over inheritance, free functions vs methods, borrow over own, `Result` vs `Option`, module size, `AppContext`, comment-why-not-what, no-`print`-outside-`ui/`, iterators, async discipline, const placement, strict lints, module headers, and the reading order. This file only adds Rust-specific deltas.

## 1. `.unwrap()` / `.expect()` discipline

The general no-`panic` rule maps in Rust to: no `.unwrap()`, no `.expect()` outside `main`, tests, build scripts, and `LazyLock` initializers.

```rust
// no
let widget = registry.get(&id).unwrap();

// yes
let widget = registry.get(&id)
    .ok_or_else(|| AppError::Usage(format!("unknown widget: {id}")))?;
```

`.expect("invariant: ...")` is acceptable when documenting an invariant the type system can't express, but treat each one as a smell to revisit.

## 2. Trait objects only when justified

Banned as a return type: `Box<dyn Error>`. Use the typed `AppError`.

Acceptable: `Arc<dyn Clock>` on `AppContext` so tests swap in a `MockClock`; `Box<dyn Iterator<Item = T>>` to erase a complex iterator chain at an API boundary.

Default to generics:

```rust
pub fn sync<G: GitBackend, H: HttpClient>(git: &G, http: &H) -> Result<Report, _> { ... }
```

Reach for `dyn` only when monomorphization blows up binary size or heterogeneity is genuinely runtime-determined.

## 3. Closures over `Fn` traits at API boundaries

For internal callbacks, take `impl Fn(...)` / `impl FnMut(...)` / `impl FnOnce(...)` — the compiler monomorphizes and inlines. Use `Box<dyn Fn(...)>` only when the closure must be stored heterogeneously.

## 4. No crate-root `#![allow(dead_code)]`

Scope `allow` attributes to the smallest possible target — the item, not the crate:

```rust
// yes
#[allow(dead_code)]
fn intentionally_unused_during_bootstrap() { ... }

// no — at crate root
#![allow(dead_code)]
```

A WIP module may scope at module level (`#![allow(dead_code)] // WIP: see ADR-0007`) — but remove before shipping.

## 5. Cargo / clippy lints

`Cargo.toml`:

```toml
[lints.rust]
unused_must_use = "deny"
unsafe_code     = "forbid"  # remove "forbid" if you genuinely need unsafe

[lints.clippy]
pedantic     = { level = "warn", priority = -1 }
nursery      = { level = "warn", priority = -1 }
unwrap_used  = "warn"
expect_used  = "warn"
```

Silence individual lints inline with a justifying comment, not globally.

## 6. Tokio features

For the default tokio feature set (`rt`, `macros`):

- `rt` — current-thread runtime; no work-stealing.
- `macros` — `#[tokio::main]`, `tokio::select!`, etc.

Add `rt-multi-thread` only when measurement justifies it. The general "async only when justified" rule applies.

## 7. CI lint for the no-`println!` rule

The general no-`print`-outside-`ui/` rule is enforced in Rust by:

```bash
! rg --type rust 'println!|eprintln!' src/ --glob '!src/ui/**' --glob '!src/main.rs'
```

(`main.rs` is allowed to print the final error.)

**Scope.** The rule governs _your_ writes to stdout/stderr. It does not ban clap's auto-generated `--help` / `--version` output — that goes through `clap_builder` and is structured by the derive macros, not by hand-written `println!`. The Tier 1 help pattern (`#[command(after_long_help = include_str!("../ui/help_extras.txt"))]`) is fully compliant with this rule. See [02 — Subcommand Pattern · Help rendering with clap](./02-subcommand-pattern.md#help-rendering-with-clap) for the recipe and escalation tiers.

## See also

- [General — Coding Style](../../../cli-design/04-coding-style-rust-zig.md) — canonical rules.
- [02 — Subcommand Pattern (Rust)](./02-subcommand-pattern.md)
- [03 — Error Handling (Rust)](./03-error-handling.md)
- [00 — Directory Tree (Rust)](./00-directory-tree.md)
