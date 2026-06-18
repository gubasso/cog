# shellcheck shell=bash
: 'desc: Lint SKILL.md files against the skill/script boundary.'

__cog_skill_lint_usage() {
  cog::fn::ui_data "Usage: cog skill-lint [SKILL.md ...]"
}

__cog_skill_lint_repo_root() {
  if [[ -n ${LIB_DIR:-} ]]; then
    (cd "${LIB_DIR}/.." && pwd -P)
  else
    pwd -P
  fi
}

__cog_skill_lint_add_default_files() {
  local root="$1" path
  while IFS= read -r path; do
    [[ -n $path ]] && printf '%s\n' "$path"
  done < <(find "$root/skills/claude" "$root/skills/codex" "$root/.claude/skills" -mindepth 2 -maxdepth 2 -type f -name 'SKILL.md' -print 2>/dev/null | sort)
}

__cog_skill_lint_finding() {
  local file="$1" line="$2" rule="$3" message="$4" fix="$5"
  printf '%s:%s: %s: %s; fix: %s\n' "$file" "$line" "$rule" "$message" "$fix" >&2
}

__cog_skill_lint_has_unknown_keys() {
  local file="$1" runtime="$2" unknown key failed=0
  unknown="$(cog::fn::skill::unknown_frontmatter_keys_json "$file" "$runtime")"
  while IFS= read -r key; do
    [[ -n $key ]] || continue
    __cog_skill_lint_finding "$file" 1 "frontmatter" "unknown key '${key}'" "remove it or add it to the runtime allowlist"
    failed=1
  done < <(jq -r '.[]' <<<"$unknown")
  return "$failed"
}

__cog_skill_lint_check_structure() {
  local file="$1" runtime parent name line_count emojis fences line failed=0

  runtime="$(cog::fn::skill::runtime_for_path "$file")"
  if [[ -z $runtime ]]; then
    __cog_skill_lint_finding "$file" 1 "path" "could not determine skill runtime" "place SKILL.md under skills/claude, skills/codex, or .claude/skills"
    failed=1
  fi

  if ! cog::fn::skill::has_frontmatter "$file"; then
    __cog_skill_lint_finding "$file" 1 "frontmatter" "missing or incomplete YAML frontmatter delimiters" "start SKILL.md with --- and close the frontmatter with ---"
    failed=1
  fi

  name="$(cog::fn::skill::frontmatter_name "$file")"
  if [[ -z $name ]]; then
    __cog_skill_lint_finding "$file" 1 "frontmatter" "missing name" "add a name key matching the parent directory"
    failed=1
  elif ! cog::fn::skill::name_is_valid "$name"; then
    __cog_skill_lint_finding "$file" 1 "name" "invalid skill name '${name}'" "use ^[a-z0-9-]{1,64}$ and avoid reserved names anthropic and claude"
    failed=1
  else
    parent="$(cog::fn::skill::parent_dir_name "$file")"
    if [[ $name != "$parent" ]]; then
      __cog_skill_lint_finding "$file" 1 "name" "name '${name}' does not match parent directory '${parent}'" "rename the directory or update frontmatter name"
      failed=1
    fi
  fi

  if [[ -n $runtime ]] && ! __cog_skill_lint_has_unknown_keys "$file" "$runtime"; then
    failed=1
  fi

  line_count="$(cog::fn::skill::line_count "$file")"
  if [[ $line_count -gt 500 ]]; then
    __cog_skill_lint_finding "$file" "$line_count" "line-count" "SKILL.md exceeds 500 lines" "split references or shorten the skill body"
    failed=1
  fi

  emojis="$(cog::fn::skill::emoji_lines_json "$file")"
  while IFS= read -r line; do
    [[ -n $line ]] || continue
    __cog_skill_lint_finding "$file" "$line" "emoji" "emoji character present" "remove emoji characters from skill instructions"
    failed=1
  done < <(jq -r '.[]' <<<"$emojis")

  fences="$(cog::fn::skill::untagged_fence_lines_json "$file")"
  while IFS= read -r line; do
    [[ -n $line ]] || continue
    __cog_skill_lint_finding "$file" "$line" "fence" "code fence has no language tag" "add a language tag such as bash, markdown, yaml, or text"
    failed=1
  done < <(jq -r '.[]' <<<"$fences")

  if [[ $runtime == claude ]] && ! cog::fn::skill::has_trigger_tests "$file"; then
    __cog_skill_lint_finding "$file" 1 "trigger-tests" "missing trigger-tests comment" "add an HTML trigger-tests comment near the frontmatter"
    failed=1
  fi

  return "$failed"
}

