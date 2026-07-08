setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
  export LIB_DIR="${BATS_TEST_DIRNAME}/../../lib"
  source "${LIB_DIR}/helpers.sh"
  source "${LIB_DIR}/functions/fn_ui_print.sh"
  source "${LIB_DIR}/functions/fn_log.sh"
  source "${LIB_DIR}/functions/fn_error_raise.sh"
  source "${LIB_DIR}/functions/fn_json_write.sh"
  source "${LIB_DIR}/functions/fn_template.sh"
  source "${LIB_DIR}/commands/cmd_ci_detect.sh"
  source "${LIB_DIR}/commands/cmd_bootstrap_audit.sh"
}

@test "bootstrap-audit empty project reports all seven domains missing" {
  run cog::cmd::bootstrap_audit --project-root "$BATS_TEST_TMPDIR" --json

  assert_success
  [ "$(jq -r '.ok' <<<"$output")" = "true" ]
  [ "$(jq -r '.domains | length' <<<"$output")" -eq 7 ]
  [ "$(jq -r '[.domains[] | select(.present == false)] | length' <<<"$output")" -eq 7 ]
}

@test "bootstrap-audit missing LICENSE and remote raise operator questions" {
  run cog::cmd::bootstrap_audit --project-root "$BATS_TEST_TMPDIR" --json

  assert_success
  [ "$(jq -r '.domains[] | select(.domain == "repo") | .requires_question' <<<"$output")" = "true" ]
  [ "$(jq -r '.domains[] | select(.domain == "ci") | .requires_question' <<<"$output")" = "true" ]
}

@test "bootstrap-audit reports present deliverables that already exist" {
  local dir="$BATS_TEST_TMPDIR/full"
  mkdir -p "$dir/.github/workflows"
  touch "$dir/.pre-commit-config.yaml" "$dir/.editorconfig" "$dir/flake.nix" \
    "$dir/.envrc" "$dir/.gitignore" "$dir/LICENSE" "$dir/README.md" \
    "$dir/CLAUDE.md" \
    "$dir/justfile" "$dir/.github/workflows/ci.yml"
  printf 'self-contained\n' >"$dir/AGENTS.md"

  run cog::cmd::bootstrap_audit --project-root "$dir" --json

  assert_success
  [ "$(jq -r '[.domains[] | select(.present == true)] | length' <<<"$output")" -eq 7 ]
}

@test "bootstrap-audit taskrunner is present for a bare Makefile" {
  local dir="$BATS_TEST_TMPDIR/mk"
  mkdir -p "$dir"
  touch "$dir/Makefile"

  run cog::cmd::bootstrap_audit --project-root "$dir" --json

  assert_success
  local row
  row="$(jq -c '.domains[] | select(.domain == "taskrunner")' <<<"$output")"
  [ "$(jq -r '.present' <<<"$row")" = "true" ]
  [ "$(jq -r '.artifacts | length' <<<"$row")" -eq 1 ]
  [ "$(jq -r '.artifacts[0].name' <<<"$row")" = "Makefile" ]
}

@test "bootstrap-audit every domain carries a requirements array" {
  run cog::cmd::bootstrap_audit --project-root "$BATS_TEST_TMPDIR" --json

  assert_success
  [ "$(jq -r 'all(.domains[]; .requirements | type == "array")' <<<"$output")" = "true" ]
}

@test "bootstrap-audit flags a present nix devshell whose gitignore lacks the nix lines" {
  local dir="$BATS_TEST_TMPDIR/nixgap"
  mkdir -p "$dir"
  touch "$dir/flake.nix" "$dir/.envrc"
  printf '*.log\n' >"$dir/.gitignore"

  run cog::cmd::bootstrap_audit --project-root "$dir" --json

  assert_success
  local row
  row="$(jq -c '.domains[] | select(.domain == "nix")' <<<"$output")"
  [ "$(jq -r '.present' <<<"$row")" = "true" ]
  [ "$(jq -r '.requirements[] | select(.name == "gitignore-nix-lines") | .satisfied' <<<"$row")" = "false" ]
}

@test "bootstrap-audit nix requirement is satisfied once the gitignore carries the nix lines" {
  local dir="$BATS_TEST_TMPDIR/nixok"
  mkdir -p "$dir"
  touch "$dir/flake.nix" "$dir/.envrc"
  printf '*.log\n.direnv/\n/result\n' >"$dir/.gitignore"

  run cog::cmd::bootstrap_audit --project-root "$dir" --json

  assert_success
  [ "$(jq -r '.domains[] | select(.domain == "nix") | .requirements[] | select(.name == "gitignore-nix-lines") | .satisfied' <<<"$output")" = "true" ]
}

@test "bootstrap-audit flags a present pre-commit config missing the editorconfig-checker hook" {
  local dir="$BATS_TEST_TMPDIR/pcgap"
  mkdir -p "$dir"
  printf 'repos: []\n' >"$dir/.pre-commit-config.yaml"
  printf 'root = true\n' >"$dir/.editorconfig"

  run cog::cmd::bootstrap_audit --project-root "$dir" --json

  assert_success
  [ "$(jq -r '.domains[] | select(.domain == "precommit") | .requirements[] | select(.name == "editorconfig-checker-hook") | .satisfied' <<<"$output")" = "false" ]
}

