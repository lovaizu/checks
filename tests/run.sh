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

# Prints the findings under the heading of file $2 in report $1.
findings() {
  awk -v heading="textlint on $2:" '$0 == heading { on = 1; next } on && /^$/ { exit } on' <<<"$1"
}

# A commit gives textlint all its files in one run, and each file gets the
# findings of its own.
out="$(cd "$here/cases/japanese" && "$here/../prose.sh" japanese ./* 2>&1)"
status=$?
for file in "$here"/cases/japanese/*; do
  name="${file##*/}"
  want="$(grep -m 1 -oE 'expect: [^,>]+[^ ,>-]' "$file" | sed 's/^expect: //')"
  got="$(findings "$out" "$name")"
  case "$name" in
    pass-*) [ -z "$got" ] || { echo "Failed: $name should get no finding in a run of all the Japanese cases, but got:"; echo "$got"; failed=1; } ;;
    *) grep -qF -- "$want" <<<"$got" || { echo "Failed: $name should get $want in a run of all the Japanese cases, but got:"; echo "$got"; failed=1; } ;;
  esac
done
[ "$status" -eq 1 ] || { echo "Failed: a run of all the Japanese cases should exit 1, but it exited $status."; failed=1; }

# A warning of Node on stderr is no reason to skip the check.
node_options="$(mktemp -d)"
trap 'rm -rf "$node_options"' EXIT
printf 'process.emitWarning("A warning of the test");\n' >"$node_options/warn.cjs"
out="$(cd "$here/cases/japanese" && NODE_OPTIONS="--require $node_options/warn.cjs" "$here/../prose.sh" japanese fail-japanese.md 2>&1)"
status=$?
if [ "$status" -ne 1 ] || ! grep -qF "no-mix-dearu-desumasu (error)" <<<"$out" || grep -qF "didn't check" <<<"$out"; then
  echo "Failed: fail-japanese.md should fail with its finding when Node warns, but the check exited $status with:"; echo "$out"; failed=1
fi

# A file that Vale can't read fails, with the reason that Vale gives on
# stderr. reStructuredText needs rst2html, so this case runs where rst2html
# isn't installed.
if ! command -v rst2html >/dev/null; then
  printf 'Title\n=====\n\nA sentence.\n' >"$node_options/case.rst"
  out="$("$here/../prose.sh" english "$node_options/case.rst" 2>&1)"
  status=$?
  if [ "$status" -ne 1 ] || ! grep -qF "rst2html not found" <<<"$out"; then
    echo "Failed: a reStructuredText file should fail without rst2html, but the check exited $status with:"; echo "$out"; failed=1
  fi
fi

[ "$failed" -eq 0 ] && echo "All cases passed."
exit "$failed"
