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
# The fix of each kind of failure, the one place that names them. The
# checks know the cause only where the tool names a file of the repository:
# a staged file of a format that the tool doesn't read, or a settings file
# of the repository. Any other failure has a cause that they don't know,
# and its note gives all that the tool printed.
fix_format='leave each file out of the job JOB, with glob or exclude in lefthook.yml'
fix_settings='correct the settings of the repository that the reason names'
fix_unknown="delete $textlint_dir, run $root/setup.sh, and run the check again. If the check still fails, report it in an issue of lovaizu/checks with this message"

# The jq that turns a report of a tool, {source, files: [{file, findings:
# [{line, check, level, message}]}], notes: [{file, kind, reason, detail}]},
# into shell that adds to $fails, $shows and $notes. kind is format,
# settings or unknown. A finding at the level warning or error fails. A
# lower level, suggestion in Vale and info in textlint, shows. A note with
# no file is about the whole run. The reason keeps its first line, and the
# detail, such as what the tool printed, comes in full. Notes with the same
# kind and reason become one.
report_jq='
  def line: tostring | split("\n") | map(select(test("\\S"))) | (.[0] // "") | sub("[.\\s]+$"; "");
  def detail: (. // {}) | to_entries | map(select((.value // "") | test("\\S")))
    | map("\n  \(.key):\n    \(.value | sub("\\s+$"; "") | gsub("\n"; "\n    "))") | join("");
  def part(stops): [.source as $source | .files[]
    | (.findings | map(select((.level == "warning" or .level == "error") == stops))) as $found
    | select($found | length > 0)
    | "\($tool) on \(.file)\(if ($source // "") == "" then "" else ", with \($source)" end):\n"
      + ($found | map("- Line \(.line), \(.check) (\(.level)): \(.message // "" | sub("\\s+$"; "") | gsub("\n"; "\n  "))") | join("\n"))
      + "\n\n"] | join("");
  "fails+=\(part(true) | @sh)", "shows+=\(part(false) | @sh)",
  (.notes | map(.reason |= line) | group_by([.kind, .reason])[]
    | "notes+=(\(("\($tool) didn'"'"'t check \(map(.file // empty) | if length == 0 then "the files of the job \($job)" else join(", ") end): \(.[0].reason). Fix: \({format: $format, settings: $settings, unknown: $unknown}[.[0].kind] | sub("JOB"; $job)).\(.[0].detail | detail)") | @sh))")
'

# Adds report $3 of tool $1 for job $2 by report_jq. A report that jq can't
# read fails, as it would otherwise pass with no finding.
add_report() {
  local shell
  if ! shell="$(jq -r --arg tool "$1" --arg job "$2" --arg format "$fix_format" --arg settings "$fix_settings" \
    --arg unknown "$fix_unknown" "$report_jq" <<<"$3" 2>"$work/jq.err")"; then
    notes+=("$1 didn't check the files of the job $2: jq couldn't read its report: $(cat "$work/jq.err"). Fix: $fix_unknown."$'\n'"  report:"$'\n'"$3")
    return
  fi
  eval "$shell"
}

# Runs Vale with the defaults of the checks as its user-level settings.
vale_run() {
  XDG_CONFIG_HOME="$work/vale-home" vale "$@"
}

