# The checks of prose.sh. Another script, such as a hook of Claude Code,
# can source this file and call check_prose, check_english or
# check_japanese. Vale checks the English with the Google developer
# documentation style, and lint.py of the skill natural-japanese checks the
# Japanese. Each check adds its findings to $report and the reasons that it
# couldn't run to $notes. Run setup.sh first, as prose.sh does.

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "$root/lib/paths.sh"
# The tools of mise.toml, and the Google style where Vale looks for it.
eval "$(mise -C "$root" env -s bash)"
VALE_STYLES_PATH="$(mise -C "$root" where http:vale-google)"
export VALE_STYLES_PATH
report=""
notes=()
work="$(mktemp -d)"
made=0
trap 'rm -rf "$work"' EXIT

# Prints the extension by which Vale reads a file, or nothing for JSON. A
# chezmoi template is read by the extension before .tmpl. Vale reads the
# formats that have # comments, such as shell and YAML, as Python, and it
# reads only their comments, so other_prose reads their messages or string
# values. Vale doesn't read JSON, which has no comments: other_prose reads
# its string values. Vale reads an SVG file as HTML, so that it reads only
# the text that the figure shows, at its line, and none of the markup or
# style. Vale reads any other text file as plain text, all of it. That
# holds for reStructuredText, AsciiDoc and XML too, as they need programs
# that aren't installed (rst2html, asciidoctor, xsltproc).
vale_ext() {
  local name="${1##*/}"
  name="${name%.tmpl}"
  if [ "$name" = "${name%.*}" ] || [ "${name%.*}" = "" ]; then
    # A file with no extension, such as an executable, is read by the
    # program that its first line names.
    if head -n 1 "$1" 2>/dev/null | grep -qE '^#!.*[/ ](ba|z)?sh'; then echo py; else echo txt; fi
    return
  fi
  case "${name##*.}" in
    md | markdown | mdx | txt | html | htm) echo "${name##*.}" ;;
    svg) echo html ;;
    c | h | clj | cljs | cljc | cs | cpp | cc | cxx | hpp | css | ex | exs | go | hs | java | js | jsx | mjs | cjs | jl | kt | kts | less | lua | pl | pm | php | ps1 | proto | py | qml | r | R | rb | rs | sass | scss | scala | swift | ts | tsx | mts | cts) echo "${name##*.}" ;;
    sh | bash | zsh | yml | yaml | toml | jq) echo py ;;
    json) ;;
    *) echo txt ;;
  esac
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

