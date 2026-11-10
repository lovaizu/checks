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

# The fixes that a failure names: one for a format that the tool doesn't
# read, one for settings of the repository, and one for a cause that the
# checks don't know, which names the cache and setup.sh.
root="$here/.."
. "$here/../lib/paths.sh"
fix_settings="Fix: correct the settings of the repository that the reason names."
fix_unknown="Fix: delete $textlint_dir, run $(cd "$here/.." && pwd)/setup.sh, and run the check again. If the check still fails, report it in an issue of lovaizu/checks with this message."
# Runs the functions of lib/lib.sh in bash in directory $1, with the script
# $2 before check_$3 on the files after $3, and sets $out to each note and
# the findings that fail.
run_lib() {
  local dir="$1" before="$2" check="$3"
  shift 3
  out="$(cd "$dir" && bash -c '. "$1/lib/lib.sh"; '"$before"'; shift; "$@"; printf "%s\n" "${notes[@]}" "$fails"' _ "$here/.." "check_$check" "$@" 2>&1)"
  status=0
}

# A report that jq can't read fails, with what it holds.
out="$(bash -c '. "$1/lib/lib.sh"; add_report Vale english "not JSON"; printf "%s\n" "${notes[@]}"' _ "$here/.." 2>&1)"
status=0
want "a report that jq can't read" 0 "Vale didn't check the files of the job english: jq couldn't read its report: " "$fix_unknown" "not JSON"

# When a rule fails on one file, the other files keep their findings, and
# the note names the file, with the fix of an unknown cause. A rule of the
# test, which prints to stdout and fails on BOOM, runs with the packages of
# textlint, and so do checks that lack a package.
mkdir -p "$tmp/boom/node_modules/textlint-rule-boom" "$tmp/boom/repo"
for module in "$textlint_dir"/node_modules/* "$textlint_dir"/node_modules/.bin; do ln -s "$module" "$tmp/boom/node_modules/"; done
printf '{"name": "textlint-rule-boom", "main": "index.js"}\n' >"$tmp/boom/node_modules/textlint-rule-boom/package.json"
printf 'module.exports = (context) => ({ [context.Syntax.Str](node) { console.log("A line of the rule"); if (context.getSource(node).includes("BOOM")) throw new Error("the rule of the test failed"); } });\n' >"$tmp/boom/node_modules/textlint-rule-boom/index.js"
printf '{"rules": {"boom": true}}\n' >"$tmp/boom/repo/.textlintrc.json"
cp "$here/cases/japanese/fail-japanese.md" "$tmp/boom/repo/good.md"
printf 'BOOM\n' >"$tmp/boom/repo/boom.md"
# Runs check.mjs in $tmp/boom/repo with the node_modules of $tmp/boom on
# good.md and boom.md, and sets $out to its report.
run_boom() {
  out="$(cd "$tmp/boom/repo" && mise -C "$here/.." exec -- node "$here/../textlint/check.mjs" "$tmp/boom/node_modules" "$PWD" "$tmp/boom" "$tmp/boom/repo/good.md" "$tmp/boom/repo/boom.md" 2>&1)"
  status=$?
  printed="$out"
  out="$(cat "$tmp/boom/textlint.json")"
}
run_boom
want "a rule that fails on one file" 0 '"file":"'"$tmp/boom/repo/boom.md"'","kind":"unknown","reason":"the rule of the test failed' '"file":"'"$tmp/boom/repo/good.md"'"' "no-mix-dearu-desumasu"
out="$printed"
want "a rule that prints" 0 "A line of the rule"
# A rule of the defaults that textlint can't load is no error of the
# settings of the repository.
rm "$tmp/boom/node_modules/textlint-rule-ja-hiragana-fukushi"
run_boom
want "a rule of the defaults that isn't installed" 0 '"kind":"unknown"' 'ja-hiragana-fukushi'
rm "$tmp/boom/node_modules/@textlint" && mkdir "$tmp/boom/node_modules/@textlint"
for module in "$textlint_dir"/node_modules/@textlint/*; do [ "${module##*/}" = config-loader ] || ln -s "$module" "$tmp/boom/node_modules/@textlint/"; done
run_boom
want "a check without a package" 0 '"kind":"unknown","reason":"Cannot find module '"'"'@textlint/config-loader'"'"'' '"stack":'

