# cog

`cog` is a Bash CLI project scaffolded around a source-on-dispatch module layout, pre-commit quality
gates, and bats-core test tiers.

This repository is in scaffold-only state. CLI behavior, command modules, completions, man pages,
installer implementation, and tests are added in later rounds.

## Development

```bash
just lint
just test
```

Quality gates are owned by pre-commit. Shell scripts are formatted with `shfmt -i 2 -ci -bn -s` and
checked with ShellCheck.
