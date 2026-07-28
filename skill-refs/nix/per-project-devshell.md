# Per-project devShell (flake + `.envrc` + direnv)

## Automatic activation (direnv)

`.envrc` only auto-loads if **direnv is hooked into your shell** — this is the piece people miss (without it nothing activates on `cd`). Install direnv + nix-direnv and add the hook once, host-level, not per-project:

```bash
# install direnv + nix-direnv (OS package or Home Manager `programs.direnv`), then
# hook the shell — for bash, in ~/.bashrc (zsh/fish have their own hook line):
eval "$(direnv hook bash)"
```

nix-direnv caches the flake evaluation so re-entry is fast. On NixOS / Home Manager, `programs.direnv = { enable = true; nix-direnv.enable = true; };` installs the hook for you. (In dctl sandboxes both the hook and a `[whitelist]` prefix are baked in.)

**The hook only fires in prompt-drawing shells.** `direnv hook bash` works via `PROMPT_COMMAND`, so it activates only when a shell renders a prompt. It does **not** fire in **command shells** (`bash -c "cmd"`, and `bash -lic "cmd"` despite the `-i`) or in non-interactive/CI/lifecycle shells — none of them run the prompt loop. So a tool launched that way (a coding agent, a CI step, an editor task runner) starts with **no devShell** unless you activate it another way:

- **Explicit:** `direnv exec . <cmd>` — loads the dir's `.envrc` and runs `<cmd>` inside it.
- **Eager:** `eval "$(direnv export bash)"` at shell init — loads the current dir's env without a prompt (useful when you can't wrap the command, e.g. an agent launched via a command shell; this is what dctl sandboxes do, keyed off an env marker so only sandbox command shells trigger it).

## Enter the shell

```bash
nix develop          # explicit, one-off
direnv allow         # once; nix-direnv then auto-enters on cd (.envrc = use flake)
```

## Minimal `flake.nix`

Values in angle brackets are placeholders. Copy-paste starting points per language are in the cog nix template domain (`cog skill-refs path templates/nix/<type>`).

```nix
{
  description = "<project> dev shell";

  inputs = {
    # nixos-unstable = rolling branch (better-tested than nixpkgs-unstable);
    # or pin a stable release, e.g. nixos-26.05. Avoid the bare `nixpkgs`
    # registry shorthand — it resolves per-machine and is not reproducible.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let pkgs = import nixpkgs { inherit system; };
      in {
        devShells.default = pkgs.mkShell {
          packages = [
            pkgs.<language-runtime>   # e.g. python314, nodejs_22, zig
            pkgs.<package-manager>    # e.g. poetry, pnpm
          ];
          shellHook = ''echo "dev shell ready"'';
        };
      });
}
```

## Layering a language venv (Python / Poetry)

`use flake` puts `python`/`poetry` on PATH; layer the project's Poetry venv on top so console-scripts resolve without a manual activation. `layout poetry` is **not** in direnv's stdlib, so inline the logic in `.envrc`:

```bash
use flake

# use flake must stay first — it provides `poetry`. `poetry env info --path` locates
# the venv (stable on Poetry 1.x/2.x; works for in-project .venv or the cache dir).
watch_file pyproject.toml poetry.lock
venv="$(poetry env info --path 2>/dev/null || true)"
if [[ -n "$venv" && -d "$venv" ]]; then
  export VIRTUAL_ENV="$venv"
  export POETRY_ACTIVE=1
  PATH_add "$venv/bin"
fi
```

Do **not** use `poetry shell` or `eval "$(poetry env activate)"` — neither fits direnv, which mutates PATH declaratively and reverses it on `cd` out. The venv must exist first (`poetry install`); after creating it, run `direnv reload`.

## Aligning the Python version (single source of truth)

