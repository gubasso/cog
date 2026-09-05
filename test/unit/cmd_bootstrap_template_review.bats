setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
  export LIB_DIR="${BATS_TEST_DIRNAME}/../../lib"
  export HOME="${BATS_TEST_TMPDIR}/home"
  export XDG_DATA_HOME="${BATS_TEST_TMPDIR}/xdg"
  export XDG_STATE_HOME="${BATS_TEST_TMPDIR}/state"
  # A writable installed skill-refs tree so origin=xdg, writable=true.
  mkdir -p "$HOME" "$XDG_STATE_HOME" "${XDG_DATA_HOME}/cog/skill-refs/templates/pre-commit"
  # shellcheck source=/dev/null
  source "${LIB_DIR}/helpers.sh"
  # shellcheck source=/dev/null
  source "${LIB_DIR}/functions/fn_ui_print.sh"
  # shellcheck source=/dev/null
  source "${LIB_DIR}/functions/fn_log.sh"
  # shellcheck source=/dev/null
  source "${LIB_DIR}/functions/fn_error_raise.sh"
  # shellcheck source=/dev/null
  source "${LIB_DIR}/functions/fn_json_write.sh"
  # shellcheck source=/dev/null
  source "${LIB_DIR}/functions/fn_data.sh"
  # shellcheck source=/dev/null
  source "${LIB_DIR}/functions/fn_research.sh"
  # shellcheck source=/dev/null
  source "${LIB_DIR}/functions/fn_skill_refs.sh"
  # shellcheck source=/dev/null
  source "${LIB_DIR}/functions/fn_template.sh"
  # shellcheck source=/dev/null
  source "${LIB_DIR}/functions/fn_bootstrap_review.sh"
  # shellcheck source=/dev/null
  source "${LIB_DIR}/commands/cmd_bootstrap_template_review.sh"
  SHELF="${BATS_TEST_TMPDIR}/shelf"
}

@test "bootstrap-template-review check reports missing for an empty shelf" {
  run cog::cmd::bootstrap_template_review check --domain precommit --type rust --research-root "$SHELF" --json

  assert_success
  [ "$(jq -r '.ok' <<<"$output")" = "true" ]
  [ "$(jq -r '.review.state' <<<"$output")" = "missing" ]
  [ "$(jq -r '.review.fresh' <<<"$output")" = "false" ]
  [ "$(jq -r '.topic_tags | join(",")' <<<"$output")" = "bootstrap-template,precommit,rust" ]
}

@test "bootstrap-template-review check reports the reported template roots for repo" {
  run cog::cmd::bootstrap_template_review check --domain repo --type generic --research-root "$SHELF" --json

  assert_success
  [ "$(jq -r '[.template_roots[].domain] | join(",")' <<<"$output")" = "gitignore,license,readme" ]
}

@test "bootstrap-template-review check requires --json" {
  run --separate-stderr cog::cmd::bootstrap_template_review check --domain precommit --type rust --research-root "$SHELF"

  assert_failure
  [[ $stderr == *"MissingArgument"* ]]
}

@test "bootstrap-template-review rejects an unknown domain before I/O" {
  run --separate-stderr cog::cmd::bootstrap_template_review check --domain bogus --type rust --json

  assert_failure
  [[ $stderr == *"unknown bootstrap review domain"* ]]
}

@test "bootstrap-template-review rejects an invalid type" {
  run --separate-stderr cog::cmd::bootstrap_template_review check --domain precommit --type "Rust!" --research-root "$SHELF" --json

  assert_failure
  [[ $stderr == *"invalid bootstrap review type"* ]]
}

@test "bootstrap-template-review stamp rejects a non-positive freshness window" {
  run --separate-stderr cog::cmd::bootstrap_template_review stamp --domain precommit --type rust --freshness-days 0 --research-root "$SHELF" --json

  assert_failure
  [[ $stderr == *"invalid freshness window"* ]]
}

