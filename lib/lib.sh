# The checks of prose.sh. Another script, such as a hook of Claude Code,
# can source this file and call its functions, such as `check_prose`. Vale
# checks the English with the Google developer
# documentation style, and lint.py of the skill natural-japanese checks the
# Japanese. Each check adds its findings to $report and the reasons that it
# couldn't run to $notes. Run setup.sh first, as prose.sh does.
#
# Issue #12 holds the table of what the checks read in each format. Vale
# reads each format that it knows, with vale/formats.ini laid under
# the .vale.ini of the repository. The checks read the rest themselves,
# and write what they read into a Markdown file at the same line numbers,
# which Vale and lint.py then read.

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "$root/lib/paths.sh"
# The tools of mise.toml, and the Google style where Vale looks for it.
eval "$(mise -C "$root" env -s bash)"
VALE_STYLES_PATH="$(mise -C "$root" where http:vale-google)"
export VALE_STYLES_PATH
report=""
notes=()
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# Prints the path of a new file in $work, with extension $1. Each one has
# a directory of its own, as macOS's mktemp takes no extension.
new_file() {
  echo "$(mktemp -d "$work/file.XXXXXX")/text$1"
}

# Prints the .vale.ini that applies in directory $1. A repository that has
# its own .vale.ini uses it, as Vale itself would. Elsewhere the
# .vale.ini of this repository applies.
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
  echo "$root/vale/.vale.ini"
}

