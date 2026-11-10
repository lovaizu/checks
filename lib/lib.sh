# The checks of prose.sh. Another script, such as a hook of Claude Code,
# can source this file and call `check_prose`. Vale checks the English with
# the Google developer documentation style, and textlint checks the
# Japanese. Each tool reads the file as it reads its format, and the checks
# change nothing in it. Each check adds its findings to $fails or $shows,
# by the level that the tool gives them, and the reasons that it couldn't
# run to $notes. Run setup.sh first, as prose.sh does.

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
# The file that Vale reads as the .vale.ini of a repository that has none.
: >"$work/none.ini"

# Prints the .vale.ini of the repository that applies in directory $1, as
# Vale itself would find it, or an empty file where there's none.
vale_config() {
  local dir name
  dir="$(cd "$1" && pwd)"
  while :; do
    for name in .vale.ini _vale.ini; do
      if [ -f "$dir/$name" ]; then
        echo "$dir/$name"
        return
      fi
    done
    [ "$dir" = / ] && break
    dir="$(dirname "$dir")"
  done
  echo "$work/none.ini"
}

# Adds each finding of JSON array $2, of {line, check, level, message},
# to $fails or $shows, under the heading $1. A finding at the level
# warning or error fails. A lower level, suggestion in Vale and info in
# textlint, shows.
add_findings() {
  local heading="$1" found
  found="$(jq -r 'map(select(.level == "warning" or .level == "error")) | .[] | "- Line \(.line), \(.check) (\(.level)): \(.message | sub("\\s+$"; "") | gsub("\n"; "\n  "))"' <<<"$2")"
  [ -n "$found" ] && fails+="$heading"$'\n'"$found"$'\n\n'
  found="$(jq -r 'map(select(.level != "warning" and .level != "error")) | .[] | "- Line \(.line), \(.check) (\(.level)): \(.message | sub("\\s+$"; "") | gsub("\n"; "\n  "))"' <<<"$2")"
  [ -n "$found" ] && shows+="$heading"$'\n'"$found"$'\n\n'
}

# Runs Vale on file $1, with the .vale.ini of the repository over the
# defaults. Vale reads a file in the format that its extension names.
check_english() {
  local file="$1" config out found
  config="$(vale_config "$(dirname "$file")")"
  out="$(cd "$(dirname "$config")" && XDG_CONFIG_HOME="$work/vale-home" vale --no-exit --output=JSON --config="$config" "$file" 2>&1)"
  if ! found="$(jq -c '[.[] | .[] | {line: .Line, check: .Check, level: .Severity, message: .Message}]' <<<"$out" 2>/dev/null)"; then
    # A Vale error is a JSON object whose Text says why.
    notes+=("Vale didn't check $file: $(jq -r '.Text // empty' <<<"$out" 2>/dev/null || head -c 300 <<<"$out")")
    return
  fi
  [ "$config" = "$work/none.ini" ] && config=""
  add_findings "Vale on $file${config:+, with $config}:" "$found"
}

# The settings of textlint: the defaults with the settings of the
# repository, in the current directory, laid over them.
textlint_config="$work/textlintrc.json"
textlint_levels="$work/textlint-levels.json"
textlint_source=""
textlint_ready=""

# Runs textlint on file $1, when it holds Japanese: hiragana or katakana.
# textlint reads Markdown and plain text, and no other format.
check_japanese() {
  local file="$1" out found
  jq -Rse 'test("[\\p{Hiragana}\\p{Katakana}]")' "$file" >/dev/null || return
  if [ ! -x "$textlint_dir/node_modules/.bin/textlint" ]; then
    notes+=("textlint isn't installed, so the check skipped the Japanese. Fix: run $root/setup.sh.")
    return
  fi
  if [ -z "$textlint_ready" ]; then
    if ! textlint_source="$(node "$root/textlint/config.mjs" "$textlint_dir/node_modules" "$PWD" "$textlint_config" "$textlint_levels" 2>&1)"; then
      notes+=("textlint didn't check the Japanese: $textlint_source")
      textlint_ready=failed
      return
    fi
    textlint_ready=1
  fi
  [ "$textlint_ready" = 1 ] || return
  out="$("$textlint_dir/node_modules/.bin/textlint" --format json --config "$textlint_config" \
    --rules-base-directory "$textlint_dir/node_modules" "$file" 2>&1)"
  # textlint gives each finding a level by number: 1 warning, 2 error and
  # 3 info. The level that the settings name for a rule comes first, as
  # config.mjs says.
  if ! found="$(jq -c --slurpfile levels "$textlint_levels" '[.[] | .messages[] | {line, check: .ruleId,
    level: ($levels[0][.ruleId] // {"1": "warning", "2": "error", "3": "info"}[.severity | tostring] // "error"), message}]' <<<"$out" 2>/dev/null)"; then
    notes+=("textlint didn't check $file: $(head -c 300 <<<"$out")")
    return
  fi
  add_findings "textlint on $file${textlint_source:+, with $textlint_source}:" "$found"
}

# Checks the prose of file $1.
check_prose() {
  # A binary file, such as an image, holds no text.
  grep -Iq . "$1" || return
  check_english "$1"
  check_japanese "$1"
}
