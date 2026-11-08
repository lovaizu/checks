#!/bin/bash -e (e.g.)
# shellcheck disable=SC2086 (e.g.)
# Writes the settings of the tools.
x="e.g. this; that"
grep -q "e.g. this; that" "$x" || true
echo "export X=1; e.g." >>"$HOME/.profile"
printf '%s\n' "e.g. this; that" >"$x"
echo "Wrote the settings."
printf '\033]0;%s: %s\007' "$x" "$PWD"
printf 'Wrote %.1s.\n' "$x"
#
# x
