# shellcheck shell=bash

cog::fn::docs_lint::root() {
  local root="${COG_DOCS_LINT_ROOT:-$PWD}"
  [[ -d $root ]] || cog::fn::error_raise "InputNotFound" \
    "documentation root not found" "path: ${root}" "" "run from a project root"
  realpath "$root"
}

cog::fn::docs_lint::files() {
  local root="$1" path
  local -a roots=()

  [[ -d $root/docs ]] && roots+=("$root/docs")
  [[ -d $root/skill-refs/docs-design ]] && roots+=("$root/skill-refs/docs-design")
  [[ -d $root/.draft ]] && roots+=("$root/.draft")

  # The retired archive is a user-owned hand-off buffer, not an active docs source.
  ((${#roots[@]})) || return 0
  while IFS= read -r -d '' path; do
    printf '%s\0' "$path"
  done < <(find "${roots[@]}" -type f -name '*.md' \
    ! -path "$root/.draft/safe-to-delete/*" -print0 | sort -z)
}

cog::fn::docs_lint::relative() {
  local root="$1" path="$2"
  printf '%s\n' "${path#"$root"/}"
}

cog::fn::docs_lint::emphasis() {
  local root="$1" file="$2" rel
  rel="$(cog::fn::docs_lint::relative "$root" "$file")"
  awk -v path="$rel" '
    # Code spans are resolved one inline block at a time, not one line at a time: a
    # span may contain a line ending, and an opener that never closes inside its
    # block is literal text rather than a swallow-everything delimiter.

    # Inside an open span a backslash is an ordinary character, so the closer search
    # deliberately does not honor escapes.
    function find_close(s, from, run,   n, k, m) {
      n = length(s); k = from
      while (k <= n) {
        if (substr(s, k, 1) != "`") { k++; continue }
        m = k
        while (m <= n && substr(s, m, 1) == "`") m++
        if (m - k == run) return m
        k = m
      }
      return 0
    }
    # Outside a span a backslash escape hides the character after it, which is what
    # keeps an escaped backtick from opening a span and escaped emphasis from firing.
    function clean_spans(s,   out, i, n, c, nxt, j, run, endpos, inner, gap) {
      out = ""; i = 1; n = length(s)
      while (i <= n) {
        c = substr(s, i, 1)
        if (c == "\n") { out = out c; i++; continue }
        if (c == "\\") {
          nxt = substr(s, i + 1, 1)
          if (nxt ~ /[[:punct:]]/) { i += 2; continue }
          out = out c; i++; continue
        }
        if (c != "`") { out = out c; i++; continue }
        j = i
        while (j <= n && substr(s, j, 1) == "`") j++
        run = j - i
        endpos = find_close(s, j, run)
        if (endpos == 0) {
          # No closer in this block: the run is literal, so keep scanning past it.
          out = out substr(s, i, run)
          i = j
          continue
        }
        # Drop the span but keep its line endings so reported line numbers hold.
        inner = substr(s, i, endpos - i)
        gap = gsub(/\n/, "\n", inner)
        while (gap-- > 0) out = out "\n"
        i = endpos
      }
      return out
    }
    # A closing delimiter run may not be preceded by whitespace, and a line ending
    # counts as whitespace, so the optional tail must end on a non-space character.
    function strong_form(text) {
      return text ~ /(^|[^[:alnum:]_])__[^_[:space:]]([^_]*[^_[:space:]])?__([^[:alnum:]_]|$)/ \
          || text ~ /\*\*[^*[:space:]]([^*]*[^*[:space:]])?\*\*/
    }
    function emphasized(text) {
      return strong_form(text) \
          || text ~ /(^|[^[:alnum:]_])_[^_[:space:]]([^_]*[^_[:space:]])?_([^[:alnum:]_]|$)/ \
          || text ~ /(^|[^*])\*[^*[:space:]]([^*]*[^*[:space:]])?\*([^*]|$)/
    }
    function report(text, lineno, prev,   delimiter) {
      if (!emphasized(text)) return 0
      if (prev ~ /^<!--[[:space:]]*allow-emphasis:[[:space:]]*[^[:space:]][^>]*-->[[:space:]]*$/) return 0
      delimiter = strong_form(text) ? "strong" : "emphasis"
      printf "%s:%d: decorative %s delimiter\n", path, lineno, delimiter > "/dev/stderr"
      failures++
      return 1
    }
    # Emphasis may span a line ending, so a block with no per-line hit is re-checked
    # flattened. The block'"'"'s first line is reported, because that is where a reader
    # starts looking for a delimiter pair that opens on one line and closes on another.
    function flush_block(   joined, cleaned, parts, count, i, hits, flat) {
      if (blk == 0) return
      joined = ""
      for (i = 1; i <= blk; i++) joined = joined (i > 1 ? "\n" : "") blk_text[i]
      cleaned = clean_spans(joined)
      count = split(cleaned, parts, "\n")
      hits = 0
      for (i = 1; i <= count && i <= blk; i++) hits += report(parts[i], blk_no[i], blk_prev[i])
      if (hits == 0 && blk > 1) {
        flat = cleaned
        gsub(/\n/, " ", flat)
        report(flat, blk_no[1], blk_prev[1])
      }
      blk = 0
    }
    function push(text, lineno, prev) {
      blk++
      blk_text[blk] = text
      blk_no[blk] = lineno
      blk_prev[blk] = prev
    }
    function run_of(s, ch,   run) {
      run = 0
      while (substr(s, run + 1, 1) == ch) run++
      return run
    }
    BEGIN { fence_char = ""; fence_len = 0; blk = 0; last = ""; failures = 0 }
    {
      raw = $0
      indent = 0
      while (substr(raw, indent + 1, 1) == " ") indent++
      stripped = substr(raw, indent + 1)
      head = substr(stripped, 1, 1)
      run = (indent <= 3 && (head == "`" || head == "~")) ? run_of(stripped, head) : 0
      info = substr(stripped, run + 1)

      if (fence_char != "") {
        if (head == fence_char && run >= fence_len) {
          rest = info
          sub(/[[:space:]]+$/, "", rest)
          if (rest == "") { fence_char = ""; fence_len = 0 }
        }
        last = raw
        next
      }
      # A backtick fence opener may not carry a backtick in its info string.
      if (run >= 3 && !(head == "`" && index(info, "`") > 0)) {
        flush_block()
        fence_char = head
        fence_len = run
        last = raw
        next
      }
      # Block boundaries: a span cannot continue past a blank line, a heading, an
      # indented-code line, a table row, or an HTML block.
      if (raw ~ /^[[:space:]]*$/ || stripped ~ /^#{1,6}([[:space:]]|$)/ || indent >= 4 \
          || stripped ~ /^\|/ || stripped ~ /^<!--/ || stripped ~ /^(-{3,}|={3,})[[:space:]]*$/) {
        flush_block()
        if (raw !~ /^[[:space:]]*$/) push(raw, NR, last)
        flush_block()
        last = raw
        next
      }
      # A new list item starts a new inline block: delimiters never pair across items.
      if (stripped ~ /^([-*+]|[0-9]+[.)])[[:space:]]/) flush_block()
      push(raw, NR, last)
      last = raw
    }
    END { flush_block(); exit failures > 0 ? 1 : 0 }
  ' "$file"
}

cog::fn::docs_lint::headings_equal() {
  local root="$1" file="$2" label="$3"
  shift 3
  local rel actual expected
  rel="$(cog::fn::docs_lint::relative "$root" "$file")"
  actual="$(sed -n 's/^## /## /p' "$file")"
  expected="$(printf '%s\n' "$@")"
  if [[ $actual != "$expected" ]]; then
    printf '%s\n' "${rel}: heading structure differs from ${label}" >&2
    return 1
  fi
}

# A successor pointer is only a pointer when its destination is the named record and
# that record is a later one: the label alone can name ADR-0002 while the link goes
# anywhere at all, and a record cannot supersede itself.
cog::fn::docs_lint::successor_link() {
  local file="$1" tail="$2" dir number target self
  self="$(basename "$file")"
  self="${self%%-*}"
  # The pattern lives in a variable: an inline [[ =~ ]] regex loses its backslashes
  # to quote removal, which silently turns this into an unmatched-paren error.
  local pattern='\[[^]]*ADR-([0-9]{4})[^]]*\]\(([^)]+)\)'
  dir="$(dirname "$file")"
  while [[ $tail =~ $pattern ]]; do
    number="${BASH_REMATCH[1]}"
    target="${BASH_REMATCH[2]}"
    tail="${tail#*"${BASH_REMATCH[0]}"}"
    target="${target%%#*}"
    target="${target#./}"
    [[ $target == "$number"-*.md ]] || continue
    [[ -f $dir/$target ]] || continue
    ((10#$number > 10#$self)) && return 0
  done
  return 1
}

cog::fn::docs_lint::adr() {
  local root="$1" file="$2" rel words status status_tail extra
  local failed=0
  rel="$(cog::fn::docs_lint::relative "$root" "$file")"

  cog::fn::docs_lint::headings_equal "$root" "$file" "the ADR contract" \
    "## Context and Problem Statement" "## Considered Options" "## Decision Outcome" \
    "## Consequences" "## Status" || failed=1

  words="$(awk '
    NR == 1 { next }
    /^<!--[[:space:]]*markdownlint-configure-file/ { next }
    { for (i = 1; i <= NF; i++) count++ }
    END { print count + 0 }
  ' "$file")"
  if ((words > 350)); then
    printf '%s\n' "${rel}: ADR body has ${words} words; maximum is 350" >&2
    failed=1
  fi

  # The value is compared byte for byte: `Implemented.` and `` `Implemented` `` are
  # the exact drift forms the closed vocabulary exists to reject.
  status="$(awk '
    /^## Status[[:space:]]*$/ { found = 1; next }
    found && NF { sub(/[[:space:]]+$/, ""); print; exit }
  ' "$file")"
  case "$status" in
    Ideation | Proposed | Accepted | Implemented | Deprecated | Superseded | Rejected) ;;
    *)
      printf '%s\n' "${rel}: invalid first Status value: ${status:-<missing>}" >&2
      failed=1
      ;;
  esac

  status_tail="$(awk '/^## Status[[:space:]]*$/{found=1; next} found{print}' "$file")"
  extra="$(printf '%s\n' "$status_tail" | awk '
    !NF { next }
    !seen { seen = 1; next }
    /^(Ideation|Proposed|Accepted|Implemented|Deprecated|Superseded|Rejected)[[:space:]]*$/ { print; exit }
  ')"
  if [[ -n $extra ]]; then
    printf '%s\n' "${rel}: Status carries a second lifecycle value: ${extra}" >&2
    failed=1
  fi

  case "$status" in
    Implemented)
      if [[ $status_tail != *"]("* ]]; then
        printf '%s\n' "${rel}: Implemented status must link an enactment target" >&2
        failed=1
      fi
      ;;
    Superseded)
      if ! cog::fn::docs_lint::successor_link "$file" "$status_tail"; then
        printf '%s\n' "${rel}: Superseded status must link its successor ADR record" >&2
        failed=1
      fi
      ;;
    Deprecated)
      if [[ $(printf '%s' "$status_tail" | wc -w) -lt 4 ]]; then
        printf '%s\n' "${rel}: Deprecated status must explain why it stopped applying" >&2
        failed=1
      fi
      ;;
  esac

  return "$failed"
}

