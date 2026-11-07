#!/bin/bash
# Runs prose.sh on each file of tests/cases, whose name says the result that
# the check must give: a file named pass-* has no finding, and a file named
# fail-* has the finding that its first line names. The check reads a
# file named *-commit as a commit message. A check must fail where
# it should, or it passes everything.
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
failed=0
for file in "$here"/cases/*; do
  name="${file##*/}"
  # A case named *-commit is a commit message.
  flag=()
  case "$name" in *-commit) flag=(--message) ;; esac
  out="$("$here/../prose.sh" "${flag[@]}" "$file" 2>&1)"
  status=$?
  case "$name" in
    pass-*) [ "$status" -eq 0 ] || { echo "Failed: $name should pass, but the check found:"; echo "$out"; failed=1; } ;;
    fail-*)
      want="$(head -n 1 "$file" | sed -E 's/.*expect: ([^ ]+).*/\1/')"
      if [ "$status" -ne 1 ] || ! grep -qF -- "$want" <<<"$out"; then
        echo "Failed: $name should fail with $want, but the check exited $status with:"; echo "$out"; failed=1
      fi
      ;;
  esac
done
[ "$failed" -eq 0 ] && echo "All cases passed."
exit "$failed"
