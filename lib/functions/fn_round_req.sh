# shellcheck shell=bash

cog::fn::round_req::abs_path() {
  local path="$1"
  [[ -e $path ]] || cog::fn::error_raise "InputNotFound" \
    "round requirement path not found" "path: $path" "" "pass an existing file or directory"
  if [[ -d $path ]]; then
    cd -P "$path" && pwd
  else
    printf '%s/%s\n' "$(cd -P "$(dirname "$path")" && pwd)" "$(basename "$path")"
  fi
}

cog::fn::round_req::is_round_file() {
  local path="$1" base
  [[ -f $path && $path == *.md ]] || return 1
  base="$(basename "$path")"
  case "$base" in
    README.md | STRATEGY.md | queue-plans.md | queue-rounds.md | queue-plans.yaml | queue-rounds.yaml)
      return 1
      ;;
  esac
  grep -qE '^##[[:space:]]+Acceptance Criteria' "$path"
}

cog::fn::round_req::plan_dir_for() {
  local path="$1"
  if [[ -d $path ]]; then
    cog::fn::round_req::abs_path "$path"
  else
    cd -P "$(dirname "$path")" && pwd
  fi
}

cog::fn::round_req::round_files_for() {
  local path="$1" abs
  abs="$(cog::fn::round_req::abs_path "$path")"
  if [[ -d $abs ]]; then
    find "$abs" -maxdepth 1 -type f -name '*.md' -print | while IFS= read -r file; do
      cog::fn::round_req::is_round_file "$file" && printf '%s\n' "$file"
    done | sort
  else
    cog::fn::round_req::is_round_file "$abs" || cog::fn::error_raise "InvalidInput" \
      "path is not a round markdown file" "path: $abs" "" \
      "pass a round file or a plan directory containing round files"
    printf '%s\n' "$abs"
  fi
}

