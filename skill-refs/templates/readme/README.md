# {{PROJECT_NAME}}

{{DESCRIPTION}}

## Install

```bash
# Clone the repository
git clone <repository-url>
cd {{PROJECT_NAME}}
```

## Development shell

This project ships a Nix flake devShell with all tooling pinned.

```bash
# Interactive: allow direnv to load the shell on cd
direnv allow

# Ad hoc: enter the devShell directly
nix develop
```

## Tasks

Common tasks run through the project task runner:

```bash
just lint    # run linters and formatters
just test    # run the test suite
just build   # build the project
```

## License

This project is licensed under the terms described in the [LICENSE](LICENSE) file.

## Contributing

Contributions are welcome. Please open an issue to discuss substantial changes
before submitting a pull request, and ensure `just lint` and `just test` pass.
