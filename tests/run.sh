#!/bin/bash
# Runs prose.sh on each case of tests/cases, in the language that its
# directory names: english or japanese. The name of a case says the result
# that the check must give: a case named pass-* has no finding, a case named
# show-* passes with the finding that its line "expect:" names, and a case
# named fail-* fails with that finding. A check must fail where it should,
# or it passes everything. The runs after the cases check each thing that
# the checks must do, with one case each.
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
failed=0
for file in "$here"/cases/english/* "$here"/cases/japanese/*; do
  name="${file##*/}"
  language="$(basename "$(dirname "$file")")"
  out="$(cd "$(dirname "$file")" && "$here/../prose.sh" "$language" "$name" 2>&1)"
  status=$?
  want="$(grep -m 1 -oE 'expect: [^,>]+[^ ,>-]' "$file" | sed 's/^expect: //')"
  case "$name" in
    pass-*)
      if [ "$status" -ne 0 ] || [ -n "$out" ]; then
        echo "Failed: $language/$name should pass with no finding, but the check exited $status with:"; echo "$out"; failed=1
      fi
      ;;
    show-* | fail-*)
      code=1
      case "$name" in show-*) code=0 ;; esac
      if [ "$status" -ne "$code" ] || [ -z "$want" ] || ! grep -qF -- "$want" <<<"$out"; then
        echo "Failed: $language/$name should exit $code with ${want:-the finding that its line expect: names}, but the check exited $status with:"; echo "$out"; failed=1
      fi
      ;;
  esac
done

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
# Runs prose.sh with the arguments after $1, in directory $1, and sets $out
# and $status.
run_in() {
  local dir="$1"
  shift
  out="$(cd "$dir" && "$here/../prose.sh" "$@" 2>&1)"
  status=$?
}
# Fails run $1 unless it exited $2 and printed each text after $2.
want() {
  local name="$1" code="$2" text ok=1
  shift 2
  [ "$status" -eq "$code" ] || ok=0
  for text in "$@"; do grep -qF -- "$text" <<<"$out" || ok=0; done
  if [ "$ok" -eq 0 ]; then
    echo "Failed: $name should exit $code with $*, but the check exited $status with:"; echo "$out"; failed=1
  fi
}
# Fails unless the report of the last run gives tool $1 on file $2 the
# finding $3.
finding() {
  awk -v heading="$1 on $2:" '$0 == heading { on = 1; next } on && /^$/ { exit } on' <<<"$out" | grep -qF -- "$3" ||
    { echo "Failed: $2 should get $3 of $1, but the check printed:"; echo "$out"; failed=1; }
}

# The report says what the checks are for, before the findings and after.
run_in "$here/cases/english" english fail-english.md
want "the report" 1 "The checks found text that its reader may not understand." "Rewrite each part for its reader."

# The settings of the repository lie over the defaults, and each file gets
# the nearest settings, up to the root of the repository: those above it,
# and those of VALE_CONFIG_PATH, which Vale would read in place of those of
# the repository, would turn off the rules.
mkdir -p "$tmp/above/repo/docs/deep"
printf '[*]\nGoogle.Latin = NO\n' | tee "$tmp/above/off.ini" >"$tmp/above/.vale.ini"
printf '{"rules": {"preset-ja-technical-writing": false}}\n' >"$tmp/above/.textlintrc.json"
printf '[*]\nGoogle.Latin = suggestion\n' >"$tmp/above/repo/docs/.vale.ini"
printf '{"rules": {"preset-ja-technical-writing": {"no-mix-dearu-desumasu": {"severity": "info"}}}}\n' >"$tmp/above/repo/docs/.textlintrc.json"
for dir in . docs/deep; do
  cp "$here/cases/english/fail-english.md" "$here/cases/japanese/fail-japanese.md" "$tmp/above/repo/$dir/"