# Prints the View by which Vale reads the data file at path $1, or nothing
# for a file that isn't data. Issue #12 holds the table of what each View
# reads.
view_of() {
  case "$1" in
    */.github/workflows/*.yml | */.github/workflows/*.yaml) echo Workflow ;;
    */action.yml | */action.yaml) echo Action ;;
    *.schema.json) echo Schema ;;
    */.claude-plugin/*.json | */hooks/hooks.json | */.claude/settings*.json | */package.json | */pyproject.toml | \
      */mise.toml | */.mise.toml | */mise/config.toml | */lefthook.yml | */.lefthook.yml | */config/views/*.yml)
      echo Description
      ;;
    *.json | *.yml | *.yaml | *.toml) echo Strings ;;
  esac
}

# Prints the directory to give Vale as XDG_CONFIG_HOME, so that it reads
# vale/formats.ini as its user-level file, with View $1, if there's one,
# for the files with extension $2. Vale takes a View only in a section of
# an extension. Vale reads the comments of a data file as plain text, so
# it leaves them out, and the checks read them as Markdown, after the View
# `Comments` finds them.
layer() {
  local dir="$work/layer-${1:-none}-$2"
  if [ ! -d "$dir" ]; then
    mkdir -p "$dir/vale"
    {
      echo "StylesPath = $root/vale/styles"
      if [ -n "$1" ] && [ "$1" != Comments ]; then
        sed 's/^IgnoredScopes = /IgnoredScopes = comment, /' "$root/vale/formats.ini"
      else
        cat "$root/vale/formats.ini"
      fi
      [ -n "$1" ] && printf '\n[*.%s]\nView = %s\n' "$2" "$1"
    } >"$dir/vale/.vale.ini"
  fi
  echo "$dir"
}

# Runs Vale with config $1 on file $2, read as the file at path $3, with
# the rest as more options of Vale. $view, when set, names the View in
# place of the one of the path. Vale reads a relative StylesPath from
# the directory of its .vale.ini, and gets a file by its path, so that the
# globs of the sections match it. A file that isn't at path $3, such as a
# chezmoi template, goes on stdin.
run_vale() {
  local config="$1" file="$2" path="$3" home
  shift 3
  home="$(layer "${view-$(view_of "$path")}" "${path##*.}")"
  if [ "$file" = "$path" ]; then
    (cd "$(dirname "$config")" && XDG_CONFIG_HOME="$home" vale --no-exit --output=JSON --config="$config" "$@" "$file" 2>&1)
  else
    (cd "$(dirname "$config")" && XDG_CONFIG_HOME="$home" vale --no-exit --output=JSON --config="$config" --path="$path" "$@" <"$file" 2>&1)
  fi
}

# Runs Vale with config $3 on file $1, read as the file at path $2. $4 is a
# JSON array of the line numbers to report, or null for all lines. $5 names
# the text in the report.
check_english() {
  local file="$1" path="$2" config="$3" lines="$4" label="$5" out found
  if ! command -v vale &>/dev/null; then
    notes+=("Vale isn't installed, so the check skipped the English. Fix: run $root/setup.sh.")
    return
  fi
  out="$(run_vale "$config" "$file" "$path")"
  if ! found="$(jq -r --argjson lines "$lines" '
    [.[] | .[] | select($lines == null or (.Line as $n | $lines | index($n)))] | .[] |
    "- Line \(.Line), \(.Check) (\(.Severity)): \(.Message)"' <<<"$out" 2>/dev/null)"; then
    # A Vale error is a JSON object whose Text says why.
    notes+=("Vale didn't check $label with $config: $(jq -r '.Text // empty' <<<"$out" 2>/dev/null || head -c 300 <<<"$out")")
    return
  fi
  if [ -n "$found" ]; then
    report+="Vale on $label, with $config:"$'\n'"$found"$'\n\n'
  fi
}

# Runs lint.py on Markdown file $1, when the lines $2 hold kana. $2 is a
# JSON array of the line numbers to report, or null for all lines. $3 names
# the text in the report.
check_japanese() {
  local file="$1" lines="$2" label="$3" lint out found japanese
  # lint.py reads only the lines that are mostly Japanese. An English line
  # with a Japanese name in it, such as ⌘英かな, stays out, as lint.py
  # would read it as Japanese and judge the English. The last line counts
  # too when no newline ends it.
  japanese="$(new_file .md)"
  jq -Rsr '
    def count(re): [scan(re)] | length;
    rtrimstr("\n") | split("\n")[] |
    if count("[\\p{Hiragana}\\p{Katakana}\\p{Han}]") > count("[A-Za-z]") then . else "" end' "$file" >"$japanese"
  if ! jq -Rse --argjson lines "$lines" '
    split("\n") as $all | (if $lines == null then $all else [$lines[] | $all[. - 1]] end) |
    join("\n") | test("[\\p{Hiragana}\\p{Katakana}]")' "$japanese" >/dev/null; then
    return
  fi
  file="$japanese"
  lint="$natural_japanese/skills/natural-japanese/scripts/lint.py"
  python="$venv/bin/python"
  if [ ! -f "$lint" ] || [ ! -x "$python" ]; then
    notes+=("The skill natural-japanese or its Python packages aren't installed, so the check skipped the Japanese. Fix: run $root/setup.sh.")
    return
  fi
  # The packages come from the virtual environment that setup.sh makes
  # with their sha256 checked. Python writes no bytecode, so that the
  # skill's directory stays as fetched.
  if ! out="$(PYTHONDONTWRITEBYTECODE=1 "$python" "$lint" --json --reading-load "$file" 2>&1)" ||
    ! found="$(jq -r --argjson lines "$lines" '
      [.findings[], (.reading_load.findings // [])[]] |
      map(select($lines == null or (.line as $n | $lines | index($n)))) | .[] |
      "- Line \(.line), \(.category) (\(.severity)): \(.detail) 「\(.excerpt)」" +
      (if .hint then " Hint: \(.hint)" else "" end)' <<<"$out" 2>/dev/null)"; then
    notes+=("lint.py didn't check $label: $(head -c 300 <<<"$out")")
    return
  fi
  if [ -n "$found" ]; then
    report+="lint.py of natural-japanese on $label:"$'\n'"$found"$'\n\n'
  fi
}

# Prints, as {line, text}, each line of the prose that Vale reads in file
# $1, read as the file at path $2, with the settings of the checks. The
# rule `Lovaizu.Text` finds each line, from its first word to its end. It
# fails when Vale can't read the file.
vale_text() {
  run_vale "$root/vale/text.ini" "$1" "$2" |
    jq -c '[.[] | .[] | {line: .Line, text: .Match}]' 2>/dev/null
}

# Writes the text in $2, a JSON array of {line, text}, into a Markdown file
# at the same line numbers as file $1, and prints its path. One line holds
# each text that starts on it.
at_lines() {
  local out
  out="$(new_file .md)"
  jq -r --argjson n "$(wc -l <"$1")" '
    (group_by(.line) | map({(.[0].line | tostring): (map(.text) | join(" "))}) | add // {}) as $at |
    range(1; $n + 2) | $at[tostring] // ""' <<<"$2" >"$out"
  echo "$out"
}

# Prints, as {line, text}, the comment lines of file $1: each line whose
# first character, past any space, is one of $2, such as `#;`.
comment_lines() {
  jq -Rsc --arg marks "$2" '[split("\n") | to_entries[] |
    (.value | capture("^\\s*[" + $marks + "]+\\s?(?<text>.*)$")) as $m | {line: (.key + 1), text: $m.text}]' "$1"
}

# Prints, as {line, text}, the comments of jq program $1: from a # that
# isn't in a string to the end of its line.
jq_comments() {
  jq -Rsc '[split("\n") | to_entries[] |
    (.value | gsub("\"(\\\\.|[^\"\\\\])*\""; "") | capture("#\\s?(?<text>.*)$")) as $m |
    {line: (.key + 1), text: $m.text}]' "$1"
}

# Prints, as {line, text}, the comment lines and the values of file $1, in
# the format of a `.ini` file.
# A value goes on after its key, past = or :, and on the indented lines
# that follow it. Section names and keys aren't prose.
ini_prose() {
  jq -Rsc '[split("\n") | to_entries[] | .key += 1 |
    if .value | test("^\\s*[;#]") then {line: .key, text: (.value | sub("^\\s*[;#]+\\s?"; ""))}
    elif .value | test("^\\s*\\[") then empty
    elif .value | test("^\\s+\\S") then {line: .key, text: (.value | sub("^\\s+"; ""))}
    elif .value | test("[=:]") then {line: .key, text: (.value | sub("^[^=:]*[=:]\\s*"; ""))}
    else empty end]' "$1"
}

# Prints, as {line, text}, the prose of shell script $1: its comments, and
# the words that echo and printf show. The first line #!, a directive of
# shellcheck, and echo or printf that writes to a file aren't prose. It
# fails when shfmt can't parse the script, with $2 as the name of the
# script, from which shfmt takes its dialect.
shell_prose() {
  local tree
  # shfmt can't parse a template's `{{ ... }}`, nor an expression
  # `${{ ... }}` of a workflow, so each one reads as x.
  tree="$(sed 's/{{[^}]*}}/x/g' "$1" | shfmt --to-json --filename "${2:-script.sh}" 2>/dev/null)" || return 1
  jq -c -f "$root/lib/shell-prose.jq" <<<"$tree"
}

# Prints, as {line, text}, the prose of the shell script that each step of
# a GitHub workflow or action, or each job of a lefthook config, at YAML
# file $1 runs: the run of a step whose shell is bash or sh, as GitHub
# runs it.
run_prose() {
  local file="$1" steps step script start all='[]'
  steps="$(yq -p yaml -o json -I0 '[.. | select(tag == "!!str") |
    select((path | .[-1]) == "run" and (path | .[-3]) == "steps" and ((parent | .shell // "bash") | test("^(ba)?sh"))) |
    {"line": line, "text": ., "block": (style == "literal" or style == "folded")}]' "$file" 2>/dev/null)" || return 1
  while IFS= read -r step; do
    script="$(new_file .sh)"
    jq -r .text <<<"$step" >"$script"
    # A block scalar starts on the line after its key.
    start="$(jq '.line + (if .block then 1 else 0 end)' <<<"$step")"
    all="$(jq -sc --argjson start "$start" '.[0] + (.[1] | map(.line += $start - 1))' \
      <<<"$all $(shell_prose "$script" || echo '[]')")"
  done < <(jq -c '.[]' <<<"$steps")
  echo "$all"
}

# Writes chezmoi template $1 with each action `{{ ... }}` as spaces into a
# new file, and prints its path. The text keeps its lines and columns.
template_text() {
  local out
  out="$(new_file "")"
  jq -Rrsj 'gsub("(?<a>\\{\\{[\\s\\S]*?\\}\\})"; .a | gsub("[^\n]"; " "))' "$1" >"$out"
  echo "$out"
}

# Prints, as {line, text}, the lines of each comment `{{/* ... */}}` of
# chezmoi template $1.
template_comments() {
  jq -Rsc '. as $all | [match("\\{\\{-?\\s*/\\*(?<c>[\\s\\S]*?)\\*/\\s*-?\\}\\}"; "g") |
    .captures[0] as $c | ($all[0:$c.offset] | [scan("\n")] | length) as $before |
    $c.string | split("\n") | to_entries[] |
    {line: ($before + .key + 1), text: (.value | sub("^\\s+"; "") | sub("\\s+$"; ""))} | select(.text != "")]' "$1"
}

# Prints the name by which the checks read a chezmoi template at path $1:
# its name without .tmpl and the prefixes of chezmoi's attributes, such as
# dot_ for a leading dot.
template_name() {
  local name="${1##*/}" before=""
  name="${name%.tmpl}"
  while [ "$name" != "$before" ]; do
    before="$name"
    name="$(sed -E 's/^(create|modify|remove|run|once|onchange|before|after|exact|private|readonly|empty|executable|symlink|encrypted|literal)_//' <<<"$name")"
  done
  case "$name" in dot_*) name=".${name#dot_}" ;; esac
  echo "$name"
}

# Prints how the checks read file $1 with name $2, as one of these words:
#
# - `md` for Markdown and plain text, which lint.py reads too.
# - `vale:` and an extension, such as `vale:py`, for another format that
#   Vale reads as that extension.
# - `html` for HTML and SVG.
# - `shell`, `jq` or `ini` for a format that the checks read themselves.
# - `vale-ini` for the settings of Vale.
# - `comments` for a file that holds only patterns and comment lines.
# - `none` for a file that holds no prose.
reader() {
  local file="$1" name="$2" first
  case "$name" in
    .chezmoiroot | .chezmoiversion) echo none ;;
    .vale.ini | _vale.ini | vale.ini) echo vale-ini ;;
    .gitignore | .chezmoiignore | .chezmoiremove | requirements*.txt | requirements*.in) echo comments ;;
    .coveragerc | *.ini | *.cfg) echo ini ;;
    *.jq) echo jq ;;
    .bashrc | .bash_profile | .bash_logout | .profile | .zshrc | .zprofile | .zshenv | .zlogin | *.sh | *.bash | *.zsh) echo shell ;;
    *.md | *.markdown | *.mdx | *.txt) echo md ;;
    *.html | *.htm | *.svg) echo html ;;
    *.json | *.yml | *.yaml | *.toml) echo "vale:${name##*.}" ;;
    *.c | *.h | *.cc | *.cpp | *.cs | *.css | *.go | *.java | *.js | *.jsx | *.mjs | *.cjs | *.kt | *.less | *.lua | *.php | *.py | *.rb | *.rs | *.sass | *.scss | *.swift | *.ts | *.tsx | *.mts | *.cts) echo "vale:${name##*.}" ;;
    *.*) echo vale:txt ;;
    *)
      # A file with no extension, such as an executable, reads as the
      # program that its first line names.
      first="$(head -n 1 "$file" 2>/dev/null)"
      case "$first" in
        '#!'*python*) echo vale:py ;;
        '#!'*node*) echo vale:js ;;
        '#!'*sh | '#!'*sh' '* | '#!'*' '*sh) echo shell ;;
        *) echo vale:txt ;;
      esac
      ;;
  esac
}

# Checks the prose of file $1 that Vale and lint.py can read, as issue #12
# says. $2 is a JSON array of the line numbers to report, or null for all
# lines. $3 is the .vale.ini to use.
check_prose() {
  local file="$1" lines="$2" config="$3" name="${1##*/}" text="$1" path="$1" kind prose='[]' more ext
  # A binary file, such as an image, holds no text.
  grep -Iq . "$file" || return
  # A chezmoi template reads as the file that it makes, with its actions
  # as spaces, and its comments `{{/* ... */}}` read as prose. chezmoi
  # reads a file named modify_* as a template when the file holds
  # chezmoi:modify-template.
  if [ "$name" != "${name%.tmpl}" ] || { [ "$name" != "${name#modify_}" ] && grep -q 'chezmoi:modify-template' "$file"; } ||
    case "$file" in */.chezmoitemplates/* | */.chezmoiignore | */.chezmoiremove) true ;; *) false ;; esac; then
    name="$(template_name "$file")"
    text="$(template_text "$file")"
    path="$(dirname "$file")/$name"
    prose="$(template_comments "$file")"
    # A template that's all actions, such as one that modifies a file,
    # holds nothing more.
    grep -q '[^[:space:]]' "$text" || name=""
  fi
  kind="$(reader "$text" "$name")"
  [ -n "$name" ] || kind=none
  more='[]'
  case "$kind" in
    md)
      check_english "$text" "$path" "$config" "$lines" "$file"
      check_japanese "$text" "$lines" "$file"
      ;;
    vale:*)
      ext="${kind#vale:}"
      # A file with no extension reads as the program that it runs.
      [ "${name##*.}" = "$ext" ] || path="$path.$ext"
      check_english "$text" "$path" "$config" "$lines" "$file"
      if ! more="$(vale_text "$text" "$path")"; then
        more='[]'
        notes+=("Vale couldn't read $file, so the check didn't check its Japanese.")
      fi
      # The comments of a data file, and the run of each step, go into the
      # Markdown file below.
      if [ -n "$(view_of "$path")" ]; then
        prose="$(jq -sc 'add' <<<"$prose $(view=Comments vale_text "$text" "$path" || echo '[]')")"
      fi
      case "$path" in
        */.github/workflows/*.yml | */.github/workflows/*.yaml | */action.yml | */action.yaml)
          prose="$(jq -sc 'add' <<<"$prose $(run_prose "$text" || echo '[]')")"
          ;;
      esac
      ;;
    html)
      # Vale reads the text of HTML with the settings of the checks, as the
      # TokenIgnores of a repository can match inside a tag, such as the
      # URL of xmlns, and break the markup. The text then reads as Markdown
      # with the settings of the repository.
      if ! more="$(vale_text "$text" "${path%.*}.html")"; then
        more='[]'
        notes+=("Vale couldn't read $file, so the check didn't check its text.")
      fi
      prose="$(jq -sc 'add' <<<"$prose $more")"
      more='[]'
      ;;
    shell)
      if ! more="$(shell_prose "$text" "$name")"; then
        more='[]'
        notes+=("shfmt couldn't parse $file, so the check didn't check its text. Fix: make it valid, or leave it out with exclude in lefthook.yml.")
      fi
      prose="$(jq -sc 'add' <<<"$prose $more")"
      more='[]'
      ;;
    ini) prose="$(jq -sc 'add' <<<"$prose $(ini_prose "$text")")" ;;
    vale-ini) prose="$(jq -sc 'add' <<<"$prose $(comment_lines "$text" '#;')")" ;;
    comments) prose="$(jq -sc 'add' <<<"$prose $(comment_lines "$text" '#')")" ;;
    jq) prose="$(jq -sc 'add' <<<"$prose $(jq_comments "$text")")" ;;
  esac
  # The Japanese of the text that Vale read, which lint.py reads only in a
  # Markdown file.
  if [ "$more" != "[]" ]; then
    check_japanese "$(at_lines "$file" "$more")" "$lines" "$file"
  fi
  if [ "$prose" != "[]" ]; then
    text="$(at_lines "$file" "$prose")"
    check_english "$text" "$text" "$config" "$lines" "$file"
    check_japanese "$text" "$lines" "$file"
  fi
}