# Runs Vale with config $3 on file $1, read as extension $2. $4 is a JSON
# array of the line numbers to report, or null for all lines. $5 names the
# text in the report.
check_english() {
  local file="$1" ext="$2" config="$3" lines="$4" label="$5" out found
  if ! command -v vale &>/dev/null; then
    notes+=("Vale isn't installed, so the check skipped the English. Fix: run $root/setup.sh.")
    return
  fi
  # Vale reads a relative StylesPath from the directory of its .vale.ini.
  # Vale gets a file by its path, so that the globs of a repository's
  # .vale.ini match it. Vale gets a template on stdin with its extension.
  if [ "$file" = "${file%.tmpl}" ] && [ "${file##*.}" = "$ext" ]; then
    out="$(cd "$(dirname "$config")" && vale --no-exit --output=JSON --config="$config" "$file" 2>&1)"
  else
    out="$(cd "$(dirname "$config")" && vale --no-exit --output=JSON --config="$config" --ext=".$ext" <"$file" 2>&1)"
  fi
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

# Runs lint.py on Markdown file $1, when the lines $2 (a JSON array, or
# null for all lines) hold kana. $3 names the text in the report, and $4 is
# the file that the line numbers are in, when it is not $1.
check_japanese() {
  local file="$1" lines="$2" label="$3" lint out found japanese
  # lint.py reads only the lines that are mostly Japanese. An English line
  # with a Japanese name in it, such as ⌘英かな, stays out, as lint.py
  # would read it as Japanese and judge the English. The last line counts
  # too when no newline ends it.
  made=$((made + 1))
  japanese="$work/mostly-japanese-$made.md"
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
  # with their sha256 checked. No bytecode is written, so that the skill's
  # directory stays as fetched.
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
# $1 as extension $2, such as the comments of code. Vale applies the
# TokenIgnores of a .vale.ini, and reads a span in backticks as code, only
# in markup, so the checks read these lines as Markdown. It fails when Vale
# can't read the file.
vale_text() {
  local config="$root/vale/text.ini"
  (cd "$(dirname "$config")" && vale --no-exit --output=JSON --config="$config" --ext=".$2" <"$1" 2>/dev/null) |
    jq -c '[.[] | .[] | {line: .Line, text: .Match}]' 2>/dev/null
}

# Prints, as {line, text}, the messages of shell script $1.
shell_messages() {
  # shfmt can't parse a template's `{{ ... }}`, nor an expression
  # `${{ ... }}` of a workflow, so each one reads as x.
  sed 's/{{[^}]*}}/x/g' "$1" | shfmt --to-json 2>/dev/null | jq -c -f "$root/lib/shell-messages.jq" || echo '[]'
}

# Writes the text in $2, a JSON array of {line, text}, into a Markdown file
# at the same line numbers as file $1, and prints its path. One line holds
# each text that starts on it.
at_lines() {
  local out
  made=$((made + 1))
  out="$work/text-$made.md"
  jq -r --argjson n "$(wc -l <"$1")" '
    (group_by(.line) | map({(.[0].line | tostring): (map(.text) | join(" "))}) | add // {}) as $at |
    range(1; $n + 2) | $at[tostring] // ""' <<<"$2" >"$out"
  echo "$out"
}

# Prints, as {line, text}, the prose of file $1 that Vale doesn't read: the
# messages of a shell script, the string values of a .json, .yml, .yaml or
# .toml file, and the comments of a chezmoi template. It fails when it
# can't read the file's format.
other_prose() {
  local file="$1" name="${1##*/}" format strings step script start scripts='[]'
  name="${name%.tmpl}"
  case "$name" in
    *.sh | *.bash | *.zsh) ;;
    *.json | *.yml | *.yaml | *.toml)
      format="${name##*.}"
      [ "$format" = yml ] && format=yaml
      # yq gives the line of a YAML string. Elsewhere the check looks for
      # the string as JSON writes it, as a .toml file does a basic string, or
      # else for its first line as the file holds it. A line break in the
      # text becomes a space, so that the text stays on its one line.
      # The run of a step, in a workflow or an action of GitHub, is a shell
      # script unless the step names another shell. Its prose is that of a
      # shell script: its comments and its messages.
      strings="$(yq -p "$format" -o json -I0 '[.. | select(tag == "!!str") | {
        "line": line, "text": ., "block": (style == "literal" or style == "folded"),
        "script": ((path | .[-1]) == "run" and (path | .[-3]) == "steps" and ((parent | .shell // "bash") | test("^(ba)?sh")))}]' "$file" 2>/dev/null)" || return
      while IFS= read -r step; do
        script="$(mktemp "$work/script.XXXXXX")"
        jq -r .text <<<"$step" >"$script"
        # A block scalar starts on the line after its key.
        start="$(jq '.line + (if .block then 1 else 0 end)' <<<"$step")"
        scripts="$(jq -sc --argjson start "$start" '.[0] + (.[1] + .[2] | map(.line += $start - 1))' \
          <<<"$scripts $(vale_text "$script" py || echo '[]') $(shell_messages "$script")")"
      done < <(jq -c '.[] | select(.script)' <<<"$strings")
      jq -s --rawfile raw "$file" --argjson scripts "$scripts" '
        ($raw | indices("\n")) as $breaks |
        add // [] | map(select(.text != "" and (.script | not)) | del(.block, .script) |
          if .line > 0 then . else
            .text as $t | (($raw | index($t | tojson)) // ($raw | index($t | split("\n")[0]))) as $at |
            .line = (if $at then -($breaks | bsearch($at)) else null end)
          end | .text |= gsub("\n"; " ")) + $scripts' <<<"$strings"
      return
      ;;
    *)
      if ! head -n 1 "$file" | grep -qE '^#!.*[/ ](ba|z)?sh'; then
        # Only a chezmoi template has the comments {{/* ... */}}. In any
        # other file, /* is text, such as a glob.
        case "$file" in
          *.tmpl | */.chezmoitemplates/* | */.chezmoiignore | */.chezmoiremove) ;;
          *)
            echo '[]'
            return
            ;;
        esac
        # The comments of a chezmoi template, line by line.
        awk '{
          line = $0; out = ""
          while (line != "") {
            if (!inside) { i = index(line, "/*"); if (!i) break; inside = 1; line = substr(line, i + 2) }
            j = index(line, "*/")
            if (j) { out = out substr(line, 1, j - 1) " "; line = substr(line, j + 2); inside = 0 }
            else { out = out line; line = "" }
          }
          gsub(/^[ \t-]+|[ \t-]+$/, "", out)
          if (out != "") printf "%d\t%s\n", NR, out
        }' "$file" | jq -Rs '[split("\n")[] | select(. != "") | capture("^(?<line>[0-9]+)\t(?<text>.*)$") | .line |= tonumber]'
        return
      fi
      ;;
  esac
  shell_messages "$file"
}

# Checks all the prose of file $1 that Vale and lint.py can read. $2 is a
# JSON array of the line numbers to report, or null for all lines. $3 is
# the .vale.ini to use.
check_prose() {
  local file="$1" lines="$2" config="$3" ext prose='[]' other text
  # A binary file, such as an image, holds no text.
  grep -Iq . "$file" || return
  ext="$(vale_ext "$file")"
  case "$ext" in
    "") ;;
    md | markdown | mdx | txt)
      check_english "$file" "$ext" "$config" "$lines" "$file"
      check_japanese "$file" "$lines" "$file"
      ;;
    html | htm)
      # lint.py can read only Markdown and plain text.
      check_english "$file" "$ext" "$config" "$lines" "$file"
      check_japanese "$(at_lines "$file" "$(vale_text "$file" "$ext")")" "$lines" "$file"
      ;;
    *)
      prose="$(vale_text "$file" "$ext")" ||
        notes+=("Vale couldn't read the comments of $file, so the check didn't check them.")
      ;;
  esac
  if ! other="$(other_prose "$file")"; then
    notes+=("The check couldn't read $file, so it didn't check its text. Fix: make it valid, or leave it out with exclude in lefthook.yml.")
  fi
  if jq -e 'any(.[]; .line == null)' <<<"$other" >/dev/null 2>&1; then
    notes+=("The check couldn't find the line of a string in $file, so it didn't check that string. Fix: write it as jq -c writes it, with no \\u or \\/ escape.")
  fi
  # Vale reads a # line of a workflow's script as a comment of the file,
  # so the same text can come from both.
  prose="$(jq -sc 'map(. // []) | add | unique' <<<"${prose:-[]} ${other:-[]}")"
  if [ "$prose" != "[]" ]; then
    text="$(at_lines "$file" "$prose")"
    check_english "$text" md "$config" "$lines" "$file"
    check_japanese "$text" "$lines" "$file"
  fi
}
