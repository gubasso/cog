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
    "$dir/justfile" "$dir/.github/workflows/ci.yml"
  printf '@AGENTS.md\n' >"$dir/CLAUDE.md"
  printf 'self-contained\n' >"$dir/AGENTS.md"

  run cog::cmd::bootstrap_audit --project-root "$dir" --json

  assert_success
  [ "$(jq -r '[.domains[] | select(.present == true)] | length' <<<"$output")" -eq 7 ]
}

@test "bootstrap-audit taskrunner is present for a bare justfile" {
  local dir="$BATS_TEST_TMPDIR/jf"
  mkdir -p "$dir"
  touch "$dir/justfile"

  run cog::cmd::bootstrap_audit --project-root "$dir" --json

  assert_success
  local row
  row="$(jq -c '.domains[] | select(.domain == "taskrunner")' <<<"$output")"
  [ "$(jq -r '.present' <<<"$row")" = "true" ]
  [ "$(jq -r '.artifacts | length' <<<"$row")" -eq 1 ]
  [ "$(jq -r '.artifacts[0].name' <<<"$row")" = "justfile" ]
}

@test "bootstrap-audit taskrunner is missing for a project with only a Makefile" {
  local dir="$BATS_TEST_TMPDIR/mk"
  mkdir -p "$dir"
  touch "$dir/Makefile"

  run cog::cmd::bootstrap_audit --project-root "$dir" --json

  assert_success
  local row
  row="$(jq -c '.domains[] | select(.domain == "taskrunner")' <<<"$output")"
  [ "$(jq -r '.present' <<<"$row")" = "false" ]
  [ "$(jq -r '.artifacts[0].name' <<<"$row")" = "justfile" ]
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
    "$dir/justfile" "$dir/.github/workflows/ci.yml"
  printf '@AGENTS.md\n' >"$dir/CLAUDE.md"
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
  [ "$(jq -r '.requirements[] | select(.name == "claude-agents-pointer") | .satisfied' <<<"$row")" = "true" ]
  [ "$(jq -r '.requirements_satisfied' <<<"$row")" = "true" ]
}

@test "bootstrap-audit governance flags a CLAUDE.md pointer with extra content" {
  local dir="$BATS_TEST_TMPDIR/govextra"
  mkdir -p "$dir"
  printf '@AGENTS.md\nextra\n' >"$dir/CLAUDE.md"
  printf '# Agent Guidelines\n\nself-contained\n' >"$dir/AGENTS.md"

  run cog::cmd::bootstrap_audit --project-root "$dir" --json

  assert_success
  local row
  row="$(jq -c '.domains[] | select(.domain == "governance")' <<<"$output")"
  [ "$(jq -r '.requirements[] | select(.name == "claude-agents-pointer") | .satisfied' <<<"$row")" = "false" ]
  [ "$(jq -r '.requirements_satisfied' <<<"$row")" = "false" ]
}

