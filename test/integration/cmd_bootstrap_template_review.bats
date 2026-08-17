setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
  export HOME="${BATS_TEST_TMPDIR}/home"
  export XDG_DATA_HOME="${BATS_TEST_TMPDIR}/xdg"
  export XDG_STATE_HOME="${BATS_TEST_TMPDIR}/state"
  # A writable installed skill-refs tree so origin=xdg, writable=true.
  mkdir -p "$HOME" "$XDG_STATE_HOME" \
    "${XDG_DATA_HOME}/cog/skill-refs/templates/pre-commit/rust" \
    "${XDG_DATA_HOME}/cog/data"
  # A stamp asserts every --changed-template path exists under the SoT, so the
  # tree carries the files these tests claim to have edited.
  SKILL_REFS="${XDG_DATA_HOME}/cog/skill-refs"
  mkdir -p "${SKILL_REFS}/templates/cargo-publish/docs" \
    "${SKILL_REFS}/templates/installer/bash"
  touch "${SKILL_REFS}/templates/pre-commit/rust/.pre-commit-config.yaml" \
    "${SKILL_REFS}/templates/cargo-publish/docs/PUBLISHING.md" \
    "${SKILL_REFS}/templates/installer/bash/install.sh"
  SHELF="${BATS_TEST_TMPDIR}/shelf"
  SRC='{"title":"pre-commit hooks","url":"https://pre-commit.com/hooks.html","publisher":"pre-commit","access-date":"2026-07-04"}'
}

@test "bootstrap-template-review round-trips missing -> stamp -> fresh" {
  run cog bootstrap-template-review check --domain precommit --type rust --research-root "$SHELF" --json
  assert_success
  [ "$(jq -r '.review.state' <<<"$output")" = "missing" ]

  run cog bootstrap-template-review stamp --domain precommit --type rust \
    --summary "reviewed rust pre-commit hooks; kept editorconfig-checker" \
    --source-json "$SRC" \
    --changed-template "templates/pre-commit/rust/.pre-commit-config.yaml" \
    --research-root "$SHELF" --json
  assert_success
  [ "$(jq -r '.action' <<<"$output")" = "stamp" ]
  [ "$(jq -r '.entry_id' <<<"$output")" != "null" ]
  [ "$(jq -r '.changed_templates[0]' <<<"$output")" = "templates/pre-commit/rust/.pre-commit-config.yaml" ]
  [ "$(jq -r '.skill_refs.origin' <<<"$output")" = "xdg" ]

  run cog bootstrap-template-review check --domain precommit --type rust --research-root "$SHELF" --json
  assert_success
  [ "$(jq -r '.review.state' <<<"$output")" = "fresh" ]
  [ "$(jq -r '.review.fresh' <<<"$output")" = "true" ]
  [ "$(jq -r '.summary' <<<"$output")" = "reviewed rust pre-commit hooks; kept editorconfig-checker" ]
}

@test "bootstrap-template-review freshness is keyed by domain and type" {
  run cog bootstrap-template-review stamp --domain precommit --type rust \
    --summary "rust review" --source-json "$SRC" --research-root "$SHELF" --json
  assert_success

  # A different type stays missing even though precommit,rust is fresh.
  run cog bootstrap-template-review check --domain precommit --type python --research-root "$SHELF" --json
  assert_success
  [ "$(jq -r '.review.state' <<<"$output")" = "missing" ]
}

@test "bootstrap-template-review stamp records a validated research-shelf entry" {
  run cog bootstrap-template-review stamp --domain nix --type generic \
    --summary "nix flake review" --source-json "$SRC" --research-root "$SHELF" --json
  assert_success

  run cog research-shelf validate --root "$SHELF" --json
  assert_success
  [ "$(jq -r '.ok' <<<"$output")" = "true" ]
  [ "$(jq -r '.entries' <<<"$output")" -ge 1 ]
}

@test "bootstrap-template-review stamp records the merged owner as the consuming skill" {
  run cog bootstrap-template-review stamp --domain precommit --type rust \
    --summary "hook review" --source-json "$SRC" --research-root "$SHELF" --json
  assert_success
  [ "$(jq -r '.entry."consuming-skills"[0]' <<<"$output")" = "bootstrap-lint" ]

  run cog bootstrap-template-review stamp --domain cargo-publish --type rust \
    --summary "publish review" --source-json "$SRC" --research-root "$SHELF" --json
  assert_success
  [ "$(jq -r '.entry."consuming-skills"[0]' <<<"$output")" = "bootstrap-rust" ]

  run cog bootstrap-template-review stamp --domain nix --type generic \
    --summary "flake review" --source-json "$SRC" --research-root "$SHELF" --json
  assert_success
  [ "$(jq -r '.entry."consuming-skills"[0]' <<<"$output")" = "bootstrap-nix" ]
}

@test "bootstrap-template-review stamp fails fast on a non-writable template SoT" {
  chmod -R a-w "${XDG_DATA_HOME}/cog/skill-refs"

  run --separate-stderr cog bootstrap-template-review stamp --domain precommit --type rust \
    --summary "s" --source-json "$SRC" --research-root "$SHELF" --json

  chmod -R u+w "${XDG_DATA_HOME}/cog/skill-refs"
  assert_failure
  [[ $stderr == *"not writable"* ]]
}

