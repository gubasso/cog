setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
  export HOME="${BATS_TEST_TMPDIR}/home"
  export XDG_DATA_HOME="${BATS_TEST_TMPDIR}/data"
  export XDG_STATE_HOME="${BATS_TEST_TMPDIR}/state"
  unset RUN_DIR REFACTOR_GUIDELINE
  mkdir -p "$HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME" "${BATS_TEST_TMPDIR}/repo/src/bin"
}

@test "cog classify-project detects rust cli shape" {
  cat >"${BATS_TEST_TMPDIR}/repo/Cargo.toml" <<'EOF'
[package]
name = "demo"

[[bin]]
name = "demo"

[dependencies]
clap = "4"
EOF

  run bash -c 'cd "$1" && cog classify-project --json' _ "${BATS_TEST_TMPDIR}/repo"

  assert_success
  printf '%s\n' "$output" | jq -e '.is_cli == true and (.languages[] | select(.lang == "rust")) and (.frameworks[] | select(.name == "clap"))' >/dev/null
}

@test "cog classify-project writes a fragment" {
  touch "${BATS_TEST_TMPDIR}/repo/package.json"
  local out="${BATS_TEST_TMPDIR}/classification.json"

  run bash -c 'cd "$1" && cog classify-project "$2"' _ "${BATS_TEST_TMPDIR}/repo" "$out"

  assert_success
  assert_output "RESOLVED $out"
  jq -e '.git_root and (.languages[] | select(.lang == "javascript"))' "$out" >/dev/null
}

@test "cog classify-project detects a knowledge-base markdown project" {
  mkdir -p "${BATS_TEST_TMPDIR}/repo/tech"
  printf '# a\n' >"${BATS_TEST_TMPDIR}/repo/README.md"
  printf '# b\n' >"${BATS_TEST_TMPDIR}/repo/tech/b.md"
  printf '# c\n' >"${BATS_TEST_TMPDIR}/repo/tech/c.md"

  run bash -c 'cd "$1" && cog classify-project --json' _ "${BATS_TEST_TMPDIR}/repo"

  assert_success
  printf '%s\n' "$output" | jq -e '(.languages[] | select(.lang == "markdown")) and (.project_types | index("knowledge-base"))' >/dev/null
}

@test "cog classify-project does not mark a code project with docs as knowledge-base" {
  printf '[package]\nname = "demo"\n' >"${BATS_TEST_TMPDIR}/repo/Cargo.toml"
  printf '# docs\n' >"${BATS_TEST_TMPDIR}/repo/README.md"
  printf '# more\n' >"${BATS_TEST_TMPDIR}/repo/GUIDE.md"

  run bash -c 'cd "$1" && cog classify-project --json' _ "${BATS_TEST_TMPDIR}/repo"

  assert_success
  printf '%s\n' "$output" | jq -e '(.project_types | index("knowledge-base") | not)' >/dev/null
}

@test "cog classify-project treats a markdown vault with tooling scripts as knowledge-base only" {
  # Regression: a doc-dominated vault with a few shell scripts under systems/ and
  # prose that merely mentions "click"/"typer" must not misfire to cli/python.
  local vault="${BATS_TEST_TMPDIR}/vault"
  mkdir -p "$vault/tech" "$vault/systems/net"
  printf '# readme\n' >"$vault/README.md"
  for i in 1 2 3 4 5 6 7 8 9 10 11 12; do
    printf '# note %s\nclick here to typer around with cobra\n' "$i" >"$vault/tech/n$i.md"
  done
  printf '#!/usr/bin/env bash\necho deploy\n' >"$vault/systems/net/deploy.sh"
  chmod +x "$vault/systems/net/deploy.sh"
  printf '#!/bin/sh\necho x\n' >"$vault/systems/net/x.sh"
  chmod +x "$vault/systems/net/x.sh"

  run bash -c 'cd "$1" && cog classify-project --json' _ "$vault"

  assert_success
  printf '%s\n' "$output" | jq -e '
    (.project_types == ["knowledge-base"]) and (.is_cli == false)
    and ((.frameworks | length) == 0) and (.ambiguous == false)
    and (.primary_type == "knowledge-base")
    and ([.languages[].lang] == ["markdown"])' >/dev/null
}

@test "cog classify-project does not invent frameworks from prose keywords" {
  local docs="${BATS_TEST_TMPDIR}/docs"
  mkdir -p "$docs"
  printf '# guide\nWe evaluated click, typer, cobra, commander and yargs.\n' >"$docs/README.md"
  printf '# more\nyargs vs commander notes.\n' >"$docs/notes.md"

  run bash -c 'cd "$1" && cog classify-project --json' _ "$docs"

  assert_success
  printf '%s\n' "$output" | jq -e '(.frameworks | length) == 0 and (.cli_signals | length) == 0' >/dev/null
}

@test "cog classify-project keeps a doc-heavy shell CLI as cli" {
  local tool="${BATS_TEST_TMPDIR}/tool"
  mkdir -p "$tool/bin" "$tool/lib" "$tool/docs"
  printf '#!/usr/bin/env bash\necho hi\n' >"$tool/bin/tool"
  chmod +x "$tool/bin/tool"
  printf 'echo a\n' >"$tool/lib/a.sh"
  printf 'echo b\n' >"$tool/lib/b.sh"
  printf '# doc1\n' >"$tool/docs/d1.md"
  printf '# doc2\n' >"$tool/docs/d2.md"

  run bash -c 'cd "$1" && cog classify-project --json' _ "$tool"

  assert_success
  printf '%s\n' "$output" | jq -e '
    (.is_cli == true) and (.languages[] | select(.lang == "bash"))
    and (.project_types | index("knowledge-base") | not)' >/dev/null
}

@test "cog classify-project trusts a manifest over surrounding docs" {
  local proj="${BATS_TEST_TMPDIR}/proj"
  mkdir -p "$proj/docs"
  printf '[project]\nname = "demo"\n' >"$proj/pyproject.toml"
  for i in 1 2 3 4 5 6 7 8; do printf '# doc %s\n' "$i" >"$proj/docs/d$i.md"; done

  run bash -c 'cd "$1" && cog classify-project --json' _ "$proj"

  assert_success
  printf '%s\n' "$output" | jq -e '
    (.languages[] | select(.lang == "python")) and (.confidence == "high")
    and (.ambiguous == false) and (.project_types | index("knowledge-base") | not)' >/dev/null
}

@test "cog classify-project reports ambiguous when no shape dominates" {
  # Loose scripts with no manifest and no dominant content: deterministic rules
  # cannot decide, so the caller is told to judge.
  local mix="${BATS_TEST_TMPDIR}/mix"
  mkdir -p "$mix"
  printf 'print(1)\n' >"$mix/a.py"
  printf 'print(2)\n' >"$mix/b.py"
  printf 'notes\n' >"$mix/a.txt"
  printf 'more\n' >"$mix/b.txt"

  run bash -c 'cd "$1" && cog classify-project --json' _ "$mix"

  assert_success
  printf '%s\n' "$output" | jq -e '(.ambiguous == true) and (.primary_type == null)' >/dev/null
}

@test "cog classify-project --help dispatches" {
  run cog classify-project --help

  assert_success
  [[ $output == *"Classify repository shape"* ]]
}
