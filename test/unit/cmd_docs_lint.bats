# shellcheck disable=SC2016 # Backticks are literal Markdown fixture syntax.

setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
  FIXTURE="$BATS_TEST_TMPDIR/project"
  mkdir -p "$FIXTURE/docs"
  printf '%s\n' '# Docs' 'Plain prose.' >"$FIXTURE/docs/README.md"
}

run_lint() {
  run --separate-stderr env COG_DOCS_LINT_ROOT="$FIXTURE" cog docs-lint
}

write_adr() {
  local status="${1:-Implemented}"
  mkdir -p "$FIXTURE/docs/decisions"
  {
    printf '%s\n' '# ADR-0001: Test choice'
    printf '%s\n' '## Context and Problem Statement' 'A durable choice is needed.'
    printf '%s\n' '## Considered Options' '- First' '- Second'
    printf '%s\n' '## Decision Outcome' 'Chosen option: `First`.'
    printf '%s\n' '## Consequences' '- Good: deterministic.' '- Bad: narrow.'
    printf '%s\n' '## Status' "$status"
    printf '%s\n' '[Enactment](../../lib/example.sh)'
  } >"$FIXTURE/docs/decisions/0001-test-choice.md"
}

write_slice() {
  local id="$1" slug="$2" target="$3"
  local dir="$FIXTURE/docs/plan/slices/${id}-${slug}"
  mkdir -p "$dir"
  {
    printf '%s\n' "# ${id} — Test"
    printf '%s\n' '## Goal' 'A result.'
    printf '%s\n' '## Appetite' 'One implementation session.'
    printf '%s\n' '## Core' 'The result works.'
    printf '%s\n' '## In scope' '- First remainder; cut last-first.'
    printf '%s\n' '## Out of scope' '- Extra behavior.'
    printf '%s\n' '## Governed by' '- `docs/README.md`'
    printf '%s\n' '## Acceptance' '```text' "The system shall pass. -> ${target}" '```'
    printf '%s\n' '## Rabbit holes' '- Drift — escape: stop.'
    printf '%s\n' '## Done when' 'The named test passes.'
    printf '%s\n' '## Revisions' 'None.'
  } >"$dir/README.md"
}

# One milestone line in the fixed grammar: `<id> <slug> — <status> — <appetite>`
# plus the optional trailing note.
milestone_line() {
  local id="$1" slug="$2" status="$3" note="${4:-}" line
  line="- ${id} ${slug} — ${status} — 1 session"
  [[ -n $note ]] && line+=" — ${note}"
  printf '%s\n' "$line"
}

# The two-section surface, with every argument line already placed by its caller.
# `$1` is the `## in flight` body and `$2` the `## closed` body.
write_milestone_sections() {
  mkdir -p "$FIXTURE/docs/plan"
  {
    printf '%s\n\n' '# Milestones'
    printf '%s\n\n' '## in flight'
    [[ -n $1 ]] && printf '%s\n\n' "$1"
    printf '%s\n\n' '## closed'
    [[ -n ${2:-} ]] && printf '%s\n' "$2"
  } >"$FIXTURE/docs/plan/milestones.md"
  return 0
}

# A single slice at id 001, filed into the section its status belongs to.
write_milestones() {
  local status="$1" slug="$2" note="${3:-}" line
  line="$(milestone_line 001 "$slug" "$status" "$note")"
  case "$status" in
    done | cut | reshaped) write_milestone_sections '' "$line" ;;
    *) write_milestone_sections "$line" '' ;;
  esac
}

@test "docs-lint accepts plain documentation and keeps diagnostics off stdout" {
  run_lint

  assert_success
  assert_output --partial $'OK\tfiles=1\tfailures=0'
  [ -z "$stderr" ]
}

@test "docs-lint rejects genuine bold and italic syntax" {
  printf '%s\n' '# Docs' 'This is **bold** and *italic*.' >"$FIXTURE/docs/README.md"

  run_lint

  assert_failure 65
  [ -z "$output" ]
  [[ $stderr == *'docs/README.md:2: decorative strong delimiter'* ]]
}

@test "docs-lint ignores fenced globs and inline code" {
  printf '%s\n' '# Docs' '```text' '**/*.md and _literal_' '```' 'Use `**/*.md` and `_literal_`.' >"$FIXTURE/docs/README.md"

  run_lint

  assert_success
}

