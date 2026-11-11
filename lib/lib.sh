# The checks of prose.sh. Vale checks the English with the Google developer
# documentation style, and textlint checks the Japanese. Each check adds its
# findings to $fails or $shows, by the level that the tool gives them, and a
# note for each file that it didn't check to $notes. Run setup.sh first, as
# prose.sh does.

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "$root/lib/paths.sh"
# The tools of mise.toml, and the Google style where Vale looks for it.
eval "$(mise -C "$root" env -s bash)"
VALE_STYLES_PATH="$(mise -C "$root" where http:vale-google)"
export VALE_STYLES_PATH
fails=""
shows=""
notes=()
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# Vale reads vale/.vale.ini as its user-level file, through
# XDG_CONFIG_HOME, and lays the settings of the repository over it. The
# copy names the StylesPath of this repository, as Vale reads a relative
# path from the directory of the file. A file with no settings of the
# repository gets an empty file.
mkdir -p "$work/vale-home/vale"
{
  echo "StylesPath = $root/vale/styles"
  grep -v '^StylesPath' "$root/vale/.vale.ini"
} >"$work/vale-home/vale/.vale.ini"
: >"$work/vale-empty.ini"

# Adds a note that tool $1 didn't check the files after $2, for reason $2,
# with all that the tool printed, in $work/out and $work/err. The checks
# can't tell where the cause is, so the note gives both fixes.
fail_run() {
  local tool="$1" reason="$2" files
  shift 2
  files="$(printf '%s, ' "$@")"
  notes+=("$tool didn't check ${files%, }: $reason. Fix: if the output names a file of the repository, correct it. Otherwise, run $root/setup.sh again, and if the check still fails, report it with this message in an issue of $issues."$'\n'"  stdout:"$'\n'"$(sed 's/^/    /' "$work/out")"$'\n'"  stderr:"$'\n'"$(sed 's/^/    /' "$work/err")")
}

# Succeeds where file $1 holds text for the tools. A file that isn't
# there, such as one that the commit deletes, and a file with a NUL byte,
# such as an image, hold none. The tools read UTF-8 alone, and read other
# bytes as text that the file doesn't hold, so another file fails.
is_text() {
  [ -f "$1" ] || return 1
  : >"$work/out"
  tr -d '\000' <"$1" 2>"$work/err" | cmp -s - "$1" 2>>"$work/err"
  case $? in
    0) ;;
    1) return 1 ;;
    *) fail_run "The checks" "they couldn't read it" "$1"; return 1 ;;
  esac
  iconv -f UTF-8 -t UTF-8 "$1" >/dev/null 2>&1 && return
  notes+=("The checks didn't check $1: it isn't text in UTF-8, the only encoding that they read. Fix: write it in UTF-8, or leave it out of the job, with exclude in lefthook.yml.")
  return 1
}

# Adds the findings of report $2 of tool $1, {files: [{file, findings:
# [{line, check, level, message}]}]}. A finding at the level warning or
# error goes to $fails, and one at a lower level, suggestion in Vale and
# info in textlint, to $shows. Fails where jq can't read the report.
add_findings() {
  local stops part
  for stops in true false; do
    part="$(jq -er --arg tool "$1" --argjson stops "$stops" '[.files[]
      | (.findings | map(select((.level == "warning" or .level == "error") == $stops))) as $found
      | select($found | length > 0)
      | "\($tool) on \(.file):\n" + ($found | map("- Line \(.line), \(.check) (\(.level)): \(.message | sub("\\s+$"; "") | gsub("\n"; "\n  "))") | join("\n"))]
      | join("\n\n")' <<<"$2" 2>"$work/err")" || return 1
    [ -n "$part" ] || continue
    if [ "$stops" = true ]; then fails+="$part"$'\n\n'; else shows+="$part"$'\n\n'; fi
  done
}

# Prints the settings of Vale for file $1: the nearest .vale.ini, _vale.ini
# or vale.ini from its directory up to the root of the repository, the
# current directory, or the empty file.
vale_config() {
  local dir="$PWD/$1" name
  while [[ "$dir" == "$PWD"/* ]]; do
    dir="${dir%/*}"
    for name in .vale.ini _vale.ini vale.ini; do
      [ ! -f "$dir/$name" ] || { echo "$dir/$name"; return; }
    done
  done
  echo "$work/vale-empty.ini"
}

# Runs Vale on each file given, one at a time, with its settings, by
# --config: without it, Vale would read VALE_CONFIG_PATH or the .vale.ini
# of the home directory in place of the settings of the repository. Vale
# runs in the directory of its settings, where it reads a relative path of
# them from, and reads each file in the format that its extension names.
check_english() {
  local file config status
  for file in "$@"; do
    is_text "$file" || continue
    config="$(vale_config "$file")"
    (path="$PWD/$file" && cd "${config%/*}" && XDG_CONFIG_HOME="$work/vale-home" vale --config="$config" --no-exit --output=JSON "$path") >"$work/out" 2>"$work/err"
    status=$?
    if [ "$status" -ne 0 ]; then
      fail_run Vale "Vale exited $status" "$file"
    elif ! add_findings Vale "$(jq --arg file "$file" '{files: [{file: $file, findings: [.[][] | {line: .Line, check: .Check, level: .Severity, message: .Message}]}]}' "$work/out" 2>"$work/err")"; then
      fail_run Vale "jq couldn't read its report" "$file"
    fi
  done
}

# Runs textlint once on all the files given, by textlint/check.mjs, which
# says how it checks each file and writes its report to
# $work/textlint.json. Each file of a format that textlint doesn't read
# fails, with the formats that it reads.
check_japanese() {
  local file texts=() status formats
  for file in "$@"; do is_text "$file" && texts+=("$file"); done
  [ "${#texts[@]}" -gt 0 ] || return 0
  node "$root/textlint/check.mjs" "$textlint_dir/node_modules" "$work" "${texts[@]}" >"$work/out" 2>"$work/err"
  status=$?
  if [ "$status" -ne 0 ]; then
    fail_run textlint "Node exited $status" "${texts[@]}"
  elif ! add_findings textlint "$(cat "$work/textlint.json")" || ! formats="$(jq -r '.notes | group_by(.reason)[]
    | "textlint didn'"'"'t check \(map(.file) | join(", ")): \(.[0].reason). Fix: leave each file out of the job japanese, with glob or exclude in lefthook.yml."' "$work/textlint.json" 2>"$work/err")"; then
    fail_run textlint "jq couldn't read its report" "${texts[@]}"
  elif [ -n "$formats" ]; then
    mapfile -t -O "${#notes[@]}" notes <<<"$formats"
  fi
}
