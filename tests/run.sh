#!/bin/bash
# Runs prose.sh on each case of tests/cases, in the language that its
# directory names: english or japanese. The name of a case says the result
# that the check must give: a case named pass-* has no finding, a case named
# show-* passes with the finding that its line "expect:" names, and a case
# named fail-* fails with that finding. A check must fail where it should,
# or it passes everything. Each directory of cases is the root of a
# repository, where the checks find its settings, such as the .vale.ini of
# the English cases.
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
failed=0
for file in "$here"/cases/english/* "$here"/cases/japanese/*; do
  name="${file##*/}"
  language="$(basename "$(dirname "$file")")"
  name="$language/$name"
  out="$(cd "$(dirname "$file")" && "$here/../prose.sh" "$language" "${file##*/}" 2>&1)"
  status=$?
  want="$(grep -m 1 -oE 'expect: [^,>]+[^ ,>-]' "$file" | sed 's/^expect: //')"
  case "${name#*/}" in
    pass-*)
      if [ "$status" -ne 0 ] || [ -n "$out" ]; then
        echo "Failed: $name should pass with no finding, but the check exited $status with:"; echo "$out"; failed=1
      fi
      ;;
    show-* | fail-*)
      code=1
      case "${name#*/}" in show-*) code=0 ;; esac
      if [ "$status" -ne "$code" ] || [ -z "$want" ] || ! grep -qF -- "$want" <<<"$out"; then
        echo "Failed: $name should exit $code with ${want:-the finding that its line expect: names}, but the check exited $status with:"; echo "$out"; failed=1
      fi
      ;;
  esac
done

# The runs below check how the checks run, not one case each. Each run
# sets $out and $status, and want and unwanted check them.
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
# Runs prose.sh with the arguments after $1, in directory $1.
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
# Fails run $1 if it printed text $2.
unwanted() {
  if grep -qF -- "$2" <<<"$out"; then
    echo "Failed: $1 shouldn't print $2, but printed:"; echo "$out"; failed=1
  fi
}
# Prints the findings under the heading of tool $1 on file $2 in the report
# of the last run, with the settings of the repository or without.
section() {
  awk -v heading="$1 on $2" '$0 == heading ":" || index($0, heading ", with ") == 1 { on = 1; next } on && /^$/ { exit } on' <<<"$out"
}

# A commit gives each tool all its files in one run, and each file gets the
# findings of its own.
run_in "$here/cases/japanese" japanese "$here"/cases/japanese/*
for file in "$here"/cases/japanese/*; do
  name="${file##*/}"
  expected="$(grep -m 1 -oE 'expect: [^,>]+[^ ,>-]' "$file" | sed 's/^expect: //')"
  got="$(section textlint "$name")"
  case "$name" in
    pass-*) [ -z "$got" ] || { echo "Failed: $name should get no finding in a run of all the Japanese cases, but got:"; echo "$got"; failed=1; } ;;
    *) grep -qF -- "$expected" <<<"$got" || { echo "Failed: $name should get $expected in a run of all the Japanese cases, but got:"; echo "$got"; failed=1; } ;;
  esac
