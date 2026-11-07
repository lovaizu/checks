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

# Prints the extension by which Vale reads a file, or nothing when Vale
# cannot read the file's prose. A chezmoi template is read by the extension
# before .tmpl. Vale reads the formats that have # comments, such as shell
# and YAML, as Python, and it reads only their comments. Vale reads other
# formats that it does not know as plain text, code and all, so they are
# left out. reStructuredText, AsciiDoc and XML need programs that are not
# installed (rst2html, asciidoctor, xsltproc).
vale_ext() {
  local name="${1##*/}"
  name="${name%.tmpl}"
  if [ "$name" = "${name%.*}" ] || [ "${name%.*}" = "" ]; then
    # A file with no extension, such as an executable, is read by the
    # program that its first line names.
    if head -n 1 "$1" 2>/dev/null | grep -qE '^#!.*[/ ](ba|z)?sh'; then echo py; fi
    return
  fi
  case "${name##*.}" in
    md | markdown | mdx | txt | html | htm) echo "${name##*.}" ;;
    c | h | clj | cljs | cljc | cs | cpp | cc | cxx | hpp | css | ex | exs | go | hs | java | js | jsx | mjs | cjs | jl | kt | kts | less | lua | pl | pm | php | ps1 | proto | py | qml | r | R | rb | rs | sass | scss | scala | swift | ts | tsx | mts | cts) echo "${name##*.}" ;;
    sh | bash | zsh | yml | yaml | toml | jq | ini) echo py ;;
  esac
}

is_markdown() {
  case "$1" in md | markdown | mdx) return 0 ;; esac
  return 1
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
  # would read it as Japanese and judge the English.
  made=$((made + 1))
  japanese="$work/mostly-japanese-$made.md"
  jq -Rsr '
    def count(re): [scan(re)] | length;
    split("\n")[:-1][] |
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

# Writes the Japanese text that Vale finds in file $1, read as extension
# $2, into a Markdown file at the same line numbers, and prints its path.
# lint.py can read only Markdown and plain text, so this is how it reads a
# code comment.
japanese_text() {
  local file="$1" ext="$2" out config="$root/vale/japanese.ini"
  made=$((made + 1))
  out="$work/japanese-$made.md"
  (cd "$(dirname "$config")" && vale --no-exit --output=JSON --config="$config" --ext=".$ext" <"$file" 2>/dev/null) |
    jq -r --argjson n "$(wc -l <"$file")" '
      ([.[] | .[] | {(.Line | tostring): .Match}] | add // {}) as $at |
      range(1; $n + 2) | $at[tostring] // ""' >"$out"
  echo "$out"
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

# Prints, as {line, text}, the prose of file $1 that Vale can't read where
# it is: the messages of a shell script, the descriptions in a JSON file,
# and the comments of a chezmoi template. Vale reads the rest of the file.
other_prose() {
  local file="$1" name="${1##*/}"
  name="${name%.tmpl}"
  case "$name" in
    *.sh | *.bash | *.zsh) ;;
    *.json)
      jq -r '[.. | objects | .description? | strings] | .[]' "$file" 2>/dev/null |
        while IFS= read -r text; do
          jq -n --arg text "$text" --argjson line "$(grep -nF -m 1 -- "$text" "$file" | cut -d: -f1)" '{line: $line, text: $text}'
        done | jq -s .
      return
      ;;
    *)
      if ! head -n 1 "$file" | grep -qE '^#!.*[/ ](ba|z)?sh'; then
        # The comments of a chezmoi template, {{/* ... */}}, line by line.
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
  # shfmt can't parse a template's {{ ... }}, so each one reads as x.
  sed 's/{{[^}]*}}/x/g' "$file" | shfmt --to-json 2>/dev/null | jq -c -f "$root/lib/shell-messages.jq" || echo '[]'
}

# Checks all the prose of file $1 that Vale and lint.py can read. $2 is a
# JSON array of the line numbers to report, or null for all lines. $3 is
# the .vale.ini to use.
check_prose() {
  local file="$1" lines="$2" config="$3" ext prose text
  ext="$(vale_ext "$file")"
  if [ -n "$ext" ]; then
    check_english "$file" "$ext" "$config" "$lines" "$file"
    if is_markdown "$ext" || [ "$ext" = txt ]; then
      check_japanese "$file" "$lines" "$file"
    else
      check_japanese "$(japanese_text "$file" "$ext")" "$lines" "$file"
    fi
  fi
  prose="$(other_prose "$file")"
  if [ -n "$prose" ] && [ "$prose" != "[]" ]; then
    text="$(at_lines "$file" "$prose")"
    check_english "$text" md "$config" "$lines" "the messages in $file"
    check_japanese "$text" "$lines" "the messages in $file"
  fi
}
