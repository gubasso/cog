# shellcheck shell=bash

_common_setup() {
  load "${BATS_TEST_DIRNAME}/../test_helper/bats-support/load"
  load "${BATS_TEST_DIRNAME}/../test_helper/bats-assert/load"
  load "${BATS_TEST_DIRNAME}/../test_helper/bats-file/load"

  # Git hooks (e.g. pre-commit) export repo-local GIT_* variables into the hook
  # process and everything it spawns. Tests that create nested throwaway repos
  # must start from a clean git environment, or an inherited GIT_INDEX_FILE/
  # GIT_DIR makes their `git` commands operate on the parent repo's index. Clear
  # git's own canonical repo-local var list (see githooks(5)).
  local git_env_vars=()
  mapfile -t git_env_vars < <(git rev-parse --local-env-vars 2>/dev/null || :)
  ((${#git_env_vars[@]})) && unset "${git_env_vars[@]}"

  PATH="${BATS_TEST_DIRNAME}/../../bin:${PATH}"
  export XDG_DATA_HOME="${XDG_DATA_HOME:-${BATS_TEST_TMPDIR}/data}"
}
