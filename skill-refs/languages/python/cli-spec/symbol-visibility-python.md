# Symbol Visibility (enforce the leading-underscore convention)

A reusable spec for **any** Python project that uses a single leading underscore as its only module-private marker (no `__all__`, no wildcard imports, no re-exports). It defines the rule precisely and gives a copy-pasteable pre-commit gate so the convention stops drifting.

> Values below (package names, symbols) are **placeholders** — swap in your own.

## 1. The problem

In a project that signals privacy with a leading underscore, the convention is invisible to tooling:

- A class/function/constant meant to be module-private is written **without** an underscore (`RegionServerSetup` instead of `_RegionServerSetup`), silently widening the public surface.
- Nothing fails. Reviewers forget. The mistake recurs every few PRs.

Naming style linters (`pep8-naming`) check _casing_, not _visibility_. Dead-code finders flag _unused_ code, not _internal-but-used_ code. None of them key on the one fact that decides visibility: **is this symbol referenced from another module?**

## 2. The rule

> A module-level symbol is **public** iff another module in your package references it. A symbol referenced only within its own defining module **must** be `_`-prefixed.

Two decisions make the rule precise for a real repo:

- **Reference scope.** Count references from your shipped package tree (`src/…`), including any sub-package you ship (e.g. an in-tree test suite that is part of the product). **Do not** count your own dev test tree (`tests/`): a helper that is only exercised by a unit test is still module-private and stays `_`-prefixed. Consequently, dev tests are **allowed** to import `_name` internals directly (you are testing internals on purpose).
- **Direction.** Two independent violations:
  - **A — under-marking:** a public name with zero external references → should be `_`-prefixed. (The recurring bug.)
  - **B — leakage:** a `_name` imported across modules → either it is actually public (drop the underscore) or the import is wrong.

Split the enforcement: a small custom checker owns **A**; Ruff's `PLC2701` owns **B**. No overlap.

## 3. Why no off-the-shelf tool does this