__cog_skill_lint_is_cog_extraction() {
  local line="$1"
  [[ $line =~ ^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*=\"\$\(cog[[:space:]].*\|[[:space:]]*(sed[[:space:]]+-n|cut[[:space:]]|jq[[:space:]]+-r) ]]
}

__cog_skill_lint_is_simple_assignment() {
  local line="$1"
  [[ $line =~ ^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*=\"?\$\{?[A-Za-z_][A-Za-z0-9_]*(:-[^}]*)?\}?\"?[[:space:]]*$ ]]
}

__cog_skill_lint_scan_premise_file() {
  local file="$1"
  local line line_no=0 in_shell=false fence_start=0 pending_allow=false block_allow=false failed=0
  local pending_while_line=0 pending_while_body="" i
  local -a deferred_while_lines=() deferred_while_bodies=()
  local open_re='^[[:space:]]*```+[[:space:]]*(bash|sh|shell)([[:space:]]|$)'
  local any_open_re='^[[:space:]]*```+'
  local close_re='^[[:space:]]*```+[[:space:]]*$'
  local allow_re='^[[:space:]]*<!--[[:space:]]*cog-skill-lint:[[:space:]]*allow-inline-shell[[:space:]][^[:space:]][^>]*-->[[:space:]]*$'

  # shellcheck disable=SC2094
  while IFS= read -r line || [[ -n $line ]]; do
    line_no=$((line_no + 1))

    if [[ $in_shell == false ]]; then
      if [[ $line =~ $allow_re ]]; then
        pending_allow=true
        continue
      fi
      if [[ $line =~ $open_re ]]; then
        in_shell=true
        fence_start="$line_no"
        block_allow="$pending_allow"
        pending_allow=false
        pending_while_line=0
        pending_while_body=""
        deferred_while_lines=()
        deferred_while_bodies=()
        continue
      fi
      if [[ $line =~ $any_open_re ]]; then
        pending_allow=false
      fi
      continue
    fi

    if [[ $line =~ $close_re ]]; then
      in_shell=false
      # Flush any still-open deferred `while ... read -r` loop, then resolve each
      # deferred loop against ITS OWN body (not the whole block): a loop whose body
      # never appends to an array (`arr+=(...)`) is not an argv builder and is flagged.
      if [[ $pending_while_line -ne 0 ]]; then
        deferred_while_lines+=("$pending_while_line")
        deferred_while_bodies+=("$pending_while_body")
        pending_while_line=0
        pending_while_body=""
      fi
      for i in "${!deferred_while_lines[@]}"; do
        if [[ ${deferred_while_bodies[i]} != *"+=("* ]]; then
          __cog_skill_lint_finding "$file" "${deferred_while_lines[i]}" "premise" "while loop in shell fence" "extract deterministic iteration into a cog subcommand"
          failed=1
        fi
      done
      deferred_while_lines=()
      deferred_while_bodies=()
      continue
    fi

    # Accumulate the body of the currently deferred while loop, so its argv-builder
    # exemption is judged on its own lines rather than the entire block. The body is
    # bounded at the loop's own `done`: a trailing array append AFTER the loop ends
    # must not absolve a real-work loop.
    if [[ $pending_while_line -ne 0 ]]; then
      pending_while_body+="${line}"$'\n'
      if [[ $line =~ ^[[:space:]]*done([[:space:]]|\<|$) ]]; then
        deferred_while_lines+=("$pending_while_line")
        deferred_while_bodies+=("$pending_while_body")
        pending_while_line=0
        pending_while_body=""
      fi
    fi
    [[ $block_allow == true ]] && continue
    [[ -z ${line//[[:space:]]/} || $line =~ ^[[:space:]]*# ]] && continue

    if [[ $line =~ ^[[:space:]]*[A-Za-z_][A-Za-z0-9_:-]*[[:space:]]*\(\)[[:space:]]*\{ ]]; then
      __cog_skill_lint_finding "$file" "$line_no" "premise" "shell function definition in skill body" "extract deterministic shell into a cog subcommand"
      failed=1
      continue
    fi

    if [[ $line =~ ^[[:space:]]*for[[:space:]] ]]; then
      __cog_skill_lint_finding "$file" "$line_no" "premise" "for loop in shell fence" "extract deterministic iteration into a cog subcommand"
      failed=1
      continue
    fi

    if [[ $line =~ ^[[:space:]]*while[[:space:]] ]]; then
      # Defer judgment on `while ... read -r` argv-array builders: the `arr+=(...)`
      # body usually appears on a later line, so the exclusion is resolved at fence
      # close against THIS loop's own body (see close_re handler). Other while loops
      # flag now. Starting a new loop flushes the previous deferred loop.
      if [[ $pending_while_line -ne 0 ]]; then
        deferred_while_lines+=("$pending_while_line")
        deferred_while_bodies+=("$pending_while_body")
        pending_while_line=0
        pending_while_body=""
      fi
      if [[ $line =~ ^[[:space:]]*while[[:space:]]+IFS=.*read[[:space:]]+-r ]]; then
        pending_while_line="$line_no"
        # Seed with the header line so a single-line `while ...; do arr+=(...); done`
        # idiom is recognized as an argv builder.
        pending_while_body="${line}"$'\n'
        continue
      fi
      __cog_skill_lint_finding "$file" "$line_no" "premise" "while loop in shell fence" "extract deterministic iteration into a cog subcommand"
      failed=1
      continue
    fi

    if [[ $line =~ ^[[:space:]]*case[[:space:]] ]]; then
      if [[ $line =~ ^[[:space:]]*case[[:space:]]+\"?\$[A-Za-z_][A-Za-z0-9_]*\"?[[:space:]]+in ]]; then
        continue
      fi
      __cog_skill_lint_finding "$file" "$line_no" "premise" "case dispatch in shell fence" "extract deterministic dispatch into a cog subcommand"
      failed=1
      continue
    fi

    if [[ $line =~ (grep[[:space:]]+-[^|;&]*P|grep[[:space:]]+-[^|;&]*nP|awk[[:space:]]|sed[[:space:]]) ]]; then
      if __cog_skill_lint_is_cog_extraction "$line"; then
        continue
      fi
      if [[ $line =~ ^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*= || $line =~ ^[[:space:]]*\|[[:space:]]*(awk|sed|grep) ]]; then
        continue
      fi
      __cog_skill_lint_finding "$file" "$line_no" "premise" "text-processing command in shell fence" "extract deterministic parsing into a cog subcommand"
      failed=1
      continue
    fi

    if __cog_skill_lint_is_simple_assignment "$line"; then
      continue
    fi
  done <"$file"

  if [[ $in_shell == true && $block_allow != true ]]; then
    __cog_skill_lint_finding "$file" "$fence_start" "fence" "unterminated shell fence" "close the fenced code block"
    failed=1
  fi

  return "$failed"
}

__cog_skill_lint_scan_file() {
  local file="$1" failed=0
  [[ -r $file && -f $file ]] || cog::fn::error_raise "InputUnreadable" "skill-lint input is not readable" "path: ${file}" "" "pass readable SKILL.md files"
  if ! __cog_skill_lint_check_structure "$file"; then
    failed=1
  fi
  if ! __cog_skill_lint_scan_premise_file "$file"; then
    failed=1
  fi
  return "$failed"
}

cog::cmd::skill_lint() {
  local repo_root file failed=0
  local -a files=()

  case "${1:-}" in
    -h | --help)
      __cog_skill_lint_usage
      return 0
      ;;
  esac

  if (($# > 0)); then
    files=("$@")
  else
    repo_root="$(__cog_skill_lint_repo_root)"
    while IFS= read -r file; do
      files+=("$file")
    done < <(__cog_skill_lint_add_default_files "$repo_root")
  fi

  for file in "${files[@]}"; do
    if ! __cog_skill_lint_scan_file "$file"; then
      failed=1
    fi
  done

  if [[ $failed -ne 0 ]]; then
    exit 1
  fi
  return 0
}
