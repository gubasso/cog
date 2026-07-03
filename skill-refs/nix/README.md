# Nix — per-project devShell reference

Nix is the source of truth for developer tooling: a per-project flake devShell pins the toolchain,
and direnv activates it automatically on `cd`. These references are enhancers for the `bootstrap-nix`
skill; the skill is fully functional from the cog templates and prose alone.

## The boundary (three package managers, three jobs)

| Manager              | Owns                                                                                        | Examples                                                                                 |
| -------------------- | ------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------- |
| **distro** (zypper…) | Kernel, drivers, DE, system services, the Nix daemon itself, ABI/build libs                 | `gcc`, `glibc-devel`, `libopenssl-3-devel`, Playwright browser libs                      |
| **Nix**              | Global user CLIs (lean profile) **+** each project's toolchain & dev tools (flake devShell) | global: `ripgrep`, `neovim`, `starship`; per-project: `python`, `rust`, `just`, `dprint` |
| **language pkg-mgr** | The project's dependency graph (runs _inside_ the devShell)                                 | `cargo`, `poetry`, `pnpm` own their lockfiles                                            |

Rule of thumb: needs root / boot / hardware / display → the distro manager. A user CLI or a project
runtime → **Nix**. A library your code imports → the **language's** manager, invoked inside the Nix
devShell. Nix does **not** replace the language package manager (no poetry2nix / cargo2nix unless you
deliberately want Nix to _build_ the app).

Within Nix there's a second split — **lean global / rich per-project**. A small **global profile**
holds only the CLIs you want in _every_ shell (`ripgrep`, `neovim`, `starship`, agent CLIs).
Everything a _specific_ project needs — its language toolchain **and** its task runners, linters,
formatters, and pre-commit hook tools (`just`, `dprint`, `pre-commit`, …) — lives in that project's
**flake devShell**, pinned per repo.

## Read in order

1. [overview](overview.md) — concepts, the three files, mental model.
2. [per-project-devshell](per-project-devshell.md) — flake + `.envrc` + direnv; the Poetry-venv layer.
3. [rust-toolchain](rust-toolchain.md) — the hybrid `rust-toolchain.toml` + oxalica approach.
4. [migrate-a-project](migrate-a-project.md) — step-by-step to move one repo onto a flake devShell.
5. [non-interactive-direnv](non-interactive-direnv.md) — activating the devShell in command / CI shells.

Copy-paste starting points live in the cog nix template domain (`python`, `rust`, `node`, `zig`,
`generic`), resolved with `cog skill-refs path templates/nix/<type>`.
