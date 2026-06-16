# shellcheck shell=bash

_common_setup() {
  load 'test_helper/bats-support/load'
  load 'test_helper/bats-assert/load'
  load 'test_helper/bats-file/load'
  PATH="${BATS_TEST_DIRNAME}/../../bin:${PATH}"
}
