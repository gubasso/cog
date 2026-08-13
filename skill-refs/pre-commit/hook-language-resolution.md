# Hook language resolution

How pre-commit decides _which_ runtime a hook executes with, and the traps that follow. Load this from `bootstrap-lint` when selecting hook ids, and from `bootstrap-nix` when deciding what the devShell must provide — the facts are one set, but the remedies are split across both domains, so neither skill owns them.

- [pre-commit — supported languages](https://pre-commit.com/#supported-languages)
- [`pre_commit/lang_base.py`](https://github.com/pre-commit/pre-commit/blob/main/pre_commit/lang_base.py)
- [`pre_commit/languages/`](https://github.com/pre-commit/pre-commit/tree/main/pre_commit/languages)

## `language: system` gets no environment

`system` maps to `lang_base.no_env` / `no_install` — pre-commit builds **nothing** and patches **nothing**. The hook's `entry` is resolved off the **ambient PATH** of whatever shell ran `pre-commit`.

Three consequences:

- **PATH order is a pre-commit concern**, not only a Nix one. Whatever is first on PATH wins, and pre-commit will not tell you which copy it picked.
- **Every `language: system` hook needs a named provider** in the project's `flake.nix` (or an equivalent documented install). A hook with no provider is an unsatisfied contract that fails only on someone else's machine.
- A tool that is in **both** the devShell and the language dep-manifest (pyproject dev group, `devDependencies`) is a live hazard — see below.

Since pre-commit **4.4.0**, `system` is an alias for `language: unsupported`, and the changelog says `system` "will eventually be deprecated". Do **not** migrate yet: it would impose a `minimum_pre_commit_version: 4.4.0` floor for no present benefit. Track it, and set that floor when you migrate.

## The venv/devShell shadowing trap

The canonical Python `.envrc` runs `use flake` and then `PATH_add "$venv/bin"`. `PATH_add` **prepends**, so the language venv sits _ahead_ of the devShell. Any tool present in both resolves to the venv copy.

That is fatal when the venv copy is a **PyPI binary wheel**: `ruff`, `typos` and `committed` ship prebuilt ELF executables whose interpreter is hard-coded to `/lib64/ld-linux-x86-64.so.2`, which does not exist on a Nix-provisioned host. The hook then fails with `[Errno 2] No such file or directory` or `cannot execute: required file not found` — pointing at a path that _does_ exist, which makes it read like a corrupt cache rather than a linkage problem.

**Rule:** a tool that a `language: system` hook invokes belongs in `flake.nix` **and nowhere else**. Keep it out of the dep-manifest. The Python `.envrc` template carries a guard loop that fails loudly if one reappears.

## `exe_exists` rejects `$HOME`

`lang_base.exe_exists` returns `False` when the resolved executable is inside the user's home directory, or inside any `/shims/` directory (asdf, pyenv, rbenv).

This drives `get_default_version()`, and the languages are **not symmetric**:

| language | probe                                          | home-dir rejection? |
| -------- | ---------------------------------------------- | ------------------- |
| `node`   | `exe_exists('node')` _and_ `exe_exists('npm')` | **yes**             |
| `golang` | `exe_exists('go')`                             | **yes**             |
| `rust`   | runs `cargo --version`                         | no                  |

So on a machine where node comes from a user nix profile, mise, asdf, or nvm — all under `~` — pre-commit silently returns `default` instead of `system` and downloads its own generic-glibc toolchain (~150 MB per env for nodeenv). On a Nix host that downloaded runtime **cannot exec at all**, for the same `/lib64/ld-linux` reason as the binary wheels.

**Rule:** a `node`/`golang` hook that carries `additional_dependencies` cannot be `language: system` (there would be no env to install them into), so pin it with an explicit **`language_version: system`** instead. That is load-bearing, not cosmetic. The paired devShell must then provide the runtime.

## Prefer upstream's `*-system` hook id

Many upstreams publish a `<id>-system` variant beside their default id — the **sanctioned** way to use a locally-installed binary. Verified present: `ripsecrets-system`, `lychee-system`, `gitleaks-system`; also `typos-src` / `typos-docker`, `lychee-docker`, `gitleaks-docker`.

**Never override `language:` on the default id to achieve this.** The override keeps the _default id's_ `entry`, which may not be the binary at all — `lychee`'s default entry is `scripts/lychee_pre_commit.sh`, an installer that shells out to `cargo-binstall` (curl-installing that first if absent) mid-hook. The `-system` variant keeps upstream's own entry and args authoritative.

Choosing the variant is **environment-conditional**, not a blanket default. On a machine without the binary, the default id is better: pre-commit installs it for you. Switch to `-system` when a devShell already provides it — which on Nix also lets you drop the toolchain the default id would have needed (`ripsecrets`' `language: rust` otherwise forces `cargo` + `rustc` into the shell for a from-source `cargo install` per hook env).

## Read upstream's `.pre-commit-hooks.yaml` before writing a comment

Overriding **no** `args:` means you **inherit upstream's**. A config that documents a behavior it never actually set is worse than no comment.

The standing example: `typos` defaults to `args: [--write-changes,
--force-exclude]`, so a stanza commented "report-only" **auto-fixes**. Restate `args: [--force-exclude]` to make the comment true.

Check the same file for a legacy alias. `ruff-pre-commit` renamed `ruff` to `ruff-check`; bare `ruff` is marked `# Legacy alias` and displays as "ruff (legacy alias)".

## Prefer additive CLI flags

Ruff's `--select` **replaces** the active rule selection from _every_ resolved config file, so the project's own `[tool.ruff.lint] select` stops applying. Use `--extend-select`.

`per-file-ignores` are **not** themselves discarded — they still apply to rules that remain selected. But an ignore for a rule that `--select` dropped has nothing left to ignore, so the project's exclusions silently become moot along with the rule.

Verifying this needs care: `ruff check --show-settings` reports the rule as enabled under **both** spellings. Only an actual run distinguishes them — `printf 'def f(x):\n    assert x\n' | ruff check --stdin-filename src/probe.py -` resolves config exactly as a real run does.

Generalize the habit: prefer the additive form of any CLI flag that has one, and verify a hook's behavior with a representative input rather than a settings dump.