Verified against current docs (all needed cross-module usage analysis that these tools don't do):

| Tool / rule                                                     | What it does                                  | Why it's not enough                                                                                                                             |
| --------------------------------------------------------------- | --------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------- |
| Ruff `PLC2701` `import-private-name` (preview)                  | flags importing a `_name` from another module | covers **B** only, not **A** — <https://docs.astral.sh/ruff/rules/import-private-name/>                                                         |
| Ruff (proposed)                                                 | enforce internal naming                       | unimplemented — <https://github.com/astral-sh/ruff/issues/18380>                                                                                |
| Pylint `W0238` unused-private-member / `W0212` protected-access | unused/accessed _class_ `_members`            | class scope and/or opposite direction — <https://pylint.readthedocs.io/en/latest/user_guide/checkers/features.html>                             |
| vulture / `deadcode`                                            | globally _dead_ code                          | a symbol used inside its own module is "used" → never flagged — <https://github.com/jendrikseipp/vulture>, <https://pypi.org/project/deadcode/> |
| ast-grep                                                        | structural pattern match                      | no whole-project symbol table — <https://ast-grep.github.io/>                                                                                   |
| griffe                                                          | models the API surface                        | no such lint rule (good _substrate_ to build on) — <https://mkdocstrings.github.io/griffe/>                                                     |

PEP 8 only calls the underscore a "weak internal use indicator" (<https://peps.python.org/pep-0008/>); the stricter project rule needs a custom gate.

## 4. The solution

A ~200-line stdlib-`ast` checker for **A**, plus Ruff `PLC2701` for **B**. The no-re-exports / no-wildcard convention is what makes the checker tractable: every `from X import Y` names the defining module directly.

**Algorithm:**

1. **Collect definitions.** Parse each package `.py`; record module-level `ClassDef` / `FunctionDef` / `AsyncFunctionDef` and top-level assignment targets. Skip dunders and names already starting with `_`.
2. **Collect external references.** Walk every package module (including type-checking and function-local imports). Resolve two shapes against the package:
   - `from <module> import <name>` — absolute **and relative** (resolve `level` against the importer's package);
   - module-qualified — `from <pkg> import <submodule>` then `<submodule>.<name>` (track the alias, then resolve `<alias>.<attr>`). Each yields a `(defining_module, name)` pair referenced by a _different_ module. Scan only the package tree, so the dev `tests/` tree is excluded for free.
3. **Classify (Direction A).** A public-named definition with no external reference and no exemption is a violation.

**Pitfalls that will bite (handle them):**

- **Relative imports** (`from .sub import X`, `from ..pkg import Y`) — resolve them, or you get a flood of false positives.
- **Module-qualified access** (`from pkg import mod` … `mod.func()`) — resolve attribute access, or every such callee looks internal.
- **`TypeVar("Name", …)` / `NewType` / `ParamSpec`** — the **string** argument must match the variable name. A token-aware rename skips strings (correct), so when you rename the variable you must update the string too.

## 5. Exceptions

Some symbols are public yet never imported by name. **Auto-detect** them (structural, self-updating — no central allowlist to rot):

- **Discriminated-union family members** — a class that is an operand of a module-level `A | B | C` union (incl. `Annotated[A | B | C, …]`); validated via the union type, never imported individually.
- **Entry points** — symbols named in `[project.scripts]`, or referenced inside an `if __name__ == "__main__":` block.
- **pytest** — `@pytest.fixture`-decorated functions anywhere; `pytest_*` hooks (the prefix is reserved); and `test*` functions inside a pytest test module.

For the rare genuinely-dynamic case (`getattr`/registry lookup), an inline **`# visibility: public`** comment on the definition line opts the symbol out. A central allowlist is rejected: it carries the same "people forget" failure mode as the original bug.

## 6. Implementation

### `pyproject.toml`

Ship the checker as a dev-only (sdist-only) package so it is importable in a dev checkout but stays out of the wheel:

```toml
[tool.poetry]
packages = [
    {include = "<your_package>", from = "src"},
    {include = "dev_checks", from = "src", format = "sdist"},
]
```

### `.pre-commit-config.yaml`

```yaml
# Direction A — custom checker.
- repo: local
  hooks:
    - id: symbol-visibility
      name: symbol visibility (internal symbols must be _-prefixed)
      entry: poetry run python -m dev_checks.visibility_check
      language: system
      pass_filenames: false
      always_run: true
      stages: [pre-commit]

# Direction B — Ruff import-private-name. Isolated to its own hook (only this
# rule, --preview) so the main ruff hook keeps stable non-preview behavior.
# tests/ excluded so unit tests may import internals directly.
- repo: https://github.com/astral-sh/ruff-pre-commit
  rev: v0.15.7
  hooks:
    - id: ruff
      alias: ruff-import-private-name
      name: ruff (import-private-name, preview)
      args: [--select, "PLC2701", --preview, --no-fix]
      exclude: '^tests/'
```

`PLC2701` is **preview-only**: it is silent without `--preview` (emits a "no effect" warning). Keeping it in a dedicated hook avoids turning on preview mode for the whole rule set.

### Checker shape

`src/dev_checks/visibility.py` — pure logic, no I/O presentation: `scan_visibility(repo_root) -> list[Violation]`. `src/dev_checks/visibility_check.py` — thin `argparse`/`print` `main()` with `if __name__ == "__main__": raise
SystemExit(main())`, exit `1` on any violation. A reference implementation:

```python
def scan_visibility(repo_root):
    src = repo_root / "src"
    pkg = src / PACKAGE_DIR
    module_by_path = {p: dotted(p, src) for p in src.rglob("*.py")}
    external = external_refs(src, module_by_path)        # (module, name) pairs
    entries = entry_points(repo_root, pkg, module_by_path)
    out = []
    for path in pkg.rglob("*.py"):
        module, tree, lines = module_by_path[path], parse(path), read_lines(path)
        exempt = union_members(tree) | fixtures(tree) | pytest_entries(tree, path) \
                 | marked(tree, lines)
        for name, line in module_defs(tree):
            if name.startswith("_"):                     # Direction A only
                continue
            if (module, name) in external or name in exempt or (module, name) in entries:
                continue
            out.append(Violation(path, line, name))
    return out
```

### Mass cleanup (first adoption)

The first run on an existing repo surfaces every legitimately-internal symbol (module `logger`s, nested models, internal errors, constants). Rename them with a **token-aware** rewriter (operate on `tokenize.NAME` tokens, never raw text) so strings/comments (`sys.argv = ["app"]`) and unrelated identifiers are not touched. Scope each source file to its own flagged symbols and each test file to the flagged names it actually imports — a naive global text replace will clobber a local variable that merely shares a common name (`logger`, `app`).

## 7. Verification & adoption

1. `poetry run python -m dev_checks.visibility_check` → clean.
2. `poetry run ruff check --select PLC2701 --preview src` → clean; confirm it is _active_ by importing a private name in a throwaway file (silent without `--preview`).
3. `mypy --strict` + full test run after the cleanup rename — these catch any mis-rename (broken import, a renamed keyword-argument name, a `TypeVar` string mismatch).

**Per-project knobs:** the package name; whether an in-tree shipped suite counts (yes if under `src/`); which directories are "tests"; and any extra entry-point convention (CLI plugins, framework hooks) that should join the auto-exempt set.
