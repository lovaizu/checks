# The checks of prose.sh. Vale checks the English with the Google developer
# documentation style, and textlint checks the Japanese. The repository
# chooses which files each one checks. Each tool reads the file as it reads
# its format, and the checks change nothing in it. Each check adds its
# findings to $fails or $shows, by the level that the tool gives them, and
# the reasons that it couldn't run to $notes. Each tool finds the settings
# of the repository as it does itself: from the current directory up. Run
# setup.sh first, as prose.sh does.

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
# Adds each finding of JSON array $2, of {line, check, level, message},
# to $fails or $shows, under the heading $1. A finding at the level
# warning or error fails. A lower level, suggestion in Vale and info in
# textlint, shows.
add_findings() {
  local heading="$1" found stops
  for stops in true false; do
    found="$(jq -r --argjson stops "$stops" '.[] | select((.level == "warning" or .level == "error") == $stops)
      | "- Line \(.line), \(.check) (\(.level)): \(.message | sub("\\s+$"; "") | gsub("\n"; "\n  "))"' <<<"$2")"
    [ -n "$found" ] || continue
    if [ "$stops" = true ]; then
      fails+="$heading"$'\n'"$found"$'\n\n'
    else
      shows+="$heading"$'\n'"$found"$'\n\n'
    fi
  done
}

# The .vale.ini of the repository that Vale finds, if any, for the heading
# of its findings.
vale_source=""
vale_ready=""

# Runs Vale on each file given, with the .vale.ini of the repository over
# the defaults. Vale reads a file in the format that its extension names.
check_english() {
  local file out found
  if [ -z "$vale_ready" ]; then
    if ! out="$(XDG_CONFIG_HOME="$work/vale-home" vale ls-config 2>"$work/vale.err")" ||
      ! vale_source="$(jq -r '.RootINI' <<<"$out" 2>/dev/null)"; then
      notes+=("Vale didn't check the English: $(vale_reason)")
      vale_ready=failed
      return
    fi
    vale_ready=1
  fi
  [ "$vale_ready" = 1 ] || return
  for file in "$@"; do
    # With --no-exit, Vale exits 0 with its findings, and fails only when it
    # can't check the file. It then prints {} to stdout, and its error to
    # stderr.
    if ! out="$(XDG_CONFIG_HOME="$work/vale-home" vale --no-exit --output=JSON "$file" 2>"$work/vale.err")" ||
      ! found="$(jq -c '[.[] | .[] | {line: .Line, check: .Check, level: .Severity, message: .Message}]' <<<"$out" 2>/dev/null)" ||
      [ -z "$found" ]; then
      notes+=("Vale didn't check $file: $(vale_reason)")
      continue
    fi
    add_findings "Vale on $file${vale_source:+, with $vale_source}:" "$found"
  done
}

# Prints why Vale failed: the Text of the JSON object of its error, or the
# start of its error output.
vale_reason() {
  jq -r '.Text // empty' "$work/vale.err" 2>/dev/null || head -c 300 "$work/vale.err"
}

# The settings of textlint: the defaults with the settings of the
# repository laid over them.
textlint_config="$work/textlintrc.json"
textlint_levels="$work/textlint-levels.json"
textlint_source=""

# Runs textlint once on all the files given, as its settings stay the same
# for the run, and adds the findings of each file under a heading of its
# own. textlint reads Markdown and plain text, and no other format.
check_japanese() {
  local out found file status
  if [ ! -x "$textlint_dir/node_modules/.bin/textlint" ]; then
    notes+=("textlint isn't installed, so the check skipped the Japanese. Fix: run $root/setup.sh.")
    return
  fi
  if ! textlint_source="$(node "$root/textlint/config.mjs" "$textlint_dir/node_modules" "$PWD" "$textlint_config" "$textlint_levels" 2>"$work/textlint.err")"; then
    notes+=("textlint didn't check the Japanese: $(head -c 300 "$work/textlint.err")")
    return
  fi
  # textlint exits 1 with a finding that it counts as an error, and 2 when
  # it can't check the files.
  out="$("$textlint_dir/node_modules/.bin/textlint" --format json --config "$textlint_config" \
    --rules-base-directory "$textlint_dir/node_modules" "$@" 2>"$work/textlint.err")"
  status=$?
  # textlint gives each finding a level by number: 1 warning, 2 error and
  # 3 info. The level that the settings name for a rule comes first, as
  # config.mjs says.
  if [ "$status" -gt 1 ] || ! found="$(jq -c --slurpfile levels "$textlint_levels" 'map({key: .filePath, value: [.messages[] | {line, check: .ruleId,
    level: ($levels[0][.ruleId] // {"1": "warning", "2": "error", "3": "info"}[.severity | tostring] // "error"), message}]}) | from_entries' <<<"$out" 2>/dev/null)" || [ -z "$found" ]; then
    # textlint says why on stderr, or on stdout for some errors, such as a
    # setting with no rule.
    [ -s "$work/textlint.err" ] || printf '%s' "$out" >"$work/textlint.err"
    notes+=("textlint didn't check $*: $(head -c 300 "$work/textlint.err")")
    return
  fi
  # A file that textlint reports by another path would lose its findings.
  while IFS= read -r file; do
    notes+=("textlint reported $file, which it wasn't given by that path, so its findings were lost.")
  done < <(jq -r --args 'keys - $ARGS.positional | .[]' "$@" <<<"$found")
  for file in "$@"; do
    add_findings "textlint on $file${textlint_source:+, with $textlint_source}:" "$(jq -c --arg file "$file" '.[$file] // []' <<<"$found")"
  done
}