@test "bootstrap-audit governance flags a CLAUDE.md pointer missing final newline" {
  local dir="$BATS_TEST_TMPDIR/govnonewline"
  mkdir -p "$dir"
  printf '@AGENTS.md' >"$dir/CLAUDE.md"
  printf '# Agent Guidelines\n\nself-contained\n' >"$dir/AGENTS.md"

  run cog::cmd::bootstrap_audit --project-root "$dir" --json

  assert_success
  local row
  row="$(jq -c '.domains[] | select(.domain == "governance")' <<<"$output")"
  [ "$(jq -r '.requirements[] | select(.name == "claude-agents-pointer") | .satisfied' <<<"$row")" = "false" ]
  [ "$(jq -r '.requirements_satisfied' <<<"$row")" = "false" ]
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

# shellcheck disable=SC2030 # `run --separate-stderr` rebinds `$output` here; each bats @test is its own subshell, so this cannot leak into a later test.
@test "bootstrap-audit requires an output mode" {
  run --separate-stderr cog::cmd::bootstrap_audit --project-root "$BATS_TEST_TMPDIR"

  assert_failure 64
  [[ $stderr == *"MissingArgument"* ]]
}

# --- ruff-extend-select ------------------------------------------------------
#
# A CLI --select replaces the active rule selection from every resolved config
# file. The audit must flag that on the primary ruff hook, while still allowing
# a genuinely secondary aliased hook to isolate a single rule.

# Sets RUFF_SELECT_SATISFIED rather than printing, so callers need no command
# substitution: a subshell would put bats' `run`/`$output` out of scope.
_audit_ruff_select() {
  local dir="$BATS_TEST_TMPDIR/ruffsel-$1"
  mkdir -p "$dir"
  printf '%s\n' "$2" >"$dir/.pre-commit-config.yaml"
  run cog::cmd::bootstrap_audit --project-root "$dir" --json
  assert_success
  # shellcheck disable=SC2031 # `$output` is set by `run` in this same shell; shellcheck attributes it to an earlier bats @test subshell.
  RUFF_SELECT_SATISFIED="$(jq -r '.domains[] | select(.domain == "precommit") | .requirements[] | select(.name == "ruff-extend-select") | .satisfied' <<<"$output")"
}

@test "bootstrap-audit ruff-extend-select accepts the additive inline form" {
  _audit_ruff_select ok 'repos:
  - repo: https://github.com/astral-sh/ruff-pre-commit
    hooks:
      - id: ruff-check
        args: [--extend-select, "F", --fix]'
  [ "$RUFF_SELECT_SATISFIED" = "true" ]
}

@test "bootstrap-audit ruff-extend-select flags the inline config-replacing form" {
  _audit_ruff_select inline 'repos:
  - repo: https://github.com/astral-sh/ruff-pre-commit
    hooks:
      - id: ruff-check
        args: [--select, "F", --fix]'
  [ "$RUFF_SELECT_SATISFIED" = "false" ]
}

@test "bootstrap-audit ruff-extend-select flags the block-sequence form" {
  _audit_ruff_select block 'repos:
  - repo: https://github.com/astral-sh/ruff-pre-commit
    hooks:
      - id: ruff-check
        args:
          - --select
          - F'
  [ "$RUFF_SELECT_SATISFIED" = "false" ]
}

@test "bootstrap-audit ruff-extend-select flags the equals form" {
  _audit_ruff_select equals 'repos:
  - repo: https://github.com/astral-sh/ruff-pre-commit
    hooks:
      - id: ruff-check
        args: [--select=F]'
  [ "$RUFF_SELECT_SATISFIED" = "false" ]
}

@test "bootstrap-audit ruff-extend-select exempts a secondary aliased single-rule hook" {
  # The primary hook is additive; the aliased one deliberately isolates one rule.
  _audit_ruff_select secondary 'repos:
  - repo: https://github.com/astral-sh/ruff-pre-commit
    hooks:
      - id: ruff-check
        args: [--extend-select, "F", --fix]
      - id: ruff-check
        alias: ruff-import-private-name
        args: [--select, "PLC2701"]'
  [ "$RUFF_SELECT_SATISFIED" = "true" ]
}

@test "bootstrap-audit ruff-extend-select flags a lone aliased hook using --select" {
  # With no non-aliased sibling, the aliased hook IS the primary hook, so the
  # alias must not buy an exemption.
  _audit_ruff_select lone 'repos:
  - repo: https://github.com/astral-sh/ruff-pre-commit
    hooks:
      - id: ruff-check
        alias: lint
        args: [--select, "F"]'
  [ "$RUFF_SELECT_SATISFIED" = "false" ]
}

@test "bootstrap-audit ruff-extend-select is unaffected by a comment before args" {
  _audit_ruff_select commented 'repos:
  - repo: https://github.com/astral-sh/ruff-pre-commit
    hooks:
      # a load-bearing rationale comment
      # spanning several lines
      # so any fixed line window would miss the args below
      - id: ruff-check
        args: [--extend-select, "F"]'
  [ "$RUFF_SELECT_SATISFIED" = "true" ]
}

@test "bootstrap-audit ruff-extend-select ignores an in-stanza comment naming --select" {
  # The prescriptive comment names the forbidden flag; only args values count.
  _audit_ruff_select instanza 'repos:
  - repo: https://github.com/astral-sh/ruff-pre-commit
    hooks:
      - id: ruff-check
        # --extend-select, NEVER --select: a CLI --select replaces the active
        # rule selection from every resolved config file.
        args: [--extend-select, "F"]'
  [ "$RUFF_SELECT_SATISFIED" = "true" ]
}

@test "bootstrap-audit ruff-extend-select flags a quoted hook id using --select" {
  _audit_ruff_select quoted 'repos:
  - repo: https://github.com/astral-sh/ruff-pre-commit
    hooks:
      - id: "ruff-check"
        args: [--select=F]'
  [ "$RUFF_SELECT_SATISFIED" = "false" ]
}

@test "bootstrap-audit ruff-extend-select flags an id line carrying a trailing comment" {
  _audit_ruff_select trailing 'repos:
  - repo: https://github.com/astral-sh/ruff-pre-commit
    hooks:
      - id: ruff-check # lint
        args: [--select, "F"]'
  [ "$RUFF_SELECT_SATISFIED" = "false" ]
}

@test "bootstrap-audit ruff-extend-select ignores --select outside the args region" {
  # `files:` ends the block-args region, so the later value is not an argument.
  _audit_ruff_select outside 'repos:
  - repo: https://github.com/astral-sh/ruff-pre-commit
    hooks:
      - id: ruff-check
        args:
          - --extend-select
          - F
        files: ^src/--select/'
  [ "$RUFF_SELECT_SATISFIED" = "true" ]
}

@test "bootstrap-audit ruff-extend-select sees --select after a quoted value containing ' #'" {
  # A `#` inside a quoted YAML scalar is content, not a comment; a naive comment
  # cut would truncate the line before the real --select and pass the violation.
  _audit_ruff_select quotedhash 'repos:
  - repo: https://github.com/astral-sh/ruff-pre-commit
    hooks:
      - id: ruff-check
        args: [--config, '"'"'lint.dummy-variable-rgx = "^(_+|foo # bar)$"'"'"', --select=F]'
  [ "$RUFF_SELECT_SATISFIED" = "false" ]
}

@test "bootstrap-audit ruff-extend-select still honours a real trailing comment after a quoted value" {
  _audit_ruff_select quotedok 'repos:
  - repo: https://github.com/astral-sh/ruff-pre-commit
    hooks:
      - id: ruff-check
        args: [--config, '"'"'lint.dummy-variable-rgx = "^(_+|foo # bar)$"'"'"'] # never --select
  - repo: https://github.com/other/other
    hooks:
      - id: other'
  [ "$RUFF_SELECT_SATISFIED" = "true" ]
}

@test "bootstrap-audit ruff-extend-select sees --select after an escaped double quote" {
  # `\"` is content inside a double-quoted scalar; treating it as a terminator
  # would desynchronize the scanner and hide the real --select.
  _audit_ruff_select escdquote 'repos:
  - repo: https://github.com/astral-sh/ruff-pre-commit
    hooks:
      - id: ruff-check
        args: [--config, "lint.dummy-variable-rgx = \"^(_+|foo # bar)$\"", --select=F]'
  [ "$RUFF_SELECT_SATISFIED" = "false" ]
}

@test "bootstrap-audit ruff-extend-select sees --select after a doubled single quote" {
  # '' is a literal quote inside a single-quoted scalar, not a terminator.
  _audit_ruff_select escsquote 'repos:
  - repo: https://github.com/astral-sh/ruff-pre-commit
    hooks:
      - id: ruff-check
        args: [--config, '"'"'lint.dummy-variable-rgx = "^(it'"''"'s # a) match)$"'"'"', --select=F]'
  [ "$RUFF_SELECT_SATISFIED" = "false" ]
}

@test "bootstrap-audit ruff-extend-select treats an empty alias as unaliased" {
  # pre-commit defaults `alias` to the empty string, so `alias: ""` is NOT a
  # secondary hook; it must still count as the primary and exempt the isolated one.
  _audit_ruff_select emptyalias 'repos:
  - repo: https://github.com/astral-sh/ruff-pre-commit
    hooks:
      - id: ruff-check
        alias: ""
        args: [--extend-select, "F", --fix]
      - id: ruff-check
        alias: ruff-import-private-name
        args: [--select, "PLC2701"]'
  [ "$RUFF_SELECT_SATISFIED" = "true" ]
}

@test "bootstrap-audit ruff-extend-select sees a violation in a later YAML document" {
  # yq evaluates per document; without slurping, a trailing `---` document would
  # decide the verdict alone and hide the violation in the first.
  _audit_ruff_select multidoc 'repos:
  - repo: https://github.com/astral-sh/ruff-pre-commit
    hooks:
      - id: ruff-check
        args: [--select=F]
---
repos: []'
  [ "$RUFF_SELECT_SATISFIED" = "false" ]
}

@test "bootstrap-audit ruff-extend-select fails closed on a malformed args value" {
  # A scalar `args:` makes the jq predicate error; an audit must not read that
  # as compliant.
  _audit_ruff_select scalarargs 'repos:
  - repo: https://github.com/astral-sh/ruff-pre-commit
    hooks:
      - id: ruff-check
        args: "--select=F"'
  [ "$RUFF_SELECT_SATISFIED" = "false" ]
}

@test "bootstrap-audit precommit requirements fail closed on unparseable YAML" {
  local dir="$BATS_TEST_TMPDIR/badyaml"
  mkdir -p "$dir"
  printf 'repos: [\n  - id: "unterminated\n' >"$dir/.pre-commit-config.yaml"

  run cog::cmd::bootstrap_audit --project-root "$dir" --json

  assert_success
  [ "$(jq -r '.domains[] | select(.domain == "precommit") | .requirements_satisfied' <<<"$output")" = "false" ]
}

@test "bootstrap-audit accepts a dual MIT/Apache license layout" {
  # The Rust ecosystem's `MIT OR Apache-2.0` convention ships two files and no
  # bare LICENSE. Reporting that as an absent license asked the operator for an
  # SPDX id the project had already answered.
  local dir="$BATS_TEST_TMPDIR/dual"
  mkdir -p "$dir"
  touch "$dir/.gitignore" "$dir/README.md" "$dir/LICENSE-MIT" "$dir/LICENSE-APACHE"

  run cog::cmd::bootstrap_audit --project-root "$dir" --json

  assert_success
  local row
  row="$(jq -c '.domains[] | select(.domain == "repo")' <<<"$output")"
  [ "$(jq -r '.present' <<<"$row")" = "true" ]
  [ "$(jq -r '.requires_question' <<<"$row")" = "false" ]
  [ "$(jq -r '[.artifacts[] | select(.name == "LICENSE-MIT")] | length' <<<"$row")" -eq 1 ]
  [ "$(jq -r '[.artifacts[] | select(.name == "LICENSE-APACHE")] | length' <<<"$row")" -eq 1 ]
}

@test "bootstrap-audit accepts COPYING as the license deliverable" {
  local dir="$BATS_TEST_TMPDIR/copying"
  mkdir -p "$dir"
  touch "$dir/.gitignore" "$dir/README.md" "$dir/COPYING"

  run cog::cmd::bootstrap_audit --project-root "$dir" --json

  assert_success
  local row
  row="$(jq -c '.domains[] | select(.domain == "repo")' <<<"$output")"
  [ "$(jq -r '.present' <<<"$row")" = "true" ]
  [ "$(jq -r '.requires_question' <<<"$row")" = "false" ]
}

@test "bootstrap-audit reports a placeholder LICENSE artifact when none exists" {
  local dir="$BATS_TEST_TMPDIR/nolicense"
  mkdir -p "$dir"
  touch "$dir/.gitignore" "$dir/README.md"

  run cog::cmd::bootstrap_audit --project-root "$dir" --json

  assert_success
  local row
  row="$(jq -c '.domains[] | select(.domain == "repo")' <<<"$output")"
  [ "$(jq -r '.present' <<<"$row")" = "false" ]
  [ "$(jq -r '.requires_question' <<<"$row")" = "true" ]
  [ "$(jq -r '[.artifacts[] | select(.name == "LICENSE" and .present == false)] | length' <<<"$row")" -eq 1 ]
}
