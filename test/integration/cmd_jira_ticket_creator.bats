# shellcheck shell=bash

setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
  export HOME="${BATS_TEST_TMPDIR}/home"
  export XDG_DATA_HOME="${BATS_TEST_TMPDIR}/data"
  export XDG_STATE_HOME="${BATS_TEST_TMPDIR}/state"
  unset RUN_DIR
  mkdir -p "$HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME"

  REPO="${BATS_TEST_TMPDIR}/repo"
  git init -q "$REPO"
  git -C "$REPO" config user.email a@b.c
  git -C "$REPO" config user.name t
  printf 'one\n' >"$REPO/a.txt" && git -C "$REPO" add -A && git -C "$REPO" commit -q -m "feat(api): add token refresh"
  printf 'two\n' >"$REPO/b.txt" && git -C "$REPO" add -A && git -C "$REPO" commit -q -m "refactor(api): tidy client"
  printf 'three\n' >"$REPO/c.txt" && git -C "$REPO" add -A && git -C "$REPO" commit -q -m "fix(db): handle null rows"
  S1="$(git -C "$REPO" rev-parse --short HEAD~2)"
  S2="$(git -C "$REPO" rev-parse --short HEAD~1)"
  S3="$(git -C "$REPO" rev-parse --short HEAD)"
}

@test "cog jira-ticket-creator --help dispatches the desc sentinel" {
  run cog jira-ticket-creator --help
  assert_success
  [[ $output == *"Scaffold, write, and finalize retroactive JIRA ticket drafts."* ]]
}

@test "setup creates the draft directory and parses commits" {
  run cog jira-ticket-creator setup --root "$REPO" --range HEAD~2..HEAD --sha "$(git -C "$REPO" rev-parse HEAD~2)" --path a.txt --json
  assert_success
  printf '%s\n' "$output" | jq -e '
    .ok == true
    and (.draft_dir | contains("/.draft/jira-tickets-"))
    and .commit_count == 3
    and (.paths | index("a.txt"))
    and ([.commits[].type] | index("feat") and index("fix") and index("refactor"))
  ' >/dev/null
  local draft_dir
  draft_dir="$(printf '%s\n' "$output" | jq -r '.draft_dir')"
  [[ -d $draft_dir ]]
}

@test "setup requires an output mode" {
  run cog jira-ticket-creator setup --root "$REPO" --range HEAD~1..HEAD
  assert_failure
}

@test "write derives the filename and validates the ticket" {
  local setup draft_dir body
  setup="$(cog jira-ticket-creator setup --root "$REPO" --range HEAD~2..HEAD --json)"
  draft_dir="$(printf '%s\n' "$setup" | jq -r '.draft_dir')"
  body="${BATS_TEST_TMPDIR}/body.md"
  printf 'h2. Description\n\nAdds token refresh.\n' >"$body"

  run cog jira-ticket-creator write --draft-dir "$draft_dir" --title "Add API token refresh" --issue-type Story --seq 02 --body-file "$body" --json
  assert_success
  printf '%s\n' "$output" | jq -e '.ok == true and .issue_type == "Story" and .slug == "add-api-token-refresh" and (.ticket_path | endswith("02-story-add-api-token-refresh.md")) and .bytes > 0' >/dev/null
  [[ -s "$draft_dir/02-story-add-api-token-refresh.md" ]]
}

@test "write rejects an invalid issue type" {
  local setup draft_dir body
  setup="$(cog jira-ticket-creator setup --root "$REPO" --range HEAD~1..HEAD --json)"
  draft_dir="$(printf '%s\n' "$setup" | jq -r '.draft_dir')"
  body="${BATS_TEST_TMPDIR}/body.md"
  printf 'body\n' >"$body"

  run cog jira-ticket-creator write --draft-dir "$draft_dir" --title "Bad type" --issue-type Feature --body-file "$body" --json
  assert_failure
}

@test "finalize reports full coverage and writes a non-empty INDEX" {
  local setup draft_dir manifest
  setup="$(cog jira-ticket-creator setup --root "$REPO" --range HEAD~2..HEAD --sha "$(git -C "$REPO" rev-parse HEAD~2)" --json)"
  draft_dir="$(printf '%s\n' "$setup" | jq -r '.draft_dir')"
  manifest="${BATS_TEST_TMPDIR}/manifest.json"
  cat >"$manifest" <<EOF
{"tickets":[
  {"slug":"api","issue_type":"Story","title":"API refresh","epic_link":"","path":"$draft_dir/02-story-api.md","shas":["$S1","$S2"]},
  {"slug":"db","issue_type":"Bug","title":"DB null rows","epic_link":"","path":"$draft_dir/03-bug-db.md","shas":["$S3"]}
],"all_shas":["$S1","$S2","$S3"]}
EOF
  run cog jira-ticket-creator finalize --draft-dir "$draft_dir" --manifest "$manifest" --json
  assert_success
  printf '%s\n' "$output" | jq -e '.ok == true and .complete == true and .ticket_count == 2 and .coverage.claimed == 3 and (.coverage.unclaimed | length) == 0' >/dev/null
  [[ -s "$draft_dir/INDEX.md" ]]
}

@test "finalize flags unclaimed and duplicated shas" {
  local setup draft_dir manifest
  setup="$(cog jira-ticket-creator setup --root "$REPO" --range HEAD~2..HEAD --sha "$(git -C "$REPO" rev-parse HEAD~2)" --json)"
  draft_dir="$(printf '%s\n' "$setup" | jq -r '.draft_dir')"
  manifest="${BATS_TEST_TMPDIR}/manifest.json"
  cat >"$manifest" <<EOF
{"tickets":[
  {"slug":"api","issue_type":"Story","title":"API refresh","epic_link":"","path":"$draft_dir/02-story-api.md","shas":["$S1","$S1"]}
],"all_shas":["$S1","$S2","$S3"]}
EOF
  run cog jira-ticket-creator finalize --draft-dir "$draft_dir" --manifest "$manifest" --json
  assert_success
  printf '%s\n' "$output" | jq -e '
    .ok == false and .complete == false
    and (.coverage.unclaimed | length) == 2
    and (.coverage.unclaimed | index("'"$S2"'"))
    and (.coverage.unclaimed | index("'"$S3"'"))
    and (.coverage.duplicated | index("'"$S1"'"))
  ' >/dev/null
}

@test "finalize rejects a manifest without a tickets array" {
  local setup draft_dir manifest
  setup="$(cog jira-ticket-creator setup --root "$REPO" --range HEAD~1..HEAD --json)"
  draft_dir="$(printf '%s\n' "$setup" | jq -r '.draft_dir')"
  manifest="${BATS_TEST_TMPDIR}/manifest.json"
  printf '{"all_shas":[]}\n' >"$manifest"
  run cog jira-ticket-creator finalize --draft-dir "$draft_dir" --manifest "$manifest" --json
  assert_failure
}