done
want "all the Japanese cases" 1
run_in "$here/cases/english" english "$here"/cases/english/*.md
for name in fail-english.md show-english.md; do
  expected="$(grep -m 1 -oE 'expect: [^,>]+[^ ,>-]' "$here/cases/english/$name" | sed 's/^expect: //')"
  section Vale "$name" | grep -qF -- "$expected" || { echo "Failed: $name should get $expected in a run of all the English cases, but got:"; echo "$out"; failed=1; }
done
want "all the English cases" 1

# A file whose name holds the characters of a glob is checked as it is, and
# so is a file in node_modules: the repository chooses the files.
mkdir -p "$tmp/names/node_modules/z"
for name in '[x].md' 'y{1,2}.md' node_modules/z/a.md; do
  cp "$here/cases/japanese/fail-japanese.md" "$tmp/names/$name"
  cp "$here/cases/english/fail-english.md" "$tmp/names/${name%.md}.en.md"
done
run_in "$tmp/names" japanese '[x].md' 'y{1,2}.md' node_modules/z/a.md
for name in '[x].md' 'y{1,2}.md' node_modules/z/a.md; do
  section textlint "$name" | grep -qF "no-mix-dearu-desumasu (error)" || { echo "Failed: $name should get its finding of textlint, but got:"; echo "$out"; failed=1; }
done
want "files with the characters of a glob" 1
unwanted "files with the characters of a glob" "didn't check"
run_in "$tmp/names" english '[x].en.md' 'y{1,2}.en.md' node_modules/z/a.en.md
for name in '[x].en.md' 'y{1,2}.en.md' node_modules/z/a.en.md; do
  section Vale "$name" | grep -qF "Google.Latin (error)" || { echo "Failed: $name should get its finding of Vale, but got:"; echo "$out"; failed=1; }
done

# A file that the repository leaves out in .textlintignore passes, of any
# format.
mkdir "$tmp/ignore"
cp "$here/cases/japanese/fail-japanese.md" "$tmp/ignore/left-out.md"
printf 'pre-commit: {}\n' >"$tmp/ignore/lefthook.yml"
printf '# Files that the repository leaves out.\nleft-out.md\nlefthook.yml\n' >"$tmp/ignore/.textlintignore"
run_in "$tmp/ignore" japanese left-out.md lefthook.yml
want ".textlintignore" 0
unwanted ".textlintignore" "left-out.md"
unwanted ".textlintignore" "lefthook.yml"

# A CDPATH, which cd follows, doesn't lead a path to another directory.
mkdir -p "$tmp/cdpath/docs" "$tmp/elsewhere/docs"
cp "$here/cases/english/fail-english.md" "$tmp/cdpath/docs/guide.md"
out="$(cd "$tmp/cdpath" && CDPATH="$tmp/elsewhere" "$here/../prose.sh" english docs/guide.md 2>&1)"
status=$?
want "CDPATH" 1 "Vale on docs/guide.md:" "Google.Latin (error)"

# When a rule fails on one file, the other files keep their findings, and
# the reason names the file and the fix. A rule of the test, which prints
# to stdout and fails on BOOM, runs with the packages of textlint.
root="$here/.."
. "$here/../lib/paths.sh"
mkdir -p "$tmp/boom/node_modules/textlint-rule-boom" "$tmp/boom/repo"
for module in "$textlint_dir"/node_modules/* "$textlint_dir"/node_modules/.bin; do ln -s "$module" "$tmp/boom/node_modules/"; done
printf '{"name": "textlint-rule-boom", "main": "index.js"}\n' >"$tmp/boom/node_modules/textlint-rule-boom/package.json"
printf 'module.exports = (context) => ({ [context.Syntax.Str](node) { console.log("A line of the rule"); if (context.getSource(node).includes("BOOM")) throw new Error("the rule of the test failed"); } });\n' >"$tmp/boom/node_modules/textlint-rule-boom/index.js"
printf '{"rules": {"boom": true}}\n' >"$tmp/boom/repo/.textlintrc.json"
cp "$here/cases/japanese/fail-japanese.md" "$tmp/boom/repo/good.md"
printf 'BOOM\n' >"$tmp/boom/repo/boom.md"
out="$(cd "$tmp/boom/repo" && mise -C "$here/.." exec -- node "$here/../textlint/check.mjs" "$tmp/boom/node_modules" "$PWD" "$tmp/boom" "$tmp/boom/repo/good.md" "$tmp/boom/repo/boom.md" 2>&1)"
status=$?
want "a rule that prints" 0 "A line of the rule"
out="$(cat "$tmp/boom/textlint.json")"
want "a rule that fails on one file" 0 "textlint didn't check $tmp/boom/repo/boom.md: " "the rule of the test failed" "failed. Fix: turn off in the settings of textlint" '"file":"'"$tmp/boom/repo/good.md"'"' "no-mix-dearu-desumasu"
unwanted "a rule that fails on one file" "didn't check $tmp/boom/repo/good.md"

# A warning of Node on stderr is no reason to skip the check, and the
# reason of a failure comes through it.
printf 'process.emitWarning("A warning of the test");\n' >"$tmp/warn.cjs"
out="$(cd "$here/cases/japanese" && NODE_OPTIONS="--require $tmp/warn.cjs" "$here/../prose.sh" japanese fail-japanese.md 2>&1)"
status=$?
want "a warning of Node" 1 "no-mix-dearu-desumasu (error)"
unwanted "a warning of Node" "didn't check"
mkdir "$tmp/js"
printf 'module.exports = {};\n' >"$tmp/js/.textlintrc.js"
cp "$here/cases/japanese/pass-japanese.md" "$tmp/js/"
out="$(cd "$tmp/js" && NODE_OPTIONS="--require $tmp/warn.cjs" "$here/../prose.sh" japanese pass-japanese.md 2>&1)"
status=$?
want "a reason with a warning of Node" 1 "textlint didn't check the Japanese: " ".textlintrc.js is JavaScript"

# Settings that textlint can't load fail with the reason and a fix that the
# repository can take, not the advice of textlint to install a package.
mkdir "$tmp/rule"
printf '{"rules": {"no-such-rule": true}}\n' >"$tmp/rule/.textlintrc.json"
cp "$here/cases/japanese/pass-japanese.md" "$tmp/rule/"
run_in "$tmp/rule" japanese pass-japanese.md
want "a rule that isn't installed" 1 '"no-such-rule" is not found' "Fix: in the settings of textlint of the repository, turn off or remove each rule"
unwanted "a rule that isn't installed" "FAQ"
printf '{"rules": {"preset-no-such": true}}\n' >"$tmp/rule/.textlintrc.json"
run_in "$tmp/rule" japanese pass-japanese.md
want "a preset that isn't installed" 1 "textlint-rule-preset-no-such" "Fix: in the settings of textlint of the repository"
printf '{"rules": \n' >"$tmp/rule/.textlintrc.json"
run_in "$tmp/rule" japanese pass-japanese.md
want "settings that aren't JSON" 1 ".textlintrc.json: " "Fix: correct the syntax of the file."
# Settings of Vale that Vale can't load fail with the fix.
mkdir "$tmp/vale"
printf '[*]\nBasedOnStyles = NoSuchStyle\n' >"$tmp/vale/.vale.ini"
cp "$here/cases/english/pass-english.md" "$tmp/vale/"
run_in "$tmp/vale" english pass-english.md
want "settings of Vale that Vale can't load" 1 "NoSuchStyle" "Fix: correct the settings of Vale of the repository"
# A Vale that fails with no message, or with JSON that has no Text, still
# gives a reason. A function named vale takes the place of the program.
for fake in 'return 2' 'echo "{\"Code\": \"E1\"}" >&2; return 2'; do
  out="$(cd "$here/cases/english" && bash -c '. "$1/lib/lib.sh"; vale() { '"$fake"'; }; check_english "$PWD/pass-english.md"; printf "%s\n" "${notes[@]}"' _ "$here/.." 2>&1)"
  status=0
  case "$fake" in
    'return 2') want "a Vale that says nothing" 0 "Vale didn't check the English: it exited 2 with no message" ;;
    *) want "a Vale with JSON that has no Text" 0 'Vale didn'"'"'t check the English: {"Code": "E1"}' ;;
  esac
done

# A file that Vale can't read fails, with the reason that Vale gives, and
# the other files of the run keep their findings. reStructuredText needs
# rst2html, so this case runs where rst2html isn't installed.
# Vale runs again only on the files that the failed run didn't report: a
# function named vale logs each run.
if ! command -v rst2html >/dev/null; then
  printf 'Title\n=====\n\nA sentence.\n' >"$tmp/case.rst"
  run_in "$here/cases/english" english "$tmp/case.rst" fail-english.md
  want "a reStructuredText file" 1 "rst2html not found" "Fix: leave the file out of the job english" "Google.Latin (error)"
  out="$(cd "$here/cases/english" && bash -c '. "$1/lib/lib.sh"; log="$2"; vale() { echo "vale $*" >>"$log"; command vale "$@"; }; check_english "$PWD/fail-english.md" "$PWD/pass-english.md" "$3"' _ "$here/.." "$tmp/vale.log" "$tmp/case.rst" 2>&1; cat "$tmp/vale.log")"
  status=0
  want "a run of Vale again" 0 "vale --no-exit --output=JSON $here/cases/english/pass-english.md" "vale --no-exit --output=JSON $tmp/case.rst"
  ! grep -qxF "vale --no-exit --output=JSON $here/cases/english/fail-english.md" <<<"$out" ||
    { echo "Failed: Vale shouldn't run again on fail-english.md, which the failed run reported, but it ran:"; echo "$out"; failed=1; }
fi

# A file of a format that textlint doesn't read fails, with the formats
# that it reads and the fix. A Markdown file of the same run keeps its
# findings. The formats are those of the settings: a repository that
# gives the plugin of Markdown more extensions gets those checked too.
printf '# この設定は、ルートに置くものである。\n' >"$tmp/case.py"
run_in "$here/cases/japanese" japanese "$tmp/case.py" fail-japanese.md
want "a Python file" 1 "textlint didn't check $(cd -P "$tmp" && pwd)/case.py, as it reads only the files that end in .txt, .text, .md, " "Fix: leave the file out of the job japanese" "no-mix-dearu-desumasu (error)"
mkdir "$tmp/mdx"
printf '{"plugins": {"@textlint/markdown": {"extensions": [".mdx"]}}}\n' >"$tmp/mdx/.textlintrc.json"
cp "$here/cases/japanese/fail-japanese.md" "$tmp/mdx/guide.mdx"
run_in "$tmp/mdx" japanese guide.mdx
want "an extension of the settings" 1 "textlint on guide.mdx, with .textlintrc.json:" "no-mix-dearu-desumasu (error)"
# The reason names each extension once, as the plugin that reads it first.
cp "$tmp/case.py" "$tmp/mdx/"
run_in "$tmp/mdx" japanese case.py
want "the extensions of the settings" 1 ", .mdx. Fix:"
[ "$(grep -o '\.md,' <<<"$out" | wc -l)" -eq 1 ] || { echo "Failed: the reason should name .md once, but it says:"; echo "$out"; failed=1; }

# Each package that the checks load is in textlint/package.json.
for module in $(grep -ohE 'require\("[^"]+"\)' "$here"/../textlint/*.mjs | sed -E 's/require\("([^"]+)"\)/\1/' | sort -u); do
  jq -e --arg module "$module" '.dependencies | has($module)' "$here/../textlint/package.json" >/dev/null ||
    { echo "Failed: textlint/*.mjs loads $module, which textlint/package.json doesn't name."; failed=1; }
done

[ "$failed" -eq 0 ] && echo "All cases passed."
exit "$failed"