# A failure of Node gives what Node printed in full, with the fix of an
# unknown cause. A report that check.mjs wrote before Node failed keeps
# its findings. A warning of Node on stderr is no reason to skip the check.
printf 'process.emitWarning("A warning of the test");\n' >"$tmp/warn.cjs"
out="$(cd "$here/cases/japanese" && NODE_OPTIONS="--require $tmp/warn.cjs" "$here/../prose.sh" japanese fail-japanese.md 2>&1)"
status=$?
want "a warning of Node" 1 "no-mix-dearu-desumasu (error)"
unwanted "a warning of Node" "didn't check"
long="$(printf 'A reason of the test%.0s, ' $(seq 1 60))the end"
printf 'throw new Error("%s");\n' "$long" >"$tmp/crash.cjs"
out="$(cd "$here/cases/japanese" && NODE_OPTIONS="--require $tmp/crash.cjs" "$here/../prose.sh" japanese fail-japanese.md 2>&1)"
status=$?
want "a failure of Node" 1 "textlint didn't check the files of the job japanese: Node exited 1 before check.mjs wrote its report. $fix_unknown" "stderr:" "$long"
printf 'process.on("exit", () => { process.exitCode = 3; });\n' >"$tmp/exit.cjs"
out="$(cd "$here/cases/japanese" && NODE_OPTIONS="--require $tmp/exit.cjs" "$here/../prose.sh" japanese fail-japanese.md 2>&1)"
status=$?
want "a failure of Node after the report" 1 "no-mix-dearu-desumasu (error)" "textlint didn't check the files of the job japanese: Node exited 3. $fix_unknown"

# Settings of the repository that config.mjs can't read fail once, with
# the fix of settings. A rule that textlint can't load fails with all that
# textlint said, as textlint doesn't name the settings that name the rule.
mkdir "$tmp/rule"
cp "$here/cases/japanese/pass-japanese.md" "$here/cases/japanese/fail-japanese.md" "$tmp/rule/"
for settings in '{"rules": |JSON5: invalid end of input|settings' \
  '{"rules": {"prh": {"rulePaths": ["missing.yml"]}}}|missing.yml, which doesn'"'"'t exist|settings' \
  '{"rules": {"no-such-rule": true}}|"no-such-rule" is not found|unknown' \
  '{"rules": {"preset-no-such": true}}|"preset-no-such" is not found|unknown'; do
  printf '%s\n' "${settings%%|*}" >"$tmp/rule/.textlintrc.json"
  rest="${settings#*|}"
  if [ "${rest#*|}" = settings ]; then fix="$fix_settings"; else fix="$fix_unknown"; fi
  run_in "$tmp/rule" japanese pass-japanese.md fail-japanese.md
  want "settings $(head -c 40 "$tmp/rule/.textlintrc.json")" 1 "textlint didn't check the files of the job japanese: " "${rest%%|*}" "$fix"
  [ "$(grep -c "didn't check" <<<"$out")" -eq 1 ] || { echo "Failed: settings that textlint can't load should fail once, but the check said:"; echo "$out"; failed=1; }
done
rm "$tmp/rule/.textlintrc.json"
printf 'module.exports = {};\n' >"$tmp/rule/.textlintrc.js"
run_in "$tmp/rule" japanese pass-japanese.md
want "settings in JavaScript" 1 ".textlintrc.js is JavaScript" "$fix_settings"
rm "$tmp/rule/.textlintrc.js"
# Settings that turn off each rule load, and the check passes.
printf '{"rules": {"preset-ja-technical-writing": false, "@textlint-ja/preset-ai-writing": false, "ja-hiragana-keishikimeishi": false, "ja-hiragana-hojodoushi": false, "ja-hiragana-fukushi": false, "ja-space-between-half-and-full-width": false}}\n' >"$tmp/rule/.textlintrc.json"
run_in "$tmp/rule" japanese fail-japanese.md
want "settings with no rule" 0
unwanted "settings with no rule" "didn't check"

# A .vale.ini of the repository that Vale can't load fails with the reason,
# where in the file, and the fix of settings. Settings of the checks that
# Vale can't load, such as with no Google style, fail with an unknown
# cause.
mkdir "$tmp/vale"
printf '[*]\nBasedOnStyles = NoSuchStyle\n' >"$tmp/vale/.vale.ini"
cp "$here/cases/english/pass-english.md" "$tmp/vale/"
run_in "$tmp/vale" english pass-english.md
want "a .vale.ini that Vale can't load" 1 "Style 'NoSuchStyle' isn't on the StylesPath" ".vale.ini, line 2). $fix_settings"
run_lib "$here/cases/english" 'VALE_STYLES_PATH=/nonexistent' english "$here/cases/english/pass-english.md"
want "settings of the checks that Vale can't load" 0 "Vale didn't check the files of the job english: Vale failed. $fix_unknown" "Google"
# A Vale that fails for no reason that the checks know gives all that it
# printed, with the fix of an unknown cause. A function named vale takes
# the place of the program.
for fake in 'return 2' 'echo "{\"Code\": \"E1\"}" >&2; return 2' 'case "$*" in *line*) echo "[$file]:E100:the test broke" >&2 ;; esac; return 2'; do
  run_lib "$here/cases/english" 'file="$PWD/pass-english.md"; vale() { case "$1" in ls-config) command vale "$@"; return ;; esac; '"$fake"'; }' english "$here/cases/english/pass-english.md"
  case "$fake" in
    'return 2') want "a Vale that says nothing" 0 "Vale didn't check the files of the job english: Vale failed. $fix_unknown" ;;
    echo*) want "a Vale with JSON that has no Path" 0 "Vale failed. $fix_unknown" '{"Code": "E1"}' ;;
    *) want "a Vale that fails on one file" 0 "Vale didn't check $here/cases/english/pass-english.md: the test broke. $fix_unknown" ;;
  esac