**The trap:** pinning `pkgs.python314` in the flake does **not** decide the venv's Python. nixpkgs' `pkgs.poetry` is built against nixpkgs' _default_ CPython (e.g. 3.13), so Poetry ships its **own** interpreter inside its closure. Poetry 2.x picks the interpreter with `findpython`, then hands venv creation to the `virtualenv` library, whose discovery **re-resolves** to the CPython in Poetry's own closure — even with `virtualenvs.use-poetry-python = false`. With two different CPythons on PATH (the flake's + Poetry's), the resolver decides, not your config, and you silently get a venv on Poetry's version instead of the flake's. (Refs: python-poetry/poetry#10527, NixOS/nixpkgs#439512.)

**The fix — declare the version, then guard it.** Pin the interpreter **explicitly** (this line is your SoT) and add a native `assert` that forces Poetry's own interpreter to equal it. The pin is declarative and human-readable; the assert removes the race by guaranteeing the shell holds a single Python version, and turns a future nixpkgs divergence into a **loud build failure** instead of a silent venv on the wrong version:

```nix
let
  pkgs = import nixpkgs { inherit system; };
  python = pkgs.python313;   # <-- the ONE declared source of truth
in
# pkgs.poetry is built against nixpkgs' default CPython and creates the venv
# with THAT interpreter, not whatever is on PATH. Assert they agree so the venv
# matches the pin (cache-only, no Poetry rebuild); a nixpkgs bump that moves
# Poetry's Python fails the build loudly — bump `python` to match.
assert python.version == pkgs.poetry.python.version;
{
  devShells.default = pkgs.mkShell {
    packages = [ python pkgs.poetry pkgs.pre-commit pkgs.just ];
  };
}
```

Why this shape:

- **Explicit + declarative SoT.** `python = pkgs.python313` is a readable declaration of the runtime version, pinned transitively by `flake.lock`. `pyproject.toml`'s `requires-python` is a **separate** concern — package-compatibility metadata (a range, e.g. `>=3.11,<4.0`), not the dev-interpreter pin; keep the pin inside that range.
- **Deterministic + cache-only.** The only Poetry in the binary cache is the one built against nixpkgs' **default** CPython, so pin `python` to that same version (today, the default) and both come from cache — no `poetry env use`, no recompile.
- **No silent drift.** The `assert` is the load-bearing part: without it an explicit pin that diverges from Poetry's Python silently reintroduces the two-Python race. With it, divergence can't slip by — the build stops and tells you to bump the pin. Keep `poetry.toml`'s `use-poetry-python = false` (2.x default; idiomatic and self-documenting).

**Rejected alternatives** (in order of how tempting they look):

- **`python = pkgs.poetry.python`** (bind to Poetry's interpreter, no pin) — zero-race and zero-maintenance, but the version is **implicit**: "whatever nixpkgs built Poetry against," declared nowhere. Fails the explicit/declarative-SoT goal. Use only if you _want_ the version to auto-follow nixpkgs with no say in it.
- **Explicit pin WITHOUT the `assert`** — reintroduces the silent two-Python race the moment a nixpkgs bump moves Poetry's CPython away from the pin. The guard is the whole point.
- **`pkgs.poetry.override { python3 = <pin>; }`** — the _only_ way to pin a minor **independently** of nixpkgs' default, but it recompiles Poetry **and its whole closure** with **no cache hit** — slow and fragile on a brand-new interpreter. Avoid unless you truly need a version Poetry isn't built against.
- **Remove `python` from the flake** — deterministic but implicit SoT, and nixpkgs' poetry wrapper puts only `poetry` on PATH, **not** `python`/`python3` — editors and ad-hoc scripts have no interpreter until the venv activates.
- **`poetry env use …` in a `shellHook`** — imperative wrapped in declarative; non-idempotent, mutates Poetry's cache, re-runs every entry. Reject.
- **`poetry python install` (Poetry 2.1+, python-build-standalone)** — downloads an impure interpreter outside the nix store, not pinned by `flake.lock`. Fights Nix. Reject.
- **poetry2nix `mkPoetryEnv`** — fully nix-native, but duplicates `poetry.lock` into Nix and adds override surface; over-engineered when Poetry already owns deps. Only if you want Poetry gone at runtime.

## Binary wheels need the C++ runtime (`libstdc++.so.6`)

A pure Nix devShell provides the runtimes and build tools, but **not** the shared C/C++ runtime libraries on the dynamic loader's search path — Nix reaches those only through RPATHs baked into nix-built binaries. Precompiled **manylinux wheels** (grpcio's `cygrpc.so`, `numpy`, `pydantic-core`, `cryptography`, …) are **not** nix-built: pip/Poetry drops them in as-is, and they `dlopen`/link the _system_ `libstdc++.so.6` (and often `libz.so.1`) via the normal loader path. Inside the devShell that path doesn't include them, so `import` fails:

```text
ImportError: libstdc++.so.6: cannot open shared object file: No such file or directory
```

This bites at **import** time, not install time, and only under Nix — a plain distro venv (or the old `mise`/system-Python setup) finds the host's `/usr/lib/libstdc++.so.6` and works, which is why it surfaces right after migrating a project to a flake. The `NIX_CC` / `NIX_LDFLAGS` / `stdenv` vars in the shell are **compile-time** hooks and do nothing for an already-built wheel.

Fix: put the gcc C++ runtime (and zlib) on `LD_LIBRARY_PATH` in the devShell. `mkShell` turns any attribute into an exported env var, so this is a clean one-liner (already baked into the python template, `templates/nix/python/flake.nix`):

```nix
devShells.default = pkgs.mkShell {
  # `python` is the pinned interpreter — see "Aligning the Python version" above.
  packages = [ python pkgs.poetry ];

  # gcc libstdc++.so.6 + libz.so.1 for precompiled manylinux wheels
  LD_LIBRARY_PATH = pkgs.lib.makeLibraryPath [
    pkgs.stdenv.cc.cc.lib   # ships libstdc++.so.6 — clears the reported error
    pkgs.zlib               # libz.so.1 — grpcio/Google wheels dlopen this too
  ];
};
```

Then `direnv reload` (or re-enter `nix develop`). If a wheel still fails to load, `ldd` its `.so` to see which library is missing and add that package (e.g. `pkgs.libz`, `pkgs.openssl`, `pkgs.glib`).

- **Why `LD_LIBRARY_PATH` and not `nix-ld`:** `nix-ld` also works but needs the _host_ to install and configure the `nix-ld` NixOS module (or standalone service) — not portable to RPM/openSUSE hosts. On a nix-ld host you may instead export `NIX_LD_LIBRARY_PATH`.
- **Why not `autoPatchelfHook` / build the wheel from nixpkgs:** that moves the dep into Nix and fights the "Poetry owns the venv, Nix owns the toolchain" split — over-engineered for a devShell.

## Git hooks (pre-commit)

`pre-commit` is **per-project**, not a global tool: declare it — and any `language: system` hook tools it shells out to (`dprint`, `taplo`, `typos`, `ruff`, …) — in the project's devShell, so hooks run with the same pinned toolchain as the shell and CI. pre-commit self-manages `language: python|node|rust|…` hook environments, so only `system` hooks need their tool on the devShell PATH.

```nix
devShells.default = pkgs.mkShell {
  packages = [
    pkgs.pre-commit
    pkgs.dprint # a `language: system` hook tool → must be on PATH
  ];
};
```

Install the git hook once inside the shell (idempotent):

```bash
pre-commit install
```

Make it automatic on shell entry with a `shellHook` running `pre-commit install`, or go fully Nix-native with [cachix/git-hooks.nix](https://github.com/cachix/git-hooks.nix) (formerly `pre-commit-hooks.nix`), which generates `.pre-commit-config.yaml` from Nix and installs the hook from the devShell's `shellHook`. In a sandbox that auto-activates direnv (e.g. dctl), a non-interactive lifecycle step must call it project-scoped: `direnv exec . pre-commit install`.

## Maintaining the pin

```bash
nix flake lock              # generate flake.lock the first time (needs network)
nix flake update            # bump ALL inputs
nix flake update nixpkgs    # bump one input only
```

## Notes

- Ignore `.direnv/` and `/result` in `.gitignore`.
- Nix supplies runtimes and non-language system tools; it does **not** replace the project's package manager by default (no poetry2nix / cargo2nix unless you specifically want Nix to build the app).
- Offline / no-nix host: author `flake.nix` + `.envrc`, but `flake.lock` can only be generated where `nix` and network are available. **Do not fabricate a lock.**
