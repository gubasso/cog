# Release and man-page build

## Version

The release version source is `VERSION`. The current version is:

```text
0.1.0
```

Update that file as part of a release when the shipped CLI version changes.

## Man Page

The man-page source is `man/cog.1.scd`. Build the generated man page with:

```bash
just man
```

This target runs `scdoc < man/cog.1.scd > man/cog.1` when `scdoc` is available. If `scdoc` is not installed, the target prints a skip message and exits successfully.

## Quality Gates

Run the standard gates before release:

```bash
just lint
just test
```

`just lint` delegates to `pre-commit run --all-files`. `just test` delegates to the pre-commit unit hook and the pre-push integration hook. Live and e2e hooks are manual-stage checks exposed through `just test-live`, `just test-e2e`, and `just test-manual`.

Implementers do not run git commands in this documentation round; the orchestrator owns git state.