@test "docs-lint ignores tilde fences escaped delimiters and intraword underscores" {
  printf '%s\n' '# Docs' '~~~text' '*inside*' '~~~' 'Escaped \*text\* and name_with_parts are literal.' >"$FIXTURE/docs/README.md"

  run_lint

  assert_success
}

@test "docs-lint ignores emphasis inside a double-backtick code span" {
  printf '%s\n' '# Docs' 'Use ``**literal**`` and ```_raw_``` verbatim.' >"$FIXTURE/docs/README.md"

  run_lint

  assert_success
}

@test "docs-lint keeps a longer fence open across a nested shorter fence" {
  printf '%s\n' '# Docs' '````text' '```' '**not emphasis**' '```' '````' 'Plain prose.' >"$FIXTURE/docs/README.md"

  run_lint

  assert_success
}

@test "docs-lint ignores emphasis inside a multiline code span" {
  printf '%s\n' '# Docs' 'Use `a' '**literal**' 'b` here.' >"$FIXTURE/docs/README.md"

  run_lint

  assert_success
}

@test "docs-lint treats escaped backticks as literal rather than span delimiters" {
  printf '%s\n' '# Docs' 'Text \`**real emphasis**\` more.' >"$FIXTURE/docs/README.md"

  run_lint

  assert_failure 65
  [[ $stderr == *'docs/README.md:2: decorative strong delimiter'* ]]
}

@test "docs-lint does not read a four-space-indented backtick line as a fence" {
  printf '%s\n' '# Docs' '    ```' 'This is **real emphasis**.' >"$FIXTURE/docs/README.md"

  run_lint

  assert_failure 65
  [[ $stderr == *'docs/README.md:3: decorative strong delimiter'* ]]
}

@test "docs-lint stops an unclosed code span at a blank line" {
  printf '%s\n' '# Docs' 'Dangling `opener' '' 'This is **real emphasis**.' >"$FIXTURE/docs/README.md"

  run_lint

  assert_failure 65
  [[ $stderr == *'docs/README.md:4: decorative strong delimiter'* ]]
}

@test "docs-lint restores an unclosed backtick run as literal text" {
  printf '%s\n' '# Docs' 'A stray ` tick and then **real emphasis** here.' >"$FIXTURE/docs/README.md"

  run_lint

  assert_failure 65
  [[ $stderr == *'docs/README.md:2: decorative strong delimiter'* ]]
}

@test "docs-lint ends an inline block at a heading" {
  printf '%s\n' '# Docs' '## A ` heading' 'This is **real emphasis**.' >"$FIXTURE/docs/README.md"

  run_lint

  assert_failure 65
  [[ $stderr == *'docs/README.md:3: decorative strong delimiter'* ]]
}

@test "docs-lint does not honor backslash escapes inside an open code span" {
  printf '%s\n' '# Docs' 'Span `code\` then **real emphasis**.' >"$FIXTURE/docs/README.md"

  run_lint

  assert_failure 65
  [[ $stderr == *'docs/README.md:2: decorative strong delimiter'* ]]
}

@test "docs-lint rejects a backtick fence opener carrying a backtick info string" {
  printf '%s\n' '# Docs' '```a`b' 'This is **real emphasis**.' >"$FIXTURE/docs/README.md"

  run_lint

  assert_failure 65
  [[ $stderr == *'docs/README.md:3: decorative strong delimiter'* ]]
}

@test "docs-lint catches strong emphasis spanning a line ending" {
  printf '%s\n' '# Docs' 'This is **foo' 'bar** here.' >"$FIXTURE/docs/README.md"

  run_lint

  assert_failure 65
  [[ $stderr == *'docs/README.md:2: decorative strong delimiter'* ]]
}

@test "docs-lint catches italic emphasis spanning a line ending" {
  printf '%s\n' '# Docs' 'This is *foo' 'bar* here.' >"$FIXTURE/docs/README.md"

  run_lint

  assert_failure 65
  [[ $stderr == *'docs/README.md:2: decorative emphasis delimiter'* ]]
}