@test "bootstrap-template-review check rejects the removed freshness-days option" {
  run --separate-stderr cog::cmd::bootstrap_template_review check --domain precommit --type rust --freshness-days 14 --research-root "$SHELF" --json

  assert_failure
  [[ $stderr == *"unknown bootstrap-template-review check option"* ]]
}

@test "bootstrap-template-review stamp requires a source" {
  run --separate-stderr cog::cmd::bootstrap_template_review stamp --domain precommit --type rust --summary "s" --research-root "$SHELF" --json

  assert_failure
  [[ $stderr == *"missing bootstrap review source"* ]]
}

@test "bootstrap-template-review stamp requires a summary" {
  local src='{"title":"t","url":"https://example.com","publisher":"p","access-date":"2026-07-04"}'
  run --separate-stderr cog::cmd::bootstrap_template_review stamp --domain precommit --type rust --source-json "$src" --research-root "$SHELF" --json

  assert_failure
  [[ $stderr == *"missing bootstrap review summary"* ]]
}

@test "bootstrap-template-review reports an unknown mode" {
  run --separate-stderr cog::cmd::bootstrap_template_review bogus

  assert_failure
  [[ $stderr == *"unknown bootstrap-template-review mode"* ]]
}

@test "bootstrap-template-review check fails closed with an invalid state when skill-refs is unresolved" {
  export LIB_DIR="${BATS_TEST_TMPDIR}/app/lib"
  mkdir -p "$LIB_DIR"
  export XDG_DATA_HOME="${BATS_TEST_TMPDIR}/empty-xdg"
  mkdir -p "${XDG_DATA_HOME}/cog/data"

  run --separate-stderr cog::cmd::bootstrap_template_review check --domain precommit --type rust --research-root "$SHELF" --json

  assert_failure
  [ "$(jq -r '.ok' <<<"$output")" = "false" ]
  [ "$(jq -r '.review.state' <<<"$output")" = "invalid" ]
}

# Write a matching shelf whose total size is above the per-argument kernel cap,
# so any form that routes the entries through argv fails. Linux caps ONE argv
# string at MAX_ARG_STRLEN (128KiB) while macOS caps only the ~1MB total, so the
# payload clears both: 3 records with a 256KiB summary each is about 800KB, and
# check reads the shelf in one pass. printf is a builtin, so building the fixture
# does not itself hit the cap the fixture exists to exceed.
write_oversized_matching_shelf() {
  local revalidate_after="$1"
  local pad i
  pad="$(head -c 262144 /dev/zero | tr '\0' 'x')"
  mkdir -p "$SHELF"
  for i in 1 2 3; do
    printf '{"id":"rs-2026062%s","recorded-date":"2026-06-2%s","topic-tags":["bootstrap-template","precommit","rust"],"sources":[{"title":"t","url":"https://example.test","publisher":"p","access-date":"2026-06-20"}],"stable-summary":"%s","revalidate-after":"%s","consuming-skills":["s"]}\n' \
      "$i" "$i" "$pad" "$revalidate_after"
  done >"${SHELF}/index.jsonl"
}

@test "bootstrap-template-review check reports fresh for a shelf above the argv limit" {
  write_oversized_matching_shelf 2099-01-01

  run cog::cmd::bootstrap_template_review check --domain precommit --type rust --research-root "$SHELF" --json

  assert_success
  [ "$(jq -r '.review.state' <<<"$output")" = "fresh" ]
  [ "$(jq -r '.review.fresh' <<<"$output")" = "true" ]
  [ "$(jq -r '.entry_id' <<<"$output")" = "rs-20260623" ]
  [ "$(jq -r '.revalidate_after' <<<"$output")" = "2099-01-01" ]
}

@test "bootstrap-template-review check narrows fresh out of matching entries past revalidate-after" {
  write_oversized_matching_shelf 2000-01-01

  run cog::cmd::bootstrap_template_review check --domain precommit --type rust --research-root "$SHELF" --json

  assert_success
  [ "$(jq -r '.review.state' <<<"$output")" = "stale" ]
  [ "$(jq -r '.review.fresh' <<<"$output")" = "false" ]
  [ "$(jq -r '.entry_id' <<<"$output")" = "rs-20260623" ]
}
