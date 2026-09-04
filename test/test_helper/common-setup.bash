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

  # Durable-job wrappers export internal COG_LR_* state into their child. Tests
  # must not accidentally treat that orchestration state as plugin contract
  # input or otherwise vary based on how the suite was launched.
  local cog_longrun_env_vars=()
  mapfile -t cog_longrun_env_vars < <(compgen -A variable COG_LR_ || :)
  ((${#cog_longrun_env_vars[@]})) && unset "${cog_longrun_env_vars[@]}"

  # Neutralize the developer's own git configuration. Setting HOME to a temp dir
  # is not enough: git reads $XDG_CONFIG_HOME/git/config first, and that variable
  # keeps pointing at the real config. A global config carrying a `~`-relative
  # hook path then resolves that `~` against the test's temp HOME, where the hook
  # does not exist, and every test that makes a commit fails on a machine whose
  # owner configured one. GIT_CONFIG_GLOBAL and GIT_CONFIG_SYSTEM (git 2.32+) are
  # git's own opt-out, so the suite reads repo-local configuration alone.
  export GIT_CONFIG_GLOBAL=/dev/null
  export GIT_CONFIG_SYSTEM=/dev/null

  PATH="${BATS_TEST_DIRNAME}/../../bin:${PATH}"
  export XDG_DATA_HOME="${XDG_DATA_HOME:-${BATS_TEST_TMPDIR}/data}"
}
