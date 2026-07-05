setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
  export XDG_DATA_HOME="${BATS_TEST_TMPDIR}/data"
}

@test "cog spec-leakage-scan exits zero for a clean tech-agnostic spec" {
  cat >"${BATS_TEST_TMPDIR}/clean.md" <<'EOF'
# Behavioral Contract

The system accepts an item, records its lifecycle, and reports the current state.

Scenario: complete a valid item
Given a pending item
When the item is completed
Then it is retained with completion metadata
EOF

  run cog spec-leakage-scan "${BATS_TEST_TMPDIR}/clean.md"

  assert_success
  printf '%s\n' "$output" | jq -e '.ok == true and (.findings | length == 0)' >/dev/null
}

@test "cog spec-leakage-scan does not fire on common English words in behavioral prose" {
  cat >"${BATS_TEST_TMPDIR}/prose.md" <<'EOF'
# Behavioral Contract

Each request must go to exactly one worker node in the cluster.
The service binds a network port and stops accepting work when saturated.
EOF

  run cog spec-leakage-scan "${BATS_TEST_TMPDIR}/prose.md"

  assert_success
  printf '%s\n' "$output" | jq -e '.ok == true and (.findings | length == 0)' >/dev/null
}

@test "cog spec-leakage-scan reports planted built-in and denylist leaks" {
  cat >"${BATS_TEST_TMPDIR}/denylist.txt" <<'EOF'
legacy-sync
EOF
  cat >"${BATS_TEST_TMPDIR}/leaky.md" <<'EOF'
# Behavioral Contract

Use python for the processor.
Call legacy-sync after import.
describe("state transition", () => {})
This is a reimplementation.
EOF

  run cog spec-leakage-scan "${BATS_TEST_TMPDIR}/leaky.md" --source-denylist "${BATS_TEST_TMPDIR}/denylist.txt"

  assert_failure 1
  printf '%s\n' "$output" | jq -e '
    .ok == false
    and (.findings | length == 4)
    and ([.findings[].category] | index("stack_tokens"))
    and ([.findings[].category] | index("source_denylist"))
    and ([.findings[].category] | index("test_structure_patterns"))
    and ([.findings[].category] | index("intent_tokens"))
  ' >/dev/null
}

@test "cog spec-leakage-scan treats denylist tokens as literals, not regexes" {
  cat >"${BATS_TEST_TMPDIR}/deny.txt" <<'EOF'
foo.py
c++
EOF
  # Text that a regex interpretation of the tokens would falsely match:
  # 'foo.py' as a regex matches 'fooXpy'; 'c++' as a regex matches any line with a 'c'.
  cat >"${BATS_TEST_TMPDIR}/clean.md" <<'EOF'
# Behavioral Contract
The fooXpy accessor returns the current state cleanly.
EOF

  run cog spec-leakage-scan "${BATS_TEST_TMPDIR}/clean.md" --source-denylist "${BATS_TEST_TMPDIR}/deny.txt"

  assert_success
  printf '%s\n' "$output" | jq -e '.ok == true and (.findings | length == 0)' >/dev/null
}

@test "cog spec-leakage-scan catches denylist tokens containing metacharacters" {
  cat >"${BATS_TEST_TMPDIR}/deny.txt" <<'EOF'
foo.py
c++
EOF
  cat >"${BATS_TEST_TMPDIR}/leaky.md" <<'EOF'
# Design
See foo.py for the accessor.
The core stays in C++.
EOF

  run cog spec-leakage-scan "${BATS_TEST_TMPDIR}/leaky.md" --source-denylist "${BATS_TEST_TMPDIR}/deny.txt"

  assert_failure 1
  printf '%s\n' "$output" | jq -e '
    .ok == false
    and ([.findings[] | select(.category == "source_denylist") | .token] | index("foo.py"))
    and ([.findings[] | select(.category == "source_denylist") | .token] | index("c++"))
  ' >/dev/null
}

@test "cog spec-leakage-scan catches built-in taxonomy without a denylist" {
  cat >"${BATS_TEST_TMPDIR}/built-in.md" <<'EOF'
# Notes

The behavior references src/main.rs and assert_eq! examples.
EOF

  run cog spec-leakage-scan "${BATS_TEST_TMPDIR}/built-in.md" --json

  assert_failure 1
  printf '%s\n' "$output" | jq -e '
    .ok == false
    and ([.findings[].category] | index("command_surface_patterns"))
    and ([.findings[].category] | index("test_structure_patterns"))
  ' >/dev/null
}
