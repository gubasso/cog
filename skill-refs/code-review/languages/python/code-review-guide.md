# Python — Review Guide

## When to load

Any `.py` file in the diff.

## Top review heuristics

### Common footguns

- **Mutable default argument** — `def f(items=[]):` shares `items` across calls. Use
  `items: list | None = None` and `items = items or []` inside. `[blocking]`.
- **Late-binding closure in a comprehension** — `fs = [lambda: i for i in range(3)]` produces three
  lambdas that all return 2. Use `lambda i=i: i` or a default arg. `[important]`.
- `is` for value comparison (`x is 5`) → `[important]` "Use `==`; `is` is identity, which is
  implementation-defined for small ints."
- Catching `Exception` (or `BaseException`) without re-raise → `[blocking]`.
- `except: pass` (bare except) → `[blocking]`.

### Type hints and Pydantic

- Public function missing type hints → `[important]`.
- `Any` used where a `TypeVar`/`Protocol`/`Union` would express intent → `[important]`.
- Pydantic model with `Config.allow_mutation = True` and shared across threads → `[important]`.
- `@dataclass` mutated after construction in a place that should be immutable → `[important]` "Use
  `@dataclass(frozen=True)`."

### Error handling

- `raise X` without `from e` inside an except block → `[important]` "Preserve the cause chain with
  `raise X from e`."
- Catching a broad exception (`OSError`, `Exception`) when a narrow one would do → `[important]`.
- Logging an exception with `logger.error(str(e))` instead of `logger.exception(...)` →
  `[important]` "Lose the stack trace."

### Async

- `async def` calling a blocking I/O function (`requests.get`, `time.sleep`, `open()` without
  `aiofiles`) → `[blocking]` "Use an async-aware library or `asyncio.to_thread`."
- `asyncio.run(...)` called from inside another coroutine → `[blocking]` "Already in an event loop;
  just `await`."
- Forgotten `await` (return value is a coroutine that's silently dropped) → `[blocking]`.

### Performance

- String concat in loop (`s += x`) → `[important]` "Use `''.join(list_of_strings)`."
- `list(map(...))` materializing when caller only iterates → `[suggestion]`.
- `for i in range(len(xs))` then indexing → `[suggestion]` "Use `for x in xs` or `enumerate`."
- `dict[key]` followed by `dict[key] = ...` (two hashings) → `[suggestion]`.

### Idiomatic Python

- `if x == True:` / `if x == None:` → `[nit]` "Use `if x:` / `if x is None:`."
- `dict()`/`list()`/`set()` over `{}`/`[]`/`set()` literal where applicable → `[nit]`.
- Manual context manager when `contextlib` would do → `[suggestion]`.

### Common bugs

- Iterating a dict while mutating it → `[blocking]`.
- Comparing floats with `==` → `[important]` "Use `math.isclose`."
- Using `random.random()` for security tokens → `[blocking]` "Use `secrets`."
- `yaml.load()` without `Loader=` → `[blocking]` "Use `safe_load`; unsafe yaml is code execution."
- `pickle.loads()` on untrusted input → `[blocking]`.

### Testing

- `assert` in production code (gets stripped under `-O`) → `[important]` "Raise an exception
  instead."
- Test mocks the SUT itself → `[blocking]` (see [common-bugs.md](../common-bugs.md)).
- Test relies on dict insertion order in <3.7 → `[important]` (rare in 2026, but check).

## CLI specifics (when `--cli` is active)

For shared CLI design principles see `$(cog skill-refs path cli-design/AGENTS.md)`; prefer the
project's own CLI spec when present. Python CLI patterns to check:

- Typer subcommand layout with the four-edit rule.
- pydantic-settings config precedence.

CLI-specific review flags:

- `argparse` for new code where the project uses Typer/Click → `[important]` "Match project
  convention."
- Logging configured per-import via `logging.basicConfig` → `[important]` "Configure once in `main`;
  pass the logger through `AppContext`."
- `os.environ[...]` reads scattered through modules → `[important]` "Centralize in config layer."
- `print()` in a non-`ui/` module → `[important]` "Output through the UI boundary."
- Hard-coded `~/.<app>/` or `/etc/<app>/` paths → `[important]` "Use
  `platformdirs.user_config_dir()` / `user_state_dir()` for XDG compliance."

## See also

- General: [../code-quality-universal.md](../code-quality-universal.md),
  [../common-bugs.md](../common-bugs.md).
- Django (web framework specifics): [django.md](django.md).
- Upstream guide:
  <https://github.com/awesome-skills/code-review-skill/blob/main/reference/python.md>.
