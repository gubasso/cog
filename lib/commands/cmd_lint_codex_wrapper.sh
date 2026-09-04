# shellcheck shell=bash
: 'desc: Enforce Codex single-entrypoint markdown snippets.'

__cog_lint_codex_wrapper_usage() {
  cog::fn::ui_data "Usage: cog lint-codex-wrapper [FILE ...]"
  cog::fn::ui_data ""
  cog::fn::ui_data "Scans bash/sh/shell markdown fences for command-position codex-session calls."
  cog::fn::ui_data "With no FILE args, scans skills-native/claude/*/SKILL.md from the cog repo root."
}

__cog_lint_codex_wrapper_repo_root() {
  if [[ -n ${LIB_DIR:-} ]]; then
    (cd "${LIB_DIR}/.." && pwd -P)
  else
    pwd -P
  fi
}

__cog_lint_codex_wrapper_scan_file() {
  local file="$1"
  local BARE_RE='(^|[;&|({])[[:space:]]*codex-session([[:space:]]|$)'
  local OPEN_RE='^[[:space:]]*```+[[:space:]]*(bash|sh|shell)([[:space:]]|$)'
  local CLOSE_RE='^[[:space:]]*```+[[:space:]]*$'
  local heredoc_open_re="<<-?[[:space:]]*[\"']?([A-Za-z_][A-Za-z0-9_]*)"

  awk \
    -v file="$file" \
    -v bare_re="$BARE_RE" \
    -v open_re="$OPEN_RE" \
    -v close_re="$CLOSE_RE" \
    -v heredoc_open_re="$heredoc_open_re" '
    function strip_quotes(s,    out, i, c, quote, esc) {
      out = ""
      quote = ""
      esc = 0
      for (i = 1; i <= length(s); i++) {
        c = substr(s, i, 1)
        if (quote == "") {
          if (c == "\047" || c == "\"") {
            quote = c
            out = out " "
          } else {
            out = out c
          }
        } else {
          out = out " "
          if (quote == "\"" && c == "\\" && esc == 0) {
            esc = 1
          } else if (c == quote && esc == 0) {
            quote = ""
          } else {
            esc = 0
          }
        }
      }
      return out
    }

    BEGIN {
      in_fence = 0
      heredoc = ""
      failed = 0
    }

    {
      line = $0

      if (!in_fence) {
        if (line ~ open_re) {
          in_fence = 1
        }
        next
      }

      if (line ~ close_re) {
        in_fence = 0
        heredoc = ""
        next
      }

      if (heredoc != "") {
        terminator = "^[[:space:]]*" heredoc "[[:space:]]*$"
        if (line ~ terminator) {
          heredoc = ""
        }
        next
      }

      if (line ~ /^[[:space:]]*#/) {
        next
      }

      stripped = strip_quotes(line)
      if (stripped ~ bare_re) {
        printf "%s:%d: codex-session must be invoked through cog codex-runner run-exec or run-resume\n", file, FNR > "/dev/stderr"
        failed = 1
      }

      if (match(line, heredoc_open_re)) {
        opener = substr(line, RSTART, RLENGTH)
        sub(/^<<-?[[:space:]]*["\047]?/, "", opener)
        sub(/["\047].*$/, "", opener)
        heredoc = opener
      }
    }

    END {
      exit failed
    }
  ' "$file"
}

cog::cmd::lint_codex_wrapper() {
  local repo_root file failed=0
  local -a files=()

  case "${1:-}" in
    -h | --help)
      __cog_lint_codex_wrapper_usage
      return 0
      ;;
  esac

  if (($# > 0)); then
    files=("$@")
    for file in "${files[@]}"; do
      [[ -r $file ]] || cog::fn::error_raise "InputUnreadable" \
        "lint-codex-wrapper input is not readable" "path: ${file}" "" "pass readable markdown files"
    done
  else
    repo_root="$(__cog_lint_codex_wrapper_repo_root)"
    while IFS= read -r file; do
      [[ -n $file ]] && files+=("$file")
    done < <(find "$repo_root/skills-native/claude" -mindepth 2 -maxdepth 2 -type f -name 'SKILL.md' -print 2>/dev/null | sort)
  fi

  for file in "${files[@]}"; do
    if ! __cog_lint_codex_wrapper_scan_file "$file"; then
      failed=1
    fi
  done

  if [[ $failed -ne 0 ]]; then
    exit 1
  fi
  return 0
}