done
run_lib "$here/cases/english" 'vale() { case "$1" in ls-config) echo "A line of ls-config"; return 2 ;; esac; command vale "$@"; }' english "$here/cases/english/pass-english.md"
want "a failure of ls-config" 0 "Vale failed. $fix_unknown" "stdout:" "A line of ls-config"
# Settings with no .vale.ini of the repository give a heading with no
# settings file.
run_lib "$here/cases/english" 'vale() { case "$1" in ls-config) echo "{}"; return ;; esac; command vale "$@"; }' english "$here/cases/english/fail-english.md"
want "ls-config with no RootINI" 0 "Vale on $here/cases/english/fail-english.md:"
unwanted "ls-config with no RootINI" "with null"

# A file that the tool can't read fails with what the tool says, and the
# fix of an unknown cause. Root reads each file, so this case runs for
# another user.
if [ "$(id -u)" -ne 0 ]; then
  mkdir "$tmp/read"
  printf 'A sentence.\n' >"$tmp/read/closed.md"
  chmod 000 "$tmp/read/closed.md"
  run_in "$tmp/read" english closed.md
  want "a file that Vale can't read" 1 "grep didn't check" "closed.md: grep couldn't read the file. $fix_unknown" "Permission denied"
  run_in "$tmp/read" japanese closed.md
  want "a file that textlint can't read" 1 "closed.md: grep couldn't read the file. $fix_unknown"
  chmod 600 "$tmp/read/closed.md"
fi

# A file that Vale can't read fails, with the reason that Vale gives and the
# fix of a format, and the other files of the run keep their findings.
# reStructuredText needs rst2html, so this case runs where rst2html isn't
# installed. Vale runs again, with the output line, only on the files that
# the report of the first run doesn't name. A function named vale logs each
# run.
if ! command -v rst2html >/dev/null; then
  printf 'Title\n=====\n\nA sentence.\n' >"$tmp/case.rst"
  run_in "$here/cases/english" english "$tmp/case.rst" fail-english.md
  want "a reStructuredText file" 1 "rst2html not found; it's needed to read reStructuredText. Fix: leave each file out of the job english" "Google.Latin (error)"
  run_lib "$here/cases/english" 'log="'"$tmp/vale.log"'"; vale() { echo "vale $*" >>"$log"; command vale "$@"; }' english "$here/cases/english/fail-english.md" "$here/cases/english/pass-english.md" "$tmp/case.rst"
  out="$(cat "$tmp/vale.log")"
  want "the runs of Vale" 0 "vale --no-exit --output=line $here/cases/english/pass-english.md $tmp/case.rst"
  [ "$(grep -c "^vale --no-exit" <<<"$out")" -eq 2 ] || { echo "Failed: Vale should run twice on the files, but it ran:"; echo "$out"; failed=1; }
fi

# A file of a format that textlint doesn't read fails, with the formats
# that it reads and the fix. A Markdown file of the same run keeps its
# findings. The formats are those of the settings: a repository that
# gives the plugin of Markdown more extensions gets those checked too.
printf '# この設定は、ルートに置くものである。\n' >"$tmp/case.py"
run_in "$here/cases/japanese" japanese "$tmp/case.py" fail-japanese.md
want "a Python file" 1 "textlint didn't check $(cd -P "$tmp" && pwd)/case.py: textlint reads only the files that end in .txt, .text, .md, " "Fix: leave each file out of the job japanese" "no-mix-dearu-desumasu (error)"
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
for module in $(grep -ohE 'require\("[^"]+"\)' "$here"/../textlint/*.mjs | sed -E 's/require\("((@[^/"]+\/)?[^/"]+)[^"]*"\)/\1/' | sort -u); do
  jq -e --arg module "$module" '.dependencies | has($module)' "$here/../textlint/package.json" >/dev/null ||
    { echo "Failed: textlint/*.mjs loads $module, which textlint/package.json doesn't name."; failed=1; }
done

[ "$failed" -eq 0 ] && echo "All cases passed."
exit "$failed"
