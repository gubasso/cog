# Release and man-page build

This runbook prepares the versioned CLI and its generated man page for release.

## Start state

Run from the repository root with the intended release version known. `VERSION` is the version source, `man/cog.1.scd` is the man source, and `scdoc` is required to prove regeneration.

## Build and verify

1. Inspect `VERSION` and update it only when the shipped CLI version changes.
2. Run `just man`.
3. Verify `man/cog.1` contains every command listed by `cog --help`.
4. Run `just lint`, `just test`, and `just test-e2e`.
5. Re-run any rewriting hook until the second lint run is clean.

## Stop conditions

Stop if `scdoc` is unavailable: the recipe's skip is useful for ordinary development but does not prove the tracked man page is current for release. Stop on any quality-gate failure and keep the last known generated man page until the source can be regenerated successfully.

No repository-history operation is part of this runbook. Release coordination owns any later version-control action.
