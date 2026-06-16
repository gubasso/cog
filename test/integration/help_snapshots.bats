setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
}

@test "cog --help matches generated snapshot" {
  run cog --help

  assert_success
  assert_output "Usage: cog [global-flags] <command> [args]

Global flags:
  -h, --help          Show help
  -V, --version       Show version
      --json          Request machine-readable output
      --dry-run       Show what would happen without changing state
      --print-config  Print resolved configuration and sources
  -v, -vv, -vvv       Increase verbosity

Commands:
  help           Show generated help for cog or a subcommand.
  noop           Exercise command dispatch without side effects.
  print-config   Print resolved configuration values and their sources."
}

@test "cog help matches root help" {
  run cog help

  assert_success
  assert_output "Usage: cog [global-flags] <command> [args]

Global flags:
  -h, --help          Show help
  -V, --version       Show version
      --json          Request machine-readable output
      --dry-run       Show what would happen without changing state
      --print-config  Print resolved configuration and sources
  -v, -vv, -vvv       Increase verbosity

Commands:
  help           Show generated help for cog or a subcommand.
  noop           Exercise command dispatch without side effects.
  print-config   Print resolved configuration values and their sources."
}

@test "cog noop --help matches generated snapshot" {
  run cog noop --help

  assert_success
  assert_output "Usage: cog noop [args]

Exercise command dispatch without side effects.

Global flags:
  -h, --help          Show help
  -V, --version       Show version
      --json          Request machine-readable output
      --dry-run       Show what would happen without changing state
      --print-config  Print resolved configuration and sources
  -v, -vv, -vvv       Increase verbosity"
}

@test "cog print-config --help resolves dashed command name" {
  run cog print-config --help

  assert_success
  assert_output "Usage: cog print-config [args]

Print resolved configuration values and their sources.

Global flags:
  -h, --help          Show help
  -V, --version       Show version
      --json          Request machine-readable output
      --dry-run       Show what would happen without changing state
      --print-config  Print resolved configuration and sources
  -v, -vv, -vvv       Increase verbosity"
}
