#!/bin/bash
# Runs prose.sh on each case of tests/cases, whose name says the result that
# the check must give: a case named pass-* has no finding, a case named
# show-* passes with the finding that its line "expect:" names, and a case
# named fail-* fails with that finding. A check must fail where it should,
# or it passes everything.
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
failed=0
for file in "$here"/cases/*; do
  name="${file##*/}"
  out="$("$here/../prose.sh" "$file" 2>&1)"
  status=$?
  want="$(grep -m 1 -oE 'expect: [^,>]+[^ ,>-]' "$file" | sed 's/^expect: //')"
  case "$name" in
    pass-*)
      if [ "$status" -ne 0 ] || [ -n "$out" ]; then
        echo "Failed: $name should pass with no finding, but the check exited $status with:"; echo "$out"; failed=1
      fi
      ;;
    show-* | fail-*)
      code=1
      [ "${name%%-*}" = show ] && code=0
      if [ "$status" -ne "$code" ] || [ -z "$want" ] || ! grep -qF -- "$want" <<<"$out"; then
        echo "Failed: $name should exit $code with ${want:-the finding that its line expect: names}, but the check exited $status with:"; echo "$out"; failed=1
      fi
      ;;
  esac
done
[ "$failed" -eq 0 ] && echo "All cases passed."
exit "$failed"
