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
# The jq that turns a report of a tool, {source, files: [{file, findings:
# [{line, check, level, message}]}], notes: [{file, kind, reason, detail}]},
# into shell that adds to $fails, $shows and $notes. A finding at the level
# warning or error fails. A lower level, suggestion in Vale and info in
# textlint, shows. A note that holds no file is about the whole run. Each
# fix lives here, by the kind of the note: a format that the tool doesn't
# read, a file that the checks can't read, settings that the tool can't
# load, and a cause that the checks don't know, where they don't guess a
# fix. The reason keeps its first line, and the
# detail, such as what the tool printed, comes in full. Notes with the same
# kind and reason become one. $tool and $job name the tool and the job.
report_jq='
  def line: if type == "array" then map(line) | map(select(. != "")) | join(": ")
    else tostring | split("\n") | map(select(test("\\S"))) | (.[0] // "") | sub("[.\\s]+$"; "") end;
  def fix: {
    format: "leave each file out of the job \($job), with glob or exclude in lefthook.yml",
    read: "make each file readable, or leave it out of the job \($job), with glob or exclude in lefthook.yml",
    settings: "correct the settings of the repository that the reason names",
    unknown: "run setup.sh of lovaizu/checks again, and if the check still fails, report it in an issue of lovaizu/checks with this message"
  }[.];
  def detail: (. // {}) | to_entries | map(select(.value != null and (.value | test("\\S"))))
    | map("\n  \(.key):\n    \(.value | sub("\\s+$"; "") | gsub("\n"; "\n    "))") | join("");
  def part(stops): [.source as $source | .files[]
    | (.findings | map(select((.level == "warning" or .level == "error") == stops))) as $found
    | select($found | length > 0)
    | "\($tool) on \(.file)\(if ($source // "") == "" then "" else ", with \($source)" end):\n"
      + ($found | map("- Line \(.line), \(.check) (\(.level)): \(.message | sub("\\s+$"; "") | gsub("\n"; "\n  "))") | join("\n"))
      + "\n\n"] | join("");
  def emit: "fails+=\(part(true) | @sh)", "shows+=\(part(false) | @sh)",
    (.notes | map(.reason |= line) | group_by([.kind, .reason])[]
      | "notes+=(\(("\($tool) didn'"'"'t check \(map(.file // empty) | if length == 0 then "the files of the job \($job)" else join(", ") end): \(.[0].reason). Fix: \(.[0].kind | fix).\(.[0].detail | detail)") | @sh))");
'

# Adds report $3 of tool $1 for job $2 by report_jq.
add_report() {
  eval "$(jq -r --arg tool "$1" --arg job "$2" "$report_jq emit" <<<"$3")"
}

# Adds a note of kind $3 that tool $1 of job $2 couldn't run, with reason
# $4, and what the tool printed to stdout, $5, and to stderr, in file $6.
add_failure() {
  add_report "$1" "$2" "$(jq -n --arg kind "$3" --arg reason "$4" --arg stdout "$5" --rawfile stderr "$6" \
    '{files: [], notes: [{kind: $kind, reason: $reason, detail: {stderr: $stderr, stdout: $stdout}}]}')"
}

# Runs Vale with the defaults of the checks as its user-level settings.
vale_run() {
  XDG_CONFIG_HOME="$work/vale-home" vale "$@"
}

# Runs Vale once on all the files given, with the .vale.ini of the
# repository over the defaults, and reads its findings as JSON. Vale goes on
# past a file that it can't read, but its JSON error doesn't name the file.
# So when the run fails, Vale runs once more with the output line, whose
# errors name each file, such as "[notes.rst]:E100:rst2html not found".
# Vale reads a file in the format that its extension names.
check_english() {
  local source out status
  out="$(vale_run ls-config 2>"$work/vale.err")"
  status=$?
  if [ "$status" -ne 0 ] || ! source="$(jq -r '.RootINI' <<<"$out" 2>/dev/null)"; then
    # Vale says why it can't load its settings in the Text of a JSON error.
    if out="$(jq -r '.Text // empty' "$work/vale.err" 2>/dev/null)" && [ -n "$out" ]; then
      add_failure Vale english settings "$out" "" /dev/null
    else
      add_failure Vale english unknown "Vale exited $status" "$out" "$work/vale.err"
    fi
    return
  fi
  vale_run --no-exit --output=JSON "$@" >"$work/vale.json" 2>"$work/vale.err"
  status=$?
  : >"$work/vale-line.err"
  # An error of the settings names the file, such as a .vale.ini, in its
  # Path, and an error of a file that Vale can't read has none.
  if [ "$status" -ne 0 ] && ! jq -e '.Path != ""' "$work/vale.err" >/dev/null 2>&1; then
    vale_run --no-exit --output=line "$@" >/dev/null 2>"$work/vale-line.err"
  fi
  # A file that Vale names in an error, it didn't check. A file that it
  # needs a program to read is of a format that it can't read here.
  add_report Vale english "$(jq -n --arg source "$source" --argjson status "$status" \
    --rawfile json "$work/vale.json" --rawfile errors "$work/vale-line.err" --rawfile stderr "$work/vale.err" '
    ($json | try fromjson catch {}) as $vale
    | ($stderr | try fromjson catch {}) as $error
    | if ($error.Path // "") != "" then {notes: [{kind: "settings", reason: "\($error.Text) (\($error.Path), line \($error.Line))"}], files: []} else
    [$errors | split("\n")[] | capture("^\\[(?<file>.+)\\]:E[0-9]+:(?<reason>.*)$")] as $failed
    | ($failed | map(.file)) as $names
    | {source: $source,
      files: [$ARGS.positional[] | select(IN($names[]) | not)
        | {file: ., findings: [($vale[.] // [])[] | {line: .Line, check: .Check, level: .Severity, message: .Message}]}],
      notes: ([$failed[] | {file, reason, kind: (if .reason | test("needed to read") then "format" else "unknown" end)}]
        + if $status != 0 and ($failed | length) == 0 then [{kind: "unknown", reason: "Vale exited \($status)", detail: {stderr: $stderr}}] else [] end
        + [$vale | keys[] | select(IN($ARGS.positional[]) | not) | {kind: "unknown", reason: "Vale reported \(.), which it wasn'"'"'t given by that path"}])} end' \
    --args "$@")"
}

# Runs textlint once on all the files given, by textlint/check.mjs, which
# says how it checks each file. A failure before check.mjs writes its
# report is one of Node or of the checks.
check_japanese() {
  local out status report="$work/textlint.json"
  if [ ! -x "$textlint_dir/node_modules/.bin/textlint" ]; then
    add_failure textlint japanese unknown "textlint isn't installed in $textlint_dir" "" /dev/null
    return
  fi
  out="$(node "$root/textlint/check.mjs" "$textlint_dir/node_modules" "$PWD" "$work" "$@" 2>"$work/textlint.err")"
  status=$?
  if [ "$status" -ne 0 ] || ! jq -e '.files' "$report" >/dev/null 2>&1; then
    add_failure textlint japanese unknown "Node exited $status before check.mjs wrote its report" "$out" "$work/textlint.err"
    return
  fi
  add_report textlint japanese "$(cat "$report")"
}
