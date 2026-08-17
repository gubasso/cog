#!/usr/bin/env bats
#
# Fidelity assertions over the shipped license templates.
#
# A license is the one template whose text carries legal effect, so "close
# enough" is a defect: `cog license-apply` copies these bytes into a real
# project's LICENSE. Both texts here were shipped reflowed into long paragraphs
# with substituted characters — the GPL-3.0 template had lost two thirds of its
# lines and mangled a URL — which is a paraphrase of a license, not the license.
#
# The verbatim texts are pinned by digest rather than re-fetched, so the check
# stays offline and deterministic. Upstream is:
#   Apache-2.0  https://www.apache.org/licenses/LICENSE-2.0.txt
#   GPL-3.0     https://www.gnu.org/licenses/gpl-3.0.txt
# A deliberate update re-fetches from those URLs and repins the digest here.

setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
  LICENSE_TEMPLATES="${BATS_TEST_DIRNAME}/../../skill-refs/templates/license"
}

_digest() {
  sha256sum "$1" | cut -d' ' -f1
}

@test "apache-2.0 template is the verbatim upstream text" {
  [ "$(_digest "${LICENSE_TEMPLATES}/apache-2.0/LICENSE")" = \
    "cfc7749b96f63bd31c3c42b5c471bf756814053e847c10f3eb003417bc523d30" ]
}

@test "gpl-3.0 template is the verbatim upstream text" {
  [ "$(_digest "${LICENSE_TEMPLATES}/gpl-3.0/LICENSE")" = \
    "3972dc9744f6499f0f9b2dbf76696f2ae7ad8af9b23dde66d6af86c9dfb36986" ]
}

# MIT and BSD-3-Clause carry {{YEAR}}/{{HOLDER}} placeholders, so they cannot be
# digest-pinned. Assert the placeholders and the operative clauses instead.
@test "mit and bsd templates keep their substitution placeholders" {
  local f
  for f in mit bsd-3-clause; do
    grep -qF '{{YEAR}}' "${LICENSE_TEMPLATES}/${f}/LICENSE"
    grep -qF '{{HOLDER}}' "${LICENSE_TEMPLATES}/${f}/LICENSE"
    grep -qF 'WITHOUT WARRANTY' "${LICENSE_TEMPLATES}/${f}/LICENSE" \
      || grep -qF 'AS IS' "${LICENSE_TEMPLATES}/${f}/LICENSE"
  done
}

@test "verbatim licenses carry no substitution placeholders" {
  local f
  for f in apache-2.0 gpl-3.0; do
    run ! grep -qF '{{' "${LICENSE_TEMPLATES}/${f}/LICENSE"
  done
}