@test "docs-lint does not pair code-span delimiters across list items" {
  printf '%s\n' '# Docs' '- item a `' '- item b ` and **real emphasis**' >"$FIXTURE/docs/README.md"

  run_lint

  assert_failure 65
  [[ $stderr == *'decorative strong delimiter'* ]]
}

@test "docs-lint accepts a delimiter run that whitespace stops from closing" {
  printf '%s\n' '# Docs' 'This is **foo' '** bar, literal delimiters.' >"$FIXTURE/docs/README.md"

  run_lint

  assert_success
}

@test "docs-lint accepts a same-line delimiter run preceded by a space" {
  printf '%s\n' '# Docs' 'This is **foo ** bar, literal.' >"$FIXTURE/docs/README.md"

  run_lint

  assert_success
}

@test "docs-lint accepts plain prose wrapped across lines" {
  printf '%s\n' '# Docs' 'A sentence that wraps' 'across two lines cleanly.' >"$FIXTURE/docs/README.md"

  run_lint

  assert_success
}

@test "docs-lint accepts one emphasis line with a non-empty reason" {
  printf '%s\n' '# Docs' '<!-- allow-emphasis: quoted upstream spelling -->' 'This is *verbatim*.' >"$FIXTURE/docs/README.md"

  run_lint

  assert_success
}

@test "docs-lint rejects an empty emphasis escape" {
  printf '%s\n' '# Docs' '<!-- allow-emphasis: -->' 'This is *not allowed*.' >"$FIXTURE/docs/README.md"

  run_lint

  assert_failure 65
}

@test "docs-lint accepts a canonical lean ADR" {
  write_adr Implemented

  run_lint

  assert_success
}

@test "docs-lint rejects ADR heading and status drift" {
  write_adr Done
  sed -i 's/## Consequences/## Results/' "$FIXTURE/docs/decisions/0001-test-choice.md"

  run_lint

  assert_failure 65
  [[ $stderr == *'heading structure differs'* ]]
  [[ $stderr == *'invalid first Status value: Done'* ]]
}

@test "docs-lint rejects punctuated and backticked status values" {
  write_adr 'Implemented.'

  run_lint

  assert_failure 65
  [[ $stderr == *'invalid first Status value: Implemented.'* ]]

  write_adr '`Implemented`'
  run_lint
  assert_failure 65
  [[ $stderr == *'invalid first Status value: `Implemented`'* ]]
}

@test "docs-lint rejects a second lifecycle value in the Status section" {
  write_adr Implemented
  printf '%s\n' 'Accepted' >>"$FIXTURE/docs/decisions/0001-test-choice.md"

  run_lint

  assert_failure 65
  [[ $stderr == *'Status carries a second lifecycle value: Accepted'* ]]
}

@test "docs-lint requires a Superseded status to link its successor" {
  write_adr Superseded
  printf '%s\n' 'Superseded by ADR-0002.' >>"$FIXTURE/docs/decisions/0001-test-choice.md"

  run_lint

  assert_failure 65
  [[ $stderr == *'Superseded status must link its successor ADR'* ]]
}

@test "docs-lint rejects a Superseded link whose destination is not the successor" {
  write_adr Superseded
  printf '%s\n' 'Superseded by [ADR-0002](https://example.invalid/not-the-successor).' \
    >>"$FIXTURE/docs/decisions/0001-test-choice.md"

  run_lint

  assert_failure 65
  [[ $stderr == *'Superseded status must link its successor ADR record'* ]]
}

@test "docs-lint accepts a Superseded link resolving to the successor record" {
  write_adr Superseded
  printf '%s\n' 'Superseded by [ADR-0002](./0002-next-choice.md).' \
    >>"$FIXTURE/docs/decisions/0001-test-choice.md"
  printf '%s\n' '# ADR-0002' >"$FIXTURE/docs/decisions/0002-next-choice.md"

  run_lint

  # 0002 is a bare fixture and fails its own heading contract; the point is that
  # 0001's successor pointer is accepted.
  assert_failure 65
  [[ $stderr != *'0001-test-choice.md: Superseded status must link'* ]]
}

@test "docs-lint rejects an ADR that names itself as its successor" {
  write_adr Superseded
  printf '%s\n' 'Superseded by [ADR-0001](./0001-test-choice.md).' \
    >>"$FIXTURE/docs/decisions/0001-test-choice.md"

  run_lint

  assert_failure 65
  [[ $stderr == *'0001-test-choice.md: Superseded status must link its successor ADR record'* ]]
}

