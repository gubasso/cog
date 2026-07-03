# Non-interactive direnv (command and CI shells)

direnv auto-loads a project's `.envrc` — and therefore the flake devShell — through a shell hook
(`eval "$(direnv hook bash)"`). That hook is wired into `PROMPT_COMMAND`, so it fires **only in
prompt-drawing shells**. It does **not** fire in:

- **Command shells** — `bash -c "cmd"`, and even `bash -lic "cmd"` despite the `-i`.
- **Non-interactive / CI / lifecycle shells** — CI job steps, editor task runners, coding-agent
  invocations.

None of those render a prompt, so a tool launched that way starts with **no devShell**: the pinned
toolchain, task runners, and hook tools are all off `PATH`. Activate the shell explicitly instead.

## Activation options

- **Explicit per command (preferred):** `direnv exec . <cmd>` loads the current directory's `.envrc`
  and runs `<cmd>` inside the resulting environment. Project-scoped, no global state.

  ```bash
  direnv exec . pre-commit install
  direnv exec . poetry install
  direnv exec . cargo nextest run
  ```

- **Flake-direct (no direnv needed):** `nix develop --command <cmd>` builds/loads
  `devShells.default` from `flake.nix` and runs `<cmd>` inside it. Use this in CI and anywhere direnv
  is absent — it depends only on `nix` + the committed `flake.lock`.

  ```bash
  nix develop --command just test
  nix develop --command bash -c 'cargo build && cargo test'
  ```

- **Eager at shell init:** `eval "$(direnv export bash)"` loads the current directory's environment
  without a prompt. Useful when you cannot wrap the command (e.g. an agent launched via a command
  shell); gate it behind an env marker so only the intended non-interactive shells trigger it.

## Rule of thumb

- Interactive `cd` into the project → the prompt hook handles it (after a one-time `direnv allow`).
- Everything else — CI, agents, editor tasks, `bash -c` — wrap the command in `direnv exec . …` or
  `nix develop --command …`. Never assume the devShell is active in a non-prompt shell.
