setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
  export HOME="${BATS_TEST_TMPDIR}/home"
  export XDG_DATA_HOME="${BATS_TEST_TMPDIR}/data"
  export XDG_STATE_HOME="${BATS_TEST_TMPDIR}/state"
  export RIPTASK_REPO="${BATS_TEST_TMPDIR}/store"
  unset RUN_DIR DOCS_NOTES_REPO REFACTOR_GUIDELINE
  mkdir -p "$HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME" "${BATS_TEST_TMPDIR}/fakebin"
  export TSK_LOG="${BATS_TEST_TMPDIR}/tsk-argv.log"
  cat >"${BATS_TEST_TMPDIR}/fakebin/tsk" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$TSK_LOG"
case "$1" in
  doctor)
    exit 0
    ;;
  init)
    mkdir -p "$RIPTASK_REPO/templates"
    printf 'config\n' >"$RIPTASK_REPO/config.yaml"
    printf 'template\n' >"$RIPTASK_REPO/templates/task.md"
    ;;
  *)
    exit 2
    ;;
esac
EOF
  chmod +x "${BATS_TEST_TMPDIR}/fakebin/tsk"
  export PATH="${BATS_TEST_TMPDIR}/fakebin:$PATH"
}

@test "cog tsk-store-init initializes missing store" {
  run cog tsk-store-init --json

  assert_success
  printf '%s\n' "$output" | jq -e '.store == "'"$RIPTASK_REPO"'" and .initialized == true and .template_exists == true' >/dev/null
  assert_file_contains "$TSK_LOG" "init --system"
}

@test "cog tsk-store-init --help dispatches" {
  run cog tsk-store-init --help

  assert_success
  [[ $output == *"Resolve and initialize the shared tsk store"* ]]
}
