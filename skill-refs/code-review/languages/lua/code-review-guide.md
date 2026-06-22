# Lua — Review Guide

## When to load

Any `.lua` file. Common contexts: Neovim configs, OpenResty, LÖVE2D, embedded scripts.

## Top review heuristics

### Variable scoping

- `local` missing on a new variable → `[blocking]` "Pollutes global table; common Lua footgun."
- Globals used where a module-local would do → `[important]`.

### `nil` handling

- Indexing without a nil check (`a.b.c` where `a.b` could be nil) → `[important]`.
- Using `not x` to test for nil when `x` could be `false` → `[important]` "`not false` is `true`;
  explicit `x == nil` is safer when intent is nil-check."
- `assert(x, "msg")` where `x` could legitimately be `false` (assert fires) → `[important]`.

### Tables

- Mixed array-and-hash table where iteration is order-dependent → `[important]` "`ipairs` stops at
  first nil; `pairs` has no defined order."
- Using `table.insert(t, x)` in a tight loop → `[important]` "Direct index assignment
  (`t[#t+1] = x`) is faster."
- `for i,v in ipairs(t)` when `t` has nil holes → `[important]` "Stops at first nil; use `pairs` or
  `for i=1,n`."
- Using `#t` on a sparse table → `[important]` "Length operator is undefined for tables with holes."

### Metatables

- `__index` set to a function for performance-critical paths → `[important]` "Function metamethods
  are slower than table fallback."
- Inheritance chain via `setmetatable` that's deeper than 2 levels → `[important]` "Performance +
  maintainability."

### Performance

- String concatenation in a loop with `..` → `[important]` "Use `table.concat` with an accumulator
  table."
- `string.format` in a hot path → `[suggestion]`.
- Closures captured per call instead of reused → `[suggestion]`.

### Common bugs

- `1`-indexing assumed but iterating from `0` → `[blocking]`.
- Integer/float blurring (Lua 5.3+ has distinction; older versions don't) → `[important]` when
  migrating versions.
- Coroutine resumed after death (yields error) → `[important]`.

### Neovim-specific

If the file lives in an `nvim/` config:

- Globally scoped `vim.api` calls in a buffer-local context → `[important]`.
- Autocmds without a group → `[important]` "Causes accumulation on reload."
- `vim.cmd("...")` where Lua API exists → `[suggestion]` "Use the typed API."

## CLI specifics

Lua is rarely the host language for a standalone CLI. If reviewing one:

- Argument parsing manual (no library) → `[suggestion]` "Consider `argparse.lua`."
- `os.exit(1)` for all errors → `[important]`.

## See also

- General: [../code-quality-universal.md](../code-quality-universal.md),
  [../common-bugs.md](../common-bugs.md).
- Neovim user-config conventions: project-specific (`lua/host-<hostname>.lua` per dotfiles pattern).
