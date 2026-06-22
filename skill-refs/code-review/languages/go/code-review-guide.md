# Go — Review Guide

## When to load

Any `.go` file in the diff.

## Top review heuristics

### Errors

- `if err != nil { return err }` chains where the wrapping is lossy → `[important]` "Use
  `fmt.Errorf("op: %w", err)` to preserve the chain."
- Ignored error (`_, _ = f()`) without a comment justifying why → `[important]`.
- Sentinel error comparison via `==` when `errors.Is` is needed (wrapped errors fail `==`) →
  `[blocking]`.
- Type assertion on error without `errors.As` (`err.(*MyError)`) → `[important]`.
- `panic()` for recoverable conditions → `[blocking]`.
- `recover()` outside a deferred function → won't work; flag if seen.

### Goroutines and channels

- Goroutine that captures a loop variable by reference
  (`for _, x := range xs { go func() { use(x) }() }`) → `[blocking]` "Capture explicitly:
  `for _, x := range xs { x := x; go func() { use(x) }() }`. (Go 1.22+ fixes this for `range`, but
  be explicit for clarity in mixed-version codebases.)"
- Unbounded goroutine spawn (one per loop iteration over a large slice) → `[important]` "Use a
  worker pool with a bounded channel."
- Channel sent to but never received from (deadlock) → `[blocking]`.
- Channel closed by receiver (panics on send) → `[blocking]` "Sender owns close."
- `select` without `default` in a context where blocking is wrong → `[important]`.

### Context

- Function that does I/O without taking a `context.Context` → `[important]` "Plumb context through;
  needed for cancellation and deadlines."
- `context.TODO()` left in shipping code → `[important]` "Replace with the real context."
- `context.Background()` deep inside a request path → `[important]` "Propagate the request's
  context."
- Storing a context in a struct field → `[important]` "Context is per-call; pass as argument."

### Concurrency / sync

- `sync.Mutex` value (not pointer) inside a struct that's copied → `[blocking]`.
- `sync.RWMutex` where reads vastly outnumber writes — fine; but `RWMutex` for write-heavy workloads
  → `[important]` "Plain `Mutex` is faster."
- `sync.WaitGroup` `.Add` called inside the goroutine → `[blocking]` "Race; call `Add` before `go`."

### Slices and maps

- Append to a slice without re-assigning (`append(s, x)` discarded) → `[blocking]`.
- Reading a map under concurrent write without sync → `[blocking]` "Use `sync.Map` or a mutex."
- Iterating a map and relying on order → `[blocking]` "Map iteration order is randomized."

### Performance

- String concat in a loop with `+=` → `[important]` "Use `strings.Builder`."
- `make([]T, 0)` then `append` in a loop where the size is known → `[important]` "Use
  `make([]T, 0, n)` to preallocate."
- Defer in a tight loop → `[important]` "Defers accumulate; pull out of the loop."

### Common bugs

- Unbuffered channel + single sender + single receiver assumed to be non-blocking → check carefully.
- `time.Now().Sub(t)` where `time.Since(t)` would do → `[nit]`.
- `nil` map written to → `[blocking]` "Initialize with `make`."

### Testing

- Test files outside `_test.go` naming → won't compile, but watch for `_test` packages used
  inconsistently.
- `t.Error` vs `t.Fatal` — use `Fatal` when subsequent assertions depend on this one.
- `testing.T.Parallel()` missing in tests that could run in parallel → `[suggestion]`.

## CLI specifics (when `--cli` is active)

Common Go CLI libraries: `cobra`, `urfave/cli`, `kong`. Review flags:

- `flag` (stdlib) used for new code where `cobra` is the project standard → `[important]`.
- Hand-rolled subcommand dispatcher → `[important]` "Use cobra/kong for non-trivial apps."
- `os.Exit(1)` for all errors → `[important]` "Map to sysexits codes."
- Stdout used for both data and progress → `[blocking]`.

## See also

- General: [../common-bugs.md](../common-bugs.md),
  [../performance-review.md](../performance-review.md).
- Upstream: <https://github.com/awesome-skills/code-review-skill/blob/main/reference/go.md>.