done
out="$(cd "$tmp/above/repo" && VALE_CONFIG_PATH="$tmp/above/off.ini" "$here/../prose.sh" english fail-english.md docs/deep/fail-english.md 2>&1)"
status=$?
want "the settings of Vale" 1
finding Vale fail-english.md "Google.Latin (error)"
finding Vale docs/deep/fail-english.md "Google.Latin (suggestion)"
run_in "$tmp/above/repo" japanese fail-japanese.md docs/deep/fail-japanese.md
want "the settings of textlint" 1
finding textlint fail-japanese.md "no-mix-dearu-desumasu (error)"
finding textlint docs/deep/fail-japanese.md "no-mix-dearu-desumasu (info)"

# A tool that fails stops the commit, with all that it printed and the fix.
fix="Otherwise, run $(cd "$here/.." && pwd)/setup.sh again, and if the check still fails, report it with this message in an issue of https://github.com/lovaizu/checks/issues."
mkdir -p "$tmp/broken"
cp "$here/cases/english/pass-english.md" "$here/cases/japanese/pass-japanese.md" "$tmp/broken/"
printf '[*]\nBasedOnStyles = NoSuchStyle\n' >"$tmp/broken/.vale.ini"
printf '{"rules": \n' >"$tmp/broken/.textlintrc.json"
run_in "$tmp/broken" english pass-english.md
want "a Vale that fails" 1 "Vale didn't check pass-english.md: Vale exited " "$fix" "NoSuchStyle"
run_in "$tmp/broken" japanese pass-japanese.md
want "a textlint that fails" 1 "textlint didn't check pass-japanese.md: Node exited 1. " "$fix" "JSON5: invalid end of input"

# A file of a format that textlint doesn't read fails, with the formats that
# it reads.
mkdir -p "$tmp/format"
printf 'pre-commit: {}\n' >"$tmp/format/lefthook.yml"
run_in "$tmp/format" japanese lefthook.yml
want "a format that textlint doesn't read" 1 "textlint didn't check lefthook.yml: textlint reads only the files that end in .txt, .text, .md, " "Fix: leave each file out of the job japanese"

# A file that isn't text in UTF-8 fails, as a tool would read it as other
# text. A file with a NUL byte, such as an image, holds no text and passes,
# as pass-binary.png does.
mkdir -p "$tmp/encoding"
printf 'A caf\xe9 sentence.\n' >"$tmp/encoding/latin1.md"
run_in "$tmp/encoding" english latin1.md
want "a file in Latin-1" 1 "The checks didn't check latin1.md: it isn't text in UTF-8"

# Each sentence of the case of ja-no-unneeded-comma gets a finding of its
# own, and a repository changes the rule in its settings, as any other rule.
mkdir -p "$tmp/comma"
cp "$here/cases/japanese/fail-japanese-comma.md" "$tmp/comma/"
run_in "$tmp/comma" japanese fail-japanese-comma.md
[ "$(grep -c 'ja-no-unneeded-comma (error)' <<<"$out")" -eq 4 ] || { echo "Failed: each sentence of fail-japanese-comma.md should get ja-no-unneeded-comma (error), but got:"; echo "$out"; failed=1; }
printf '{"rules": {"ja-no-unneeded-comma": {"severity": "info"}}}\n' >"$tmp/comma/.textlintrc.json"
run_in "$tmp/comma" japanese fail-japanese-comma.md
want "ja-no-unneeded-comma at the level info" 0 "ja-no-unneeded-comma (info)"
printf '{"rules": {"ja-no-unneeded-comma": false}}\n' >"$tmp/comma/.textlintrc.json"
run_in "$tmp/comma" japanese fail-japanese-comma.md
[ "$status" -eq 0 ] && [ -z "$out" ] || { echo "Failed: ja-no-unneeded-comma: false should turn off the rule, but the check exited $status with:"; echo "$out"; failed=1; }

# Each package that the checks load is in textlint/package.json, which
# pins it.
for module in $(grep -ohE 'require\("[^"]+"\)' "$here"/../textlint/*.mjs | sed -E 's/require\("((@[^/"]+\/)?[^/"]+)[^"]*"\)/\1/' | sort -u); do
  jq -e --arg module "$module" '.dependencies | has($module)' "$here/../textlint/package.json" >/dev/null ||
    { echo "Failed: textlint/*.mjs loads $module, which textlint/package.json doesn't name."; failed=1; }
done

[ "$failed" -eq 0 ] && echo "All cases passed."
exit "$failed"