cog::fn::round_req::criteria_json_for_file() {
  local path="$1" abs
  abs="$(cog::fn::round_req::abs_path "$path")"
  perl -MJSON::PP -0777 -ne '
    sub norm {
      my ($s)=@_;
      $s =~ s/`//g;
      $s =~ s/\s+/ /g;
      $s =~ s/^\s+|\s+$//g;
      return $s;
    }
    sub boiler {
      my ($s)=@_;
      my $n = norm($s);
      return 1 if $n =~ /^This plan.s queue-rounds\.yaml shows round .+ as done\.(?: \{\{If this is the final .*)?$/;
      return 1 if $n eq "The top-level .implementation-plans/queue-plans.yaml shows this plan as done.";
      return 0;
    }
    my @criteria;
    my @invalid;
    my %seen;
    my @duplicates;
    my $in = 0;
    for my $line (split /\n/, $_) {
      if ($line =~ /^##\s+Acceptance Criteria\s*$/) { $in=1; next; }
      if ($in && $line =~ /^##\s+/) { $in=0; }
      next unless $in;
      next unless $line =~ /^- \[[ xX]\]\s+(.*)$/;
      my $rest = $1;
      my ($id, $text);
      if ($rest =~ /^\((R[0-9]+)\)\s+(.+)$/) {
        ($id, $text) = ($1, $2);
      } elsif ($rest =~ /^\([^)]*\)\s+(.+)$/) {
        push @invalid, {line=>$line, reason=>"malformed-id"};
        next;
      } else {
        ($id, $text) = (undef, $rest);
      }
      next if boiler($text);
      if (defined $id) {
        if ($seen{$id}++) { push @duplicates, $id unless grep { $_ eq $id } @duplicates; }
      }
      push @criteria, {id=>$id, text=>norm($text), raw_text=>$text};
    }
    my $stamped = @criteria ? JSON::PP::true : JSON::PP::false;
    for my $c (@criteria) { if (!defined $c->{id}) { $stamped = JSON::PP::false; last; } }
    print encode_json({schema=>"cog.round-req.list.v1", ok=>(@invalid || @duplicates ? JSON::PP::false : JSON::PP::true), path=>$ARGV, stamped=>$stamped, criteria=>\@criteria, invalid=>\@invalid, duplicates=>\@duplicates});
  ' "$abs"
}

cog::fn::round_req::list_json() {
  cog::fn::round_req::criteria_json_for_file "$1"
}

cog::fn::round_req::max_id_in_plan_dir() {
  local dir="$1"
  local max
  max="$(grep -RhoE '\(R[0-9]+\)' "$dir" --include='*.md' 2>/dev/null \
    | tr -d '()R' | sort -n | tail -1 | awk '{print $1+0}' || true)"
  printf '%s\n' "${max:-0}"
}

cog::fn::round_req::stamp_json() {
  local target="$1" dry_run="${2:-false}" plan_dir max_before target_abs
  local -a files=()
  plan_dir="$(cog::fn::round_req::plan_dir_for "$target")"
  max_before="$(cog::fn::round_req::max_id_in_plan_dir "$plan_dir")"
  mapfile -t files < <(cog::fn::round_req::round_files_for "$target")
  target_abs="$(cog::fn::round_req::abs_path "$target")"
  COG_ROUND_REQ_TARGET="$target_abs" COG_ROUND_REQ_MAX_BEFORE="$max_before" COG_ROUND_REQ_DRY_RUN="$dry_run" \
    perl -MJSON::PP - "${files[@]}" <<'PERL'
      my @files = @ARGV;
      my $next = $ENV{COG_ROUND_REQ_MAX_BEFORE} + 0;
      my (@assigned, @invalid);
      my $preexisting = 0;
      my $wrote = JSON::PP::false;
      sub norm { my ($s)=@_; $s =~ s/`//g; $s =~ s/\s+/ /g; $s =~ s/^\s+|\s+$//g; return $s; }
      sub boiler {
        my ($s)=@_;
        my $n = norm($s);
        return 1 if $n =~ /^This plan.s queue-rounds\.yaml shows round .+ as done\.(?: \{\{If this is the final .*)?$/;
        return 1 if $n eq "The top-level .implementation-plans/queue-plans.yaml shows this plan as done.";
        return 0;
      }
      my @pending;
      # Phase 1: scan every target, collect malformed IDs and stage rewrites in memory; write nothing yet.
      for my $file (@files) {
        open my $fh, "<", $file or die "read $file: $!";
        my @lines = <$fh>;
        close $fh;
        my ($in, $changed) = (0, 0);
        for my $i (0..$#lines) {
          my $line = $lines[$i];
          if ($line =~ /^##\s+Acceptance Criteria\s*$/) { $in=1; next; }
          if ($in && $line =~ /^##\s+/) { $in=0; }
          next unless $in;
          next unless $line =~ /^- \[[ xX]\]\s+(.*)$/;
          my $rest = $1;
          if ($rest =~ /^\((R[0-9]+)\)\s+(.+)$/) { $preexisting++ unless boiler($2); next; }
          if ($rest =~ /^\([^)]*\)\s+(.+)$/) { push @invalid, {path=>$file, line=>norm($line), reason=>"malformed-id"}; next; }
          next if boiler($rest);
          my $id = "R" . (++$next);
          push @assigned, {path=>$file, id=>$id, text=>norm($rest)};
          $lines[$i] =~ s/^(- \[[ xX]\]\s+)/$1($id) /;
          $changed = 1;
        }
        push @pending, {path=>$file, lines=>[@lines], changed=>$changed};
      }
      # Phase 2: fail closed atomically — write only when no target had a malformed ID.
      if (!@invalid && $ENV{COG_ROUND_REQ_DRY_RUN} ne "true") {
        for my $p (@pending) {
          next unless $p->{changed};
          open my $out, ">", $p->{path} or die "write $p->{path}: $!";
          print $out @{$p->{lines}};
          close $out;
          $wrote = JSON::PP::true;
        }
      }
      my $ok = @invalid ? JSON::PP::false : JSON::PP::true;
      print encode_json({
        schema=>"cog.round-req.stamp.v1", ok=>$ok, path=>$ENV{COG_ROUND_REQ_TARGET},
        plan_max_before=>($ENV{COG_ROUND_REQ_MAX_BEFORE}+0), assigned=>\@assigned,
        preexisting=>$preexisting, wrote=>$wrote, invalid=>\@invalid
      });
PERL
}
