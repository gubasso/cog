# C — Review Guide

## When to load

Any `.c`/`.h` file in the diff.

## Top review heuristics

### Memory safety

- `malloc`/`calloc` without matching `free` on every exit path → `[blocking]`.
- `free` of a non-heap pointer or double-free → `[blocking]`.
- Use-after-free → `[blocking]`.
- Pointer dereference without prior null check (when null is possible) → `[blocking]`.
- `strcpy`/`sprintf`/`gets` (unbounded) → `[blocking]` "Use `strncpy`/`snprintf`/`fgets`."
- `strncpy` not null-terminating when source >= dest → `[blocking]` (yes, that's a `strncpy`
  footgun).

### Buffer / index

- Index without bounds check → `[blocking]`.
- `sizeof` on a pointer when array size is meant → `[blocking]`.
- VLA (variable-length array) with user-controlled size → `[blocking]` "Stack overflow."

### Integer

- Signed overflow (UB in C) → `[blocking]`.
- `int` for size when `size_t` is correct → `[important]`.
- Unsigned arithmetic underflow assumed not to happen → `[blocking]`.

### Pointers

- Pointer arithmetic without explicit type sense → `[important]`.
- Casting from `void*` to a specific type without alignment check on platforms that care →
  `[important]`.
- `restrict` violated (two `restrict` pointers aliasing) → `[blocking]`.

### Undefined behavior

- Signed shift past width → `[blocking]`.
- `memcpy` with overlapping regions → `[blocking]` "Use `memmove`."
- Strict-aliasing violation (type-punning via cast) → `[blocking]` "Use `memcpy` or union."

### Error handling

- Function returning error code that callers ignore → `[blocking]`.
- `errno` checked without first checking the return → `[important]`.

### Common bugs

- `==` vs `=` in conditions → compiler warns; ignore at peril.
- `fclose` on a NULL FILE* → undefined; check before.
- `for (i=0; i<sizeof(arr); i++)` where `arr` is `int*` (not array) → `[blocking]`.

## See also

- Upstream (terse): <https://github.com/awesome-skills/code-review-skill/blob/main/reference/c.md>.
