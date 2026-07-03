# Migrate one project onto a Nix devShell

Do this per-project, incrementally. On a host that already provides Nix + direnv, this just adds the
three files to a repo.

## Steps

1. **Pick the template.** Copy from the cog nix template domain (`templates/nix/<type>`) into the
   repo root:
   - Python (Poetry) → `templates/nix/python/{flake.nix,.envrc}`
   - Rust → `templates/nix/rust/{flake.nix,.envrc}` (keep the repo's existing `rust-toolchain.toml`)
   - Node → `templates/nix/node/{flake.nix,.envrc}`
   - Zig → `templates/nix/zig/{flake.nix,.envrc}`
   - Anything else → `templates/nix/generic/{flake.nix,.envrc}`

2. **Tune `flake.nix`** to the runtime the project needs (e.g. `nodejs_22`, a Zig version, add
   `pkgs.<system-lib>` for native builds). **For Python/Poetry**, pin the version explicitly and add
   the `assert python.version == pkgs.poetry.python.version` guard so the venv can't drift from the
   pin; see [per-project-devshell](per-project-devshell.md) ("Aligning the Python
   version").

3. **Generate the lock** on a host with Nix + network (never fabricate it):
   ```bash
   nix flake lock
   ```

4. **`.gitignore`** `/.direnv/` and `/result`.

5. **Trust + enter** (host): `direnv allow`. In a sandbox that pre-trusts the directory via a direnv
   whitelist, it's trusted automatically — just `cd` in.

6. **Install deps inside the shell** (the language manager still owns them):
   ```bash
   poetry install        # or: pnpm install / cargo build
   pre-commit install
   direnv reload          # Python: re-scan so the venv layers onto PATH
   ```

7. **Drop non-Nix provisioning**: delete any `mise.toml` / `.tool-versions`, drop `mise install` /
   `rustup` steps from project scripts or CI, and point CI at the flake
   (`nix develop --command <task>`) or install the toolchain the flake pins.

8. **Verify**: open a fresh shell, `cd` in, confirm the runtime resolves into the Nix store
   (`which python` / `cargo --version` matches the pin) with no manual activation.

## Non-interactive / sandbox specifics

- Once the repo has `flake.nix` + `.envrc`, non-interactive lifecycle steps must load the shell
  explicitly (`direnv exec . poetry install`, etc.) — the prompt hook does not fire in command
  shells. See [non-interactive-direnv](non-interactive-direnv.md).
- Rust: keep `rust-toolchain.toml` — the flake reads it (see
  [rust-toolchain](rust-toolchain.md)); no `~/.rustup` volume needed.
