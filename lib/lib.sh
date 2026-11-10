# The checks of prose.sh. Vale checks the English with the Google developer
# documentation style, and textlint checks the Japanese. The repository
# chooses which files each one checks, and each tool reads them and finds
# its settings as "What it checks" and "Change a setting" in README.md say.
# Each check adds its findings to $fails or $shows, by the level that the
# tool gives them, and the reasons that it couldn't check a file to $notes.
# Run setup.sh first, as prose.sh does.

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
# XDG_CONFIG_HOME, and lays the .vale.ini of the repository over it. The
# copy names the StylesPath of this repository, as Vale reads a relative
# path from the directory of the file.
mkdir -p "$work/vale-home/vale"
{
  echo "StylesPath = $root/vale/styles"
  grep -v '^StylesPath' "$root/vale/.vale.ini"
} >"$work/vale-home/vale/.vale.ini"
# Adds the report of JSON $2 from tool $1, {source, files: [{file,
# findings: [{line, check, level, message}]}], notes}, to $fails, $shows and
# $notes, with one jq for all the files. A finding at the level warning or
# error fails. A lower level, suggestion in Vale and info in textlint,
# shows.
add_report() {
  eval "$(jq -r --arg tool "$1" '
    def part(stops): [.source as $source | .files[]
      | (.findings | map(select((.level == "warning" or .level == "error") == stops))) as $found
      | select($found | length > 0)
      | "\($tool) on \(.file)\(if $source == "" then "" else ", with \($source)" end):\n"
        + ($found | map("- Line \(.line), \(.check) (\(.level)): \(.message | sub("\\s+$"; "") | gsub("\n"; "\n  "))") | join("\n"))
        + "\n\n"] | join("");
    "fails+=\(part(true) | @sh)", "shows+=\(part(false) | @sh)", (.notes[] | "notes+=(\(@sh))")' <<<"$2")"
}

# Prints the reason of a tool that failed with status $1, stdout $2 and
# stderr in file $3: the Text of a JSON error of Vale, or else all that the
# tool printed, as a warning on stderr can come with the reason on stdout,
# or else its status.
tool_reason() {
  local text
  text="$(jq -r '.Text? // empty' "$3" 2>/dev/null)"
  [ -n "$text" ] || text="$(printf '%s\n' "$(head -c 600 <<<"$2")" "$(head -c 600 "$3")" | sed '/^$/d')"
  # A fix follows the reason, after a period.
  text="${text%.}"
  echo "${text:-it exited $1 with no message}"
}

# Runs Vale with the defaults of the checks as its user-level settings.
vale_run() {
  XDG_CONFIG_HOME="$work/vale-home" vale "$@"
}

# Runs Vale once on all the files given, with the .vale.ini of the
# repository over the defaults. When the run fails, Vale runs again on each
# file that its report doesn't name, so that each file that fails gets the
# reason. Vale reads a file in the format that its extension names.
check_english() {
  local source out status file all checked=()
  out="$(vale_run ls-config 2>"$work/vale.err")"
  status=$?
  if [ "$status" -ne 0 ] || ! source="$(jq -r '.RootINI' <<<"$out" 2>/dev/null)"; then
    notes+=("Vale didn't check the English: $(tool_reason "$status" "$out" "$work/vale.err"). Fix: correct the settings of Vale of the repository, such as its .vale.ini.")
    return
  fi
  # With --no-exit, Vale exits 0 with its findings, and fails only when it
  # can't check a file. It then prints the findings of the files that it
  # could check to stdout, and its error to stderr. Its report names only
  # the files with findings, each by the path that it got.
  all="$(vale_run --no-exit --output=JSON "$@" 2>"$work/vale.err")"
  status=$?
  if [ "$status" -eq 0 ]; then
    checked=("$@")
  else
    # When Vale can't check even a line of Markdown, the settings fail, not
    # the files.
    if ! vale_run --no-exit --output=JSON --ext=.md <<<"A sentence." >/dev/null 2>&1; then
      notes+=("Vale didn't check the English: $(tool_reason "$status" "$all" "$work/vale.err"). Fix: correct the settings of Vale of the repository, such as its .vale.ini.")
      return
    fi
    for file in "$@"; do
      if jq -e --arg file "$file" 'has($file)' <<<"$all" >/dev/null 2>&1; then
        checked+=("$file")
        continue
      fi
      out="$(vale_run --no-exit --output=JSON "$file" 2>"$work/vale.err")"
      status=$?
      if [ "$status" -eq 0 ]; then
        all+="$out"
        checked+=("$file")
      else
        notes+=("Vale didn't check $file: $(tool_reason "$status" "$out" "$work/vale.err"). Fix: leave the file out of the job english, with glob or exclude in lefthook.yml.")
      fi
    done
  fi
  if ! out="$(jq -cs --arg source "$source" '(add // {}) as $vale | {source: $source,
    files: [$ARGS.positional[] | {file: ., findings: [($vale[.] // [])[] | {line: .Line, check: .Check, level: .Severity, message: .Message}]}],
    notes: [$vale | keys[] | select(IN($ARGS.positional[]) | not) | "Vale reported \(.), which it wasn'"'"'t given by that path."]}' \
    --args ${checked[@]+"${checked[@]}"} <<<"$all" 2>"$work/vale.err")"; then
    notes+=("Vale didn't check the English: its report isn't JSON: $(head -c 300 <<<"$all"). Fix: run the check again, and if it fails again, open an issue in lovaizu/checks with this message.")
    return
  fi
  add_report Vale "$out"
}

# Runs textlint once on all the files given, by textlint/check.mjs, which
# says how it checks each file.
check_japanese() {
  local out status report="$work/textlint.json"
  if [ ! -x "$textlint_dir/node_modules/.bin/textlint" ]; then
    notes+=("textlint isn't installed, so the check skipped the Japanese. Fix: run $root/setup.sh.")
    return
  fi
  out="$(node "$root/textlint/check.mjs" "$textlint_dir/node_modules" "$PWD" "$work" "$@" 2>&1)"
  status=$?
  if ! jq -e '.files' "$report" >/dev/null 2>&1; then
    notes+=("textlint didn't check the Japanese: $(jq -r '.error // empty' "$report" 2>/dev/null || tool_reason "$status" "$out" /dev/null)")
    return
  fi
  add_report textlint "$(cat "$report")"
}
