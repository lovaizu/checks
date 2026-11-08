#!/bin/bash
# Runs prose.sh on each case of tests/cases, whose name says the result that
# the check must give: a case named pass-* has no finding, and a case named
# fail-* has the finding that its line "expect:" names. A case is a file, or
# a directory that holds one file at the path that its format needs, such
# as .github/workflows/tests.yml. The check reads a case named *-commit as
# a commit message. A check must fail where it should, or it passes
# everything.
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
failed=0
for case in "$here"/cases/*; do
  name="${case##*/}"
  file="$case"
  [ -d "$case" ] && file="$(find "$case" -type f | head -n 1)"
  # A case named *-commit is a commit message.
  flag=()
  case "$name" in *-commit) flag=(--message) ;; esac
  out="$("$here/../prose.sh" "${flag[@]}" "$file" 2>&1)"
  status=$?
  case "$name" in
    pass-*) [ "$status" -eq 0 ] || { echo "Failed: $name should pass, but the check found:"; echo "$out"; failed=1; } ;;
    fail-*)
      want="$(grep -m 1 -oE 'expect: [^ ",]+' "$file" | sed 's/^expect: //')"
      if [ "$status" -ne 1 ] || [ -z "$want" ] || ! grep -qF -- "$want" <<<"$out"; then
        echo "Failed: $name should fail with ${want:-the finding that its line expect: names}, but the check exited $status with:"; echo "$out"; failed=1
      fi
      ;;
  esac
done
[ "$failed" -eq 0 ] && echo "All cases passed."
exit "$failed"
