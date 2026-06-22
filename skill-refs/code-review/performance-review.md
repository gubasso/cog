# Performance Review

Load when the diff touches a hot path, a database query, async/concurrency, large data processing,
or anything caller-perf-sensitive. For typical CRUD changes, this file is overkill.

## Trigger heuristics

Open this file when the diff has any of:

- A loop with I/O inside (DB call, HTTP request, file read).
- New database query, ORM `.all()`/`.filter()` chain, or migration.
- Async/await, threads, channels, locks.
- Data-processing pipeline (map/filter/reduce over large inputs).
- Caching, memoization, or invalidation logic.
- New dependency that affects startup, memory, or runtime footprint.

## The four checks (do these first)

1. **Big-O of the new code.** What's the algorithmic complexity in N (input size), K (number of
   items), or whatever scales? If it's worse than the prior code, that's the headline finding.
2. **I/O in loops.** `for item in items: db.query(item)` is the classic N+1. Refactor to batch.
3. **Allocations in hot paths.** Repeated string concatenation, list comprehensions inside loops,
   fresh struct/object per iteration when one could be reused.
4. **Synchronous I/O in async paths.** A `time.sleep()`, blocking `open()`, or blocking socket
   inside an async function tanks throughput.

If all four are clear, the change is likely fine. Only then dig into micro-perf.

## N+1 query pattern

The dominant performance bug in any app with a database.

```python
# Bad — N+1
for user in users:
    user.posts = db.query("SELECT * FROM posts WHERE user_id = ?", user.id)

# Good — one round trip
post_map = group_by_user(db.query("SELECT * FROM posts WHERE user_id IN (?)", user_ids))
for user in users:
    user.posts = post_map.get(user.id, [])
```

Flag any `for x in xs: <db_call>` pattern as `[blocking]` unless `xs` is provably tiny (constant, ≤5
items). Even then, prefer batch.

ORM-specific signals:

- Django: missing `.select_related()` / `.prefetch_related()` on FK access in a loop.
- SQLAlchemy: lazy-loaded relationships accessed inside a loop without `selectinload`/`joinedload`.
- TypeORM/Prisma: `findMany` then iterating and re-querying.

## Indexes

Any new `WHERE`, `JOIN`, or `ORDER BY` on a non-indexed column on a large table is `[blocking]`.
Look for:

- `WHERE created_at > ?` on a table without an index on `created_at`.
- `JOIN ... ON a.x = b.y` where neither column is indexed.
- `ORDER BY ... LIMIT ?` (top-N query) without a covering index.

If the diff adds a migration, check the index strategy alongside.

## Async/concurrency

- **Cancellation safety**: when a future is dropped mid-await, what state is left half-written? In
  Rust this is a documented hazard (cancel-unsafe ops); in Python/JS it's rarer but possible with
  manual task cancellation. Flag any async function that mutates shared state across an `.await`
  without an explicit drop-safe story.
- **Lock granularity**: a lock held across a `.await` (Rust: `std::sync::Mutex` held across await;
  Python: `threading.Lock` from async code; JS: SAB locks across `await`) often causes deadlocks or
  starvation. Use async-aware primitives.
- **Bounded concurrency**: `Promise.all(tasks)` over a 10k-item list will hammer the downstream
  service. Use `Promise.all` only on small fixed-size batches; otherwise queue with a concurrency
  limit.
- **Backpressure**: producer that doesn't slow down when consumer can't keep up. Buffered channels
  with no upper bound leak memory.

## Memory and allocation

- **Repeated string concatenation in a loop**: `s += x` in Python is O(N²) for the loop; use a
  list + `"".join()`. Same for JS (`+=`) — use `Array.join` or `.push` + `.join`.
- **Iterating into a list when a generator suffices**: `list(map(...))` materializes; pass the
  iterator if the consumer accepts one.
- **Boxing/unboxing in tight loops** (Java, C#): autoboxing primitives inside arithmetic loops. Use
  the primitive variant of the collection.
- **Cloning instead of borrowing** (Rust): a `.to_string()` / `.clone()` inside a hot loop the
  borrow checker could otherwise approve. Trace lifetimes.

## Web Vitals (frontend)

When the diff touches the frontend rendering path:

- **Largest Contentful Paint (LCP)**: blocking the main thread or fetching the hero image late.
  Target <2.5s.
- **Interaction to Next Paint (INP)**: long tasks (>200ms) during user input. Split work, defer
  non-critical.
- **Cumulative Layout Shift (CLS)**: images/iframes without size attributes; ads or banners that
  arrive late. Reserve space.
- **Bundle size**: a new import that pulls in 500KB of transitive deps for a single small-use
  feature. Tree-shake, dynamic-import, or pick a lighter alternative.

Use Lighthouse/PageSpeed Insights numbers, not vibes.

## Hot-path discipline

If the diff touches code that runs >1k times per request or per second:

1. **No logging at info or above** in the hot path. Move to `debug` or sample.
2. **No exception-based control flow**. Throwing is expensive in every major language; reserve for
   exceptional cases.
3. **No regex compilation per call**. Compile once, reuse.
4. **No reflection / introspection** unless cached.
5. **Allocate outside the loop** when the same buffer/string-builder/byte-array can be reused.

## Caching review

When the diff adds a cache:

1. **What's the invalidation rule?** TTL? Manual bust? Event-driven? Caches without an invalidation
   story always go stale.
2. **What's the cache key?** Does it include all variants that change the value? Off-by-one on cache
   keys is the source of many "works on my machine" bugs.
3. **What's the cache scope?** Per-process? Per-request? Distributed? Mismatch between scope and
   consistency requirement causes data freshness bugs.
4. **What's the failure mode?** If the cache is unreachable, do callers fall back or fail? Both are
   valid; the choice must be explicit.

## Profiler vs guessing

Performance findings are evidence-grounded like every other finding. Acceptable evidence:

- A measurement from a benchmark in the same PR.
- A Big-O argument that's mechanical (loop in a loop is O(N×M); the math doesn't lie).
- A flamegraph or `perf top` capture.

Unacceptable evidence:

- "This feels slow."
- "Adding a cache will speed things up." (Probably; what's the hit rate going to be?)
- "We should use X library instead of Y." (Without measurement, this is fashion.)

If you have no evidence, downgrade to `[question]` and ask for a benchmark.

## See also

- [process.md](process.md), [llm-review-discipline.md](llm-review-discipline.md) — base workflow.
- [common-bugs.md](common-bugs.md) — language-specific perf footguns.
- [security-review.md](security-review.md) — security-perf interactions (DoS via expensive
  operations).
- `$(cog skill-refs path cli-design/01-logging-and-output.md)` — logging perf rules for CLI hot
  paths.