# The jq that turns an error of Vale, in its JSON, into a note. Vale names
# the settings file that fails in Path. The cause is the settings only where
# that file is of the repository, not of the checks in $root or $work.
vale_error_jq='
  def vale_error($stdout; $stderr): ($stderr | try fromjson catch {}) as $error | ($error.Path // "") as $path
    | if $path != "" and (($path | startswith($root + "/")) or ($path | startswith($work + "/")) | not)
      then {kind: "settings", reason: "\($error.Text) (\($path), line \($error.Line))"}
      else {kind: "unknown", reason: "Vale failed", detail: {stdout: $stdout, stderr: $stderr}} end;'

# Runs Vale once on all the files given, with the .vale.ini of the
# repository over the defaults, and reads its findings as JSON, even where
# the run fails. Vale goes on past a file that it can't read, but its JSON
# error doesn't name the file. So when the run fails, Vale runs once more
# with the output line on the files that its report doesn't name, and
# those errors name each file, such as "[notes.rst]:E100:rst2html not
# found". Vale reads a file in the format that its extension names.
check_english() {
  local out status source left=()
  out="$(vale_run ls-config 2>"$work/vale.err")"
  status=$?
  if [ "$status" -ne 0 ] || ! source="$(jq -er '.RootINI // ""' <<<"$out" 2>/dev/null)"; then
    add_report Vale english "$(jq -n --arg root "$root" --arg work "$work" --arg stdout "$out" --rawfile stderr "$work/vale.err" \
      "$vale_error_jq {files: [], notes: [vale_error(\$stdout; \$stderr)]}")"
    return
  fi
  vale_run --no-exit --output=JSON "$@" >"$work/vale.json" 2>"$work/vale.err"
  status=$?
  : >"$work/vale-line.err"
  if [ "$status" -ne 0 ]; then
    mapfile -t left < <(jq -rRs --args '(try fromjson catch {}) as $vale | $ARGS.positional[] | select(. as $f | $vale | has($f) | not)' "$@" <"$work/vale.json")
    [ "${#left[@]}" -eq 0 ] || vale_run --no-exit --output=line "${left[@]}" >/dev/null 2>"$work/vale-line.err"
  fi
  # A file that Vale names in an error, it didn't check. One that Vale
  # needs a program to read is of a format that it can't read here.
  add_report Vale english "$(jq -n --arg root "$root" --arg work "$work" --arg source "$source" --argjson status "$status" \
    --rawfile json "$work/vale.json" --rawfile errors "$work/vale-line.err" --rawfile stderr "$work/vale.err" "$vale_error_jq"'
    ($json | try fromjson catch {}) as $vale
    | [$errors | split("\n")[] | capture("^\\[(?<file>.+)\\]:E[0-9]+:(?<reason>.*)$")] as $failed
    | {source: $source,
      files: [$ARGS.positional[] | select(IN($failed[].file) | not)
        | {file: ., findings: [($vale[.] // [])[] | {line: .Line, check: .Check, level: .Severity, message: .Message}]}],
      notes: ([$failed[] | if .reason | test("needed to read") then {file, reason, kind: "format"}
          else {file, reason, kind: "unknown", detail: {stderr: $errors}} end]
        + if $status != 0 and ($failed | length) == 0 then [vale_error($json; $stderr)] else [] end
        + [$vale | keys[] | select(IN($ARGS.positional[]) | not) | {kind: "unknown", reason: "Vale reported \(.), which it wasn'"'"'t given by that path"}])}' \
    --args "$@")"
}

# Runs textlint once on all the files given, by textlint/check.mjs, which
# says how it checks each file. The report that check.mjs writes counts
# even where Node then fails, and a failure of Node, with no report or
# after one, adds a note of an unknown cause.
check_japanese() {
  local out status
  : >"$work/textlint.json"
  out="$(node "$root/textlint/check.mjs" "$textlint_dir/node_modules" "$PWD" "$work" "$@" 2>"$work/textlint.err")"
  status=$?
  add_report textlint japanese "$(jq -n --argjson status "$status" --arg stdout "$out" \
    --rawfile report "$work/textlint.json" --rawfile stderr "$work/textlint.err" '
    ($report | try fromjson catch null) as $written
    | ($written // {source: "", files: [], notes: []})
    | if $written == null or $status != 0
      then .notes += [{kind: "unknown", reason: "Node exited \($status)\(if $written == null then " before check.mjs wrote its report" else "" end)", detail: {stdout: $stdout, stderr: $stderr}}]
      else . end')"
}