@test "bootstrap-template-review round-trips the cargo-publish domain" {
  run cog bootstrap-template-review check --domain cargo-publish --type rust --research-root "$SHELF" --json
  assert_success
  [ "$(jq -r '.review.state' <<<"$output")" = "missing" ]

  run cog bootstrap-template-review stamp --domain cargo-publish --type rust \
    --summary "reviewed release-plz + cargo-dist publishing setup" \
    --source-json "$SRC" \
    --changed-template "templates/cargo-publish/docs/PUBLISHING.md" \
    --research-root "$SHELF" --json
  assert_success
  [ "$(jq -r '.action' <<<"$output")" = "stamp" ]

  run cog bootstrap-template-review check --domain cargo-publish --type rust --research-root "$SHELF" --json
  assert_success
  [ "$(jq -r '.review.fresh' <<<"$output")" = "true" ]
}

@test "bootstrap-template-review round-trips the installer domain" {
  run cog bootstrap-template-review check --domain installer --type bash --research-root "$SHELF" --json
  assert_success
  [ "$(jq -r '.review.state' <<<"$output")" = "missing" ]
  [ "$(jq -r '.template_roots[0].domain' <<<"$output")" = "installer" ]

  run cog bootstrap-template-review stamp --domain installer --type bash \
    --summary "reviewed manifest-copy install/uninstall UX standard" \
    --source-json "$SRC" \
    --changed-template "templates/installer/bash/install.sh" \
    --research-root "$SHELF" --json
  assert_success
  [ "$(jq -r '.action' <<<"$output")" = "stamp" ]

  run cog bootstrap-template-review check --domain installer --type bash --research-root "$SHELF" --json
  assert_success
  [ "$(jq -r '.review.fresh' <<<"$output")" = "true" ]
}

@test "bootstrap-template-review rejects rust (ships no cog templates)" {
  run --separate-stderr cog bootstrap-template-review check --domain rust --type rust --research-root "$SHELF" --json
  assert_failure
  [[ $stderr == *"unknown bootstrap review domain"* ]]
}

@test "bootstrap-template-review stamp refuses a changed template that never landed" {
  # A freshness record is also a claim that the named edits reached the SoT; a
  # later check reports the domain fresh on the strength of it and skips the
  # review, so an unwritten path must fail the stamp rather than be recorded.
  run --separate-stderr cog bootstrap-template-review stamp --domain precommit --type rust \
    --summary "reviewed rust pre-commit hooks" \
    --source-json "$SRC" \
    --changed-template "templates/pre-commit/rust/.pre-commit-config.yaml" \
    --changed-template "templates/pre-commit/rust/never-written.yaml" \
    --research-root "$SHELF" --json

  assert_failure
  [[ $stderr == *"never-written.yaml"* ]]

  run cog bootstrap-template-review check --domain precommit --type rust --research-root "$SHELF" --json
  assert_success
  [ "$(jq -r '.review.state' <<<"$output")" = "missing" ]
}

@test "bootstrap-template-review stamp accepts an absolute changed-template path" {
  run cog bootstrap-template-review stamp --domain precommit --type rust \
    --summary "reviewed rust pre-commit hooks" \
    --source-json "$SRC" \
    --changed-template "${SKILL_REFS}/templates/pre-commit/rust/.pre-commit-config.yaml" \
    --research-root "$SHELF" --json

  assert_success
  [ "$(jq -r '.action' <<<"$output")" = "stamp" ]
}

@test "bootstrap-template-review stamp refuses an absolute path outside the SoT" {
  # Existence alone is satisfiable by any file on the box, which would authorize
  # exactly the misleading freshness stamp this check exists to refuse.
  local outside="${BATS_TEST_TMPDIR}/elsewhere.yaml"
  touch "$outside"

  run --separate-stderr cog bootstrap-template-review stamp --domain precommit --type rust \
    --summary "reviewed rust pre-commit hooks" \
    --source-json "$SRC" \
    --changed-template "$outside" \
    --research-root "$SHELF" --json

  assert_failure
  [[ $stderr == *"escapes the skill-refs SoT"* ]]

  run cog bootstrap-template-review check --domain precommit --type rust --research-root "$SHELF" --json
  assert_success
  [ "$(jq -r '.review.state' <<<"$output")" = "missing" ]
}

@test "bootstrap-template-review stamp refuses a relative path that escapes the SoT" {
  touch "${XDG_DATA_HOME}/cog/escaped.yaml"

  run --separate-stderr cog bootstrap-template-review stamp --domain precommit --type rust \
    --summary "reviewed rust pre-commit hooks" \
    --source-json "$SRC" \
    --changed-template "../escaped.yaml" \
    --research-root "$SHELF" --json

  assert_failure
  [[ $stderr == *"escapes the skill-refs SoT"* ]]
}

@test "bootstrap-template-review stamp refuses a directory as a changed template" {
  # A stamp names template edits; the enclosing directory existing says nothing
  # about whether the edit landed.
  run --separate-stderr cog bootstrap-template-review stamp --domain precommit --type rust \
    --summary "reviewed rust pre-commit hooks" \
    --source-json "$SRC" \
    --changed-template "templates/pre-commit/rust" \
    --research-root "$SHELF" --json

  assert_failure
  [[ $stderr == *"does not exist"* ]]
}