@test "docs-lint rejects an ADR above 350 words" {
  write_adr Implemented
  for _ in $(seq 1 360); do printf 'word ' >>"$FIXTURE/docs/decisions/0001-test-choice.md"; done

  run_lint

  assert_failure 65
  [[ $stderr == *'maximum is 350'* ]]
}

@test "docs-lint rejects slice heading drift" {
  write_slice 001 sample test/unit/sample.bats
  sed -i 's/## Rabbit holes/## Risks/' "$FIXTURE/docs/plan/slices/001-sample/README.md"

  run_lint

  assert_failure 65
  [[ $stderr == *'heading structure differs from the slice contract'* ]]
}

@test "docs-lint exempts shaped slice test forward references" {
  write_slice 001 sample test/unit/future.bats
  write_milestones shaped sample

  run_lint

  assert_success
}

@test "docs-lint requires a shaped slice to have its committed entry document" {
  write_milestones shaped absent

  run_lint

  assert_failure 65
  [[ $stderr == *'milestone slice file not found: docs/plan/slices/001-absent/README.md'* ]]
}

@test "docs-lint rejects a non-canonical milestone slice id" {
  write_slice 001 sample test/unit/future.bats
  write_milestone_sections "$(milestone_line 1 sample shaped)" ''

  run_lint

  assert_failure 65
  [[ $stderr == *'non-canonical slice id: 1'* ]]
}

@test "docs-lint rejects a duplicated milestone id" {
  write_slice 001 sample test/unit/future.bats
  write_milestone_sections \
    "$(milestone_line 001 sample shaped)"$'\n'"$(milestone_line 001 sample shaped)" ''

  run_lint

  assert_failure 65
  [[ $stderr == *'milestone id appears more than once: 001'* ]]
}

@test "docs-lint rejects a slice directory with no milestone line" {
  write_slice 001 sample test/unit/future.bats
  write_slice 002 orphan test/unit/future.bats
  write_milestones shaped sample

  run_lint

  assert_failure 65
  [[ $stderr == *'slice has no milestone line: docs/plan/slices/002-orphan'* ]]
}

@test "docs-lint rejects a milestone slice link pointing at another existing slice" {
  write_slice 001 sample test/unit/future.bats
  write_slice 002 other test/unit/future.bats
  write_milestone_sections \
    "$(milestone_line 001 '[sample](./slices/002-other/README.md)' shaped)"$'\n'"$(milestone_line 002 '[other](./slices/002-other/README.md)' shaped)" ''

  run_lint

  assert_failure 65
  [[ $stderr == *'milestone slice 001 links to ./slices/002-other/README.md, expected ./slices/001-sample/README.md'* ]]
}

@test "docs-lint accepts a milestone slice link matching its own line" {
  write_slice 001 sample test/unit/future.bats
  write_milestone_sections "$(milestone_line 001 '[sample](./slices/001-sample/README.md)' shaped)" ''

  run_lint

  assert_success
}

@test "docs-lint rejects a reshaped successor that is missing or self-referential" {
  write_slice 001 sample test/unit/future.bats
  write_milestones reshaped sample 're-shaped as 009'

  run_lint

  assert_failure 65
  [[ $stderr == *'names a successor with no slice: 009'* ]]

  write_milestones reshaped sample 're-shaped as 001'
  run_lint
  assert_failure 65
  [[ $stderr == *'must name a later successor id'* ]]
}

@test "docs-lint rejects the zero milestone id" {
  write_slice 000 sample test/unit/future.bats
  write_milestone_sections "$(milestone_line 000 sample shaped)" ''

  run_lint

  assert_failure 65
  [[ $stderr == *'non-canonical slice id: 000'* ]]
}

@test "docs-lint rejects a reshaped successor that points backward" {
  write_slice 001 first test/unit/future.bats
  write_slice 002 second test/unit/future.bats
  write_milestone_sections \
    "$(milestone_line 001 first shaped)" \
    "$(milestone_line 002 second reshaped 're-shaped as 001')"

  run_lint

  assert_failure 65
  [[ $stderr == *'must name a later successor id'* ]]
}

