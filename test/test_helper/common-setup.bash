# shellcheck shell=bash

_common_setup() {
  load "${BATS_TEST_DIRNAME}/../test_helper/bats-support/load"
  load "${BATS_TEST_DIRNAME}/../test_helper/bats-assert/load"
  load "${BATS_TEST_DIRNAME}/../test_helper/bats-file/load"
  PATH="${BATS_TEST_DIRNAME}/../../bin:${PATH}"
}