@test "bootstrap-audit marks every domain in scope and assigns install to absent domains" {
  run cog::cmd::bootstrap_audit --project-root "$BATS_TEST_TMPDIR" --json

  assert_success
  [ "$(jq -r 'all(.domains[]; .default_in_scope == true)' <<<"$output")" = "true" ]
  [ "$(jq -r 'all(.domains[]; .default_action == "install")' <<<"$output")" = "true" ]
}

@test "bootstrap-audit assigns reconcile to present domains" {
  local dir="$BATS_TEST_TMPDIR/full"
  mkdir -p "$dir/.github/workflows"
  touch "$dir/.pre-commit-config.yaml" "$dir/.editorconfig" "$dir/flake.nix" \
    "$dir/.envrc" "$dir/.gitignore" "$dir/LICENSE" "$dir/README.md" \
    "$dir/CLAUDE.md" \
    "$dir/justfile" "$dir/.github/workflows/ci.yml"
  printf 'self-contained\n' >"$dir/AGENTS.md"

  run cog::cmd::bootstrap_audit --project-root "$dir" --json

  assert_success
  [ "$(jq -r 'all(.domains[]; .default_action == "reconcile")' <<<"$output")" = "true" ]
}

@test "bootstrap-audit reconciles a present pre-commit config with unsatisfied requirements" {
  local dir="$BATS_TEST_TMPDIR/pcgap"
  mkdir -p "$dir"
  printf 'repos: []\n' >"$dir/.pre-commit-config.yaml"
  printf 'root = true\n' >"$dir/.editorconfig"

  run cog::cmd::bootstrap_audit --project-root "$dir" --json

  assert_success
  local row
  row="$(jq -c '.domains[] | select(.domain == "precommit")' <<<"$output")"
  [ "$(jq -r '.default_action' <<<"$row")" = "reconcile" ]
  [ "$(jq -r '.requirements_satisfied' <<<"$row")" = "false" ]
}

@test "bootstrap-audit requirements_satisfied is true for a domain with no requirements" {
  run cog::cmd::bootstrap_audit --project-root "$BATS_TEST_TMPDIR" --json

  assert_success
  # editorconfig carries no content requirements, so the fold is vacuously true.
  [ "$(jq -r '.domains[] | select(.domain == "editorconfig") | .requirements_satisfied' <<<"$output")" = "true" ]
}

@test "bootstrap-audit emits the full shape and fails on a bad root" {
  run cog::cmd::bootstrap_audit --project-root "$BATS_TEST_TMPDIR/nope" --json

  assert_failure
  [ "$(jq -r '.ok' <<<"$output")" = "false" ]
  [ "$(jq -r '.domains | length' <<<"$output")" -eq 7 ]
  [ "$(jq -r '.reason' <<<"$output")" = "project root is not a directory" ]
}

@test "bootstrap-audit governance is absent on an empty project" {
  run cog::cmd::bootstrap_audit --project-root "$BATS_TEST_TMPDIR" --json

  assert_success
  local row
  row="$(jq -c '.domains[] | select(.domain == "governance")' <<<"$output")"
  [ "$(jq -r '.present' <<<"$row")" = "false" ]
  [ "$(jq -r '.requires_question' <<<"$row")" = "false" ]
  [ "$(jq -r '.default_action' <<<"$row")" = "install" ]
}

@test "bootstrap-audit governance is present when AGENTS.md carries the principle" {
  local dir="$BATS_TEST_TMPDIR/gov"
  mkdir -p "$dir"
  printf '@AGENTS.md\n' >"$dir/CLAUDE.md"
  printf '# Agent Guidelines\n\nself-contained\n' >"$dir/AGENTS.md"

  run cog::cmd::bootstrap_audit --project-root "$dir" --json

  assert_success
  local row
  row="$(jq -c '.domains[] | select(.domain == "governance")' <<<"$output")"
  [ "$(jq -r '.present' <<<"$row")" = "true" ]
  [ "$(jq -r '.requirements[] | select(.name == "self-containment-principle") | .satisfied' <<<"$row")" = "true" ]
  [ "$(jq -r '.requirements_satisfied' <<<"$row")" = "true" ]
}

@test "bootstrap-audit governance flags an AGENTS.md that dropped the self-containment principle" {
  local dir="$BATS_TEST_TMPDIR/govgap"
  mkdir -p "$dir"
  printf '@AGENTS.md\n' >"$dir/CLAUDE.md"
  printf '# Agent Guidelines\n\nno principle here\n' >"$dir/AGENTS.md"

  run cog::cmd::bootstrap_audit --project-root "$dir" --json

  assert_success
  [ "$(jq -r '.domains[] | select(.domain == "governance") | .requirements[] | select(.name == "self-containment-principle") | .satisfied' <<<"$output")" = "false" ]
}

@test "bootstrap-audit requires an output mode" {
  run --separate-stderr cog::cmd::bootstrap_audit --project-root "$BATS_TEST_TMPDIR"

  assert_failure 64
  [[ $stderr == *"MissingArgument"* ]]
}
