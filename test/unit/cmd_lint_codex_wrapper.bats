setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
  export LIB_DIR="${BATS_TEST_DIRNAME}/../../lib"
  export HOME="${BATS_TEST_TMPDIR}/home"
  mkdir -p "$HOME"
  source "${LIB_DIR}/helpers.sh"
  source "${LIB_DIR}/functions/fn_ui_print.sh"
  source "${LIB_DIR}/functions/fn_log.sh"
  source "${LIB_DIR}/functions/fn_error_raise.sh"
  source "${LIB_DIR}/commands/cmd_lint_codex_wrapper.sh"
}

write_md() {
  local file="$1"
  shift
  printf '%s\n' "$@" >"$file"
}

@test "lint-codex-wrapper fails on bare codex-session exec in bash block" {
  local file="${BATS_TEST_TMPDIR}/bad.md"
  write_md "$file" \
    "# bad" \
    '```bash' \
    "codex-session exec --profile low" \
    '```'

  run --separate-stderr cog::cmd::lint_codex_wrapper "$file"

  assert_failure 1
  [[ $stderr == *"${file}:3:"* ]]
}

@test "lint-codex-wrapper fails on chained codex-session bypass" {
  local file="${BATS_TEST_TMPDIR}/chained.md"
  write_md "$file" \
    '```bash' \
    "foo && codex-session exec" \
    '```'

  run --separate-stderr cog::cmd::lint_codex_wrapper "$file"

  assert_failure 1
  [[ $stderr == *"${file}:2:"* ]]
}

@test "lint-codex-wrapper fails on subshell codex-session bypass" {
  local file="${BATS_TEST_TMPDIR}/subshell.md"
  write_md "$file" \
    '```bash' \
    "( codex-session exec )" \
    '```'

  run --separate-stderr cog::cmd::lint_codex_wrapper "$file"

  assert_failure 1
  [[ $stderr == *"${file}:2:"* ]]
}

@test "lint-codex-wrapper allows wrapper form" {
  local file="${BATS_TEST_TMPDIR}/wrapper.md"
  write_md "$file" \
    '```bash' \
    "cog codex-runner run-exec --mode danger" \
    '```'

  run cog::cmd::lint_codex_wrapper "$file"

  assert_success
}

@test "lint-codex-wrapper allows quoted echo mention" {
  local file="${BATS_TEST_TMPDIR}/quoted.md"
  write_md "$file" \
    '```bash' \
    'echo "codex-session exec"' \
    '```'

  run cog::cmd::lint_codex_wrapper "$file"

  assert_success
}

@test "lint-codex-wrapper allows heredoc body mention" {
  local file="${BATS_TEST_TMPDIR}/heredoc.md"
  write_md "$file" \
    '```bash' \
    "cat <<EOF" \
    "codex-session exec" \
    "EOF" \
    '```'

  run cog::cmd::lint_codex_wrapper "$file"

  assert_success
}

@test "lint-codex-wrapper allows prose outside bash fence" {
  local file="${BATS_TEST_TMPDIR}/prose.md"
  write_md "$file" \
    "codex-session exec" \
    "" \
    '```text' \
    "codex-session exec" \
    '```'

  run cog::cmd::lint_codex_wrapper "$file"

  assert_success
}

@test "lint-codex-wrapper allows comment line" {
  local file="${BATS_TEST_TMPDIR}/comment.md"
  write_md "$file" \
    '```bash' \
    "# codex-session exec" \
    '```'

  run cog::cmd::lint_codex_wrapper "$file"

  assert_success
}

@test "lint-codex-wrapper allows path and redirect args" {
  local file="${BATS_TEST_TMPDIR}/path.md"
  # shellcheck disable=SC2016 # Literal fixture text; $RUN_DIR must stay unexpanded in the markdown.
  write_md "$file" \
    '```bash' \
    'rm -f "$RUN_DIR/codex-session.json"' \
    '```'

  run cog::cmd::lint_codex_wrapper "$file"

  assert_success
}

@test "lint-codex-wrapper flags a bare invocation that also opens a heredoc" {
  # The finding check must run before the heredoc-open tracking, so a
  # command-position codex-session call that also opens a heredoc is still
  # flagged (not swallowed as a heredoc body).
  local file="${BATS_TEST_TMPDIR}/heredoc-open.md"
  write_md "$file" \
    '```bash' \
    "codex-session exec <<EOF" \
    "prompt body" \
    "EOF" \
    '```'

  run --separate-stderr cog::cmd::lint_codex_wrapper "$file"

  assert_failure 1
  [[ $stderr == *"${file}:2:"* ]]
}