@test "docs-lint reports a second directory reusing a listed slice id" {
  write_slice 001 sample test/unit/future.bats
  write_slice 001 alternate test/unit/future.bats
  write_milestones shaped sample

  run_lint

  assert_failure 65
  [[ $stderr == *'slice has no milestone line: docs/plan/slices/001-alternate'* ]]
}

@test "docs-lint requires active slice acceptance targets to exist" {
  write_slice 001 sample test/unit/missing.bats
  write_milestones active sample

  run_lint

  assert_failure 65
  [[ $stderr == *'Acceptance target not found: test/unit/missing.bats'* ]]
}

@test "docs-lint accepts an active slice with an existing named test file" {
  mkdir -p "$FIXTURE/test/unit"
  printf '%s\n' '# fixture' >"$FIXTURE/test/unit/present.bats"
  write_slice 001 sample test/unit/present.bats
  write_milestones active sample

  run_lint

  assert_success
}

@test "docs-lint enforces the complete milestone status vocabulary" {
  write_slice 001 sample test/unit/future.bats
  write_milestones paused sample

  run_lint

  assert_failure 65
  [[ $stderr == *'invalid milestone status: paused'* ]]
}

@test "docs-lint requires reshaped and cut notes" {
  write_slice 001 sample test/unit/future.bats
  write_milestones reshaped sample

  run_lint

  assert_failure 65
  [[ $stderr == *'must name a later successor id'* ]]

  write_milestones cut sample
  run_lint
  assert_failure 65
  [[ $stderr == *'note must name what was cut'* ]]
}

@test "docs-lint rejects a terminal status left in the live section" {
  write_slice 001 sample test/unit/future.bats
  write_milestone_sections "$(milestone_line 001 sample 'done')" ''

  run_lint

  assert_failure 65
  [[ $stderr == *"terminal slice 001 is listed under '## in flight', expected '## closed'"* ]]
}

@test "docs-lint rejects live work filed under the closed section" {
  write_slice 001 sample test/unit/future.bats
  write_milestone_sections '' "$(milestone_line 001 sample shaped)"

  run_lint

  assert_failure 65
  [[ $stderr == *"live slice 001 is listed under '## closed', expected '## in flight'"* ]]
}

@test "docs-lint rejects a milestone line outside both status sections" {
  write_slice 001 sample test/unit/future.bats
  mkdir -p "$FIXTURE/docs/plan"
  {
    printf '%s\n\n' '# Milestones'
    milestone_line 001 sample shaped
  } >"$FIXTURE/docs/plan/milestones.md"

  run_lint

  assert_failure 65
  [[ $stderr == *'milestone line outside a status section'* ]]
}

@test "docs-lint rejects a milestone line that breaks the fixed grammar" {
  write_slice 001 sample test/unit/future.bats
  write_milestone_sections '- 001 sample shaped 1 session' ''

  run_lint

  assert_failure 65
  [[ $stderr == *'does not match the fixed grammar'* ]]
}

@test "docs-lint rejects a milestone line carrying a field past the note" {
  write_slice 001 sample test/unit/future.bats
  write_milestone_sections '- 001 sample — shaped — 1 session — a note — a fifth field' ''

  run_lint

  assert_failure 65
  [[ $stderr == *'does not match the fixed grammar'* ]]
}

@test "docs-lint catches emphasis in the active draft workspace" {
  mkdir -p "$FIXTURE/.draft"
  printf '%s\n' '# Draft' 'This is **still active**.' >"$FIXTURE/.draft/work.md"

  run_lint

  assert_failure 65
  [[ $stderr == *'.draft/work.md:2: decorative strong delimiter'* ]]
}

@test "docs-lint excludes the safe-to-delete hand-off buffer" {
  mkdir -p "$FIXTURE/.draft/safe-to-delete"
  printf '%s\n' '# Archived draft' 'This is **preserved verbatim**.' >"$FIXTURE/.draft/safe-to-delete/work.md"

  run_lint

  assert_success
}

@test "docs-lint help is machine-facing and rejects arguments" {
  run cog docs-lint --help
  assert_success
  assert_output --partial 'Usage: cog docs-lint'

  run cog docs-lint unexpected
  assert_failure 65
}