cog::fn::docs_lint::slice_headings() {
  local root="$1" file="$2"
  cog::fn::docs_lint::headings_equal "$root" "$file" "the slice contract" \
    "## Goal" "## Appetite" "## Core" "## In scope" "## Out of scope" \
    "## Governed by" "## Acceptance" "## Rabbit holes" "## Done when" "## Revisions"
}

cog::fn::docs_lint::trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s\n' "$value"
}

cog::fn::docs_lint::test_target_exists() {
  local root="$1" target="$2"
  target="${target#\`}"
  target="${target%\`}"
  target="$(cog::fn::docs_lint::trim "$target")"
  [[ -n $target ]] || return 1
  if [[ $target == test/* ]]; then
    [[ -f $root/$target ]]
  else
    # A bare test name, not a path: grep the suite. grep, not rg, so the check
    # carries no dependency beyond the devShell's declared tools.
    grep -RFq -- "$target" "$root/test"
  fi
}

cog::fn::docs_lint::acceptance_targets() {
  local root="$1" slice_file="$2" slice_id="$3" rel line target
  local failed=0
  rel="$(cog::fn::docs_lint::relative "$root" "$slice_file")"
  while IFS= read -r line; do
    [[ $line == *"->"* ]] || continue
    target="${line##*->}"
    target="$(cog::fn::docs_lint::trim "$target")"
    if ! cog::fn::docs_lint::test_target_exists "$root" "$target"; then
      printf '%s\n' "${rel}: slice ${slice_id} Acceptance target not found: ${target}" >&2
      failed=1
    fi
  done < <(awk '
    /^## Acceptance[[:space:]]*$/ { found = 1; next }
    found && /^## / { exit }
    found { print }
  ' "$slice_file")
  return "$failed"
}

cog::fn::docs_lint::milestones() {
  local root="$1" file="$2" rel line body head id slug status appetite note extra
  local section="" slice_file successor dir link_target
  local failed=0
  local slice_link_re='^\[([^]]+)\]\(([^)]+)\)$'
  local -A seen=() seen_dir=()
  # The fixed grammar is `<id> <slug> — <status> — <appetite>[ — <note>]`, so the
  # em-dash separator is the only field boundary. Swapping it for a byte that
  # cannot appear in prose lets one `read` split the line.
  local sep=$' \xe2\x80\x94 '
  rel="$(cog::fn::docs_lint::relative "$root" "$file")"
  while IFS= read -r line; do
    # Live work first, terminal statuses below: the section a line sits in is
    # part of its meaning, so it is tracked rather than skipped.
    case "$line" in
      '## in flight') section="in flight" && continue ;;
      '## closed') section="closed" && continue ;;
      '## '*)
        section=""
        continue
        ;;
    esac
    [[ $line == "- "* ]] || continue
    if [[ -z $section ]]; then
      printf '%s\n' "${rel}: milestone line outside a status section: ${line}" >&2
      failed=1
      continue
    fi
    body="${line#- }"
    IFS=$'\x01' read -r head status appetite note extra <<<"${body//"$sep"/$'\x01'}"
    if [[ $head != *" "* || -z $status || -z $appetite || -n $extra ]]; then
      printf '%s\n' "${rel}: milestone line does not match the fixed grammar: ${line}" >&2
      failed=1
      continue
    fi
    id="${head%% *}"
    slug="${head#* }"
    if [[ ! $id =~ ^[0-9]{3}$ ]] || ((10#$id == 0)); then
      printf '%s\n' "${rel}: milestone line has a non-canonical slice id: ${id}" >&2
      failed=1
      continue
    fi
    # One line per slice: ids are never reused, so a repeat is two status
    # surfaces, and a slice listed in both sections is the same fault.
    if [[ -n ${seen[$id]:-} ]]; then
      printf '%s\n' "${rel}: milestone id appears more than once: ${id}" >&2
      failed=1
      continue
    fi
    seen[$id]=1
    # The slice field may be a bare slug or a link to its entry document; the
    # shared contract's own example list uses bare slugs, so the link stays
    # optional. When it is a link, its destination is checked against the line's
    # own id and slug: a link that merely resolves is not enough, because a
    # destination naming a *different* existing slice satisfies the generic
    # relative-link rule while still sending the reader from the single status
    # surface to the wrong slice.
    if [[ $slug =~ $slice_link_re ]]; then
      slug="${BASH_REMATCH[1]}"
      link_target="${BASH_REMATCH[2]}"
      if [[ $link_target != "./slices/${id}-${slug}/README.md" ]]; then
        printf '%s\n' "${rel}: milestone slice ${id} links to ${link_target}, expected ./slices/${id}-${slug}/README.md" >&2
        failed=1
        continue
      fi
    fi
    seen_dir["${id}-${slug}"]=1
    status="$(cog::fn::docs_lint::trim "$status")"
    note="$(cog::fn::docs_lint::trim "$note")"
    case "$status" in
      shaped | active | done | cut | reshaped) ;;
      *)
        printf '%s\n' "${rel}: slice ${id} has invalid milestone status: ${status}" >&2
        failed=1
        continue
        ;;
    esac
    # `done`, `cut`, and `reshaped` need no further action, so they belong below
    # the split; anything still needing action belongs above it. A status flipped
    # in place without the move leaves the live section reading as work in hand.
    case "$status" in
      done | cut | reshaped) [[ $section == closed ]] || {
        printf '%s\n' "${rel}: terminal slice ${id} is listed under '## ${section}', expected '## closed'" >&2
        failed=1
      } ;;
      *) [[ $section == "in flight" ]] || {
        printf '%s\n' "${rel}: live slice ${id} is listed under '## ${section}', expected '## in flight'" >&2
        failed=1
      } ;;
    esac
    if [[ $status == reshaped ]]; then
      successor=""
      [[ $note =~ ([0-9]{3}) ]] && successor="${BASH_REMATCH[1]}"
      if [[ -z $successor ]] || ((10#$successor <= 10#$id)); then
        # Ids are never reused, so a re-shape always takes the next free id.
        printf '%s\n' "${rel}: reshaped slice ${id} note must name a later successor id" >&2
        failed=1
      elif ! compgen -G "$root/docs/plan/slices/${successor}-*/README.md" >/dev/null; then
        printf '%s\n' "${rel}: reshaped slice ${id} names a successor with no slice: ${successor}" >&2
        failed=1
      fi
    fi
    if [[ $status == cut && -z $note ]]; then
      printf '%s\n' "${rel}: cut slice ${id} note must name what was cut" >&2
      failed=1
    fi
    # The slice document is committed before the work starts, so it must exist at
    # every status. Only acceptance targets are forward references while shaped.
    slice_file="$root/docs/plan/slices/${id}-${slug}/README.md"
    if [[ ! -f $slice_file ]]; then
      printf '%s\n' "${rel}: milestone slice file not found: docs/plan/slices/${id}-${slug}/README.md" >&2
      failed=1
    elif [[ $status == active || $status == "done" || $status == cut ]]; then
      if ! cog::fn::docs_lint::acceptance_targets "$root" "$slice_file" "$id"; then
        failed=1
      fi
    fi
  done <"$file"

  # The milestone list is the single status surface, so a slice directory with no
  # line is a unit of work no reader can find.
  for dir in "$root"/docs/plan/slices/*/; do
    [[ -d $dir ]] || continue
    id="$(basename "$dir")"
    # The whole basename is compared, not just the id, so a second directory under a
    # reused id is still reported rather than absorbed by its sibling's line.
    [[ -n ${seen_dir[$id]:-} ]] && continue
    printf '%s\n' "${rel}: slice has no milestone line: docs/plan/slices/${id}" >&2
    failed=1
  done
  return "$failed"
}

cog::fn::docs_lint::run() {
  local root file rel
  local failures=0 files=0
  local -a paths=()
  root="$(cog::fn::docs_lint::root)"
  mapfile -d '' -t paths < <(cog::fn::docs_lint::files "$root")

  for file in "${paths[@]}"; do
    ((files += 1))
    if ! cog::fn::docs_lint::emphasis "$root" "$file"; then failures=$((failures + 1)); fi
    rel="$(cog::fn::docs_lint::relative "$root" "$file")"
    case "$rel" in
      docs/decisions/[0-9][0-9][0-9][0-9]-*.md)
        if ! cog::fn::docs_lint::adr "$root" "$file"; then failures=$((failures + 1)); fi
        ;;
      docs/decisions/template.md)
        # The seed for every new record: hold it to the heading contract so drift
        # surfaces at the template rather than in the record copied from it.
        if ! cog::fn::docs_lint::headings_equal "$root" "$file" "the ADR contract" \
          "## Context and Problem Statement" "## Considered Options" \
          "## Decision Outcome" "## Consequences" "## Status"; then failures=$((failures + 1)); fi
        ;;
      docs/plan/charter.md)
        if ! cog::fn::docs_lint::headings_equal "$root" "$file" "the charter contract" \
          "## What this is for" "## Pillars" "## No-gos" "## Appetite unit"; then failures=$((failures + 1)); fi
        ;;
      docs/plan/slices/*/README.md)
        if ! cog::fn::docs_lint::slice_headings "$root" "$file"; then failures=$((failures + 1)); fi
        ;;
      docs/plan/milestones.md)
        if ! cog::fn::docs_lint::milestones "$root" "$file"; then failures=$((failures + 1)); fi
        ;;
    esac
  done

  COG_DOCS_LINT_FILES="$files"
  COG_DOCS_LINT_FAILURES="$failures"
  export COG_DOCS_LINT_FILES COG_DOCS_LINT_FAILURES
  ((failures == 0))
}
