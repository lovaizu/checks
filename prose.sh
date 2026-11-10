#!/bin/bash
# Checks the prose of each file given. Vale checks the English with the
# Google developer documentation style, and textlint checks the Japanese.
# A finding at the level warning or error fails, and a finding at a lower
# level shows in the report. A check that can't run fails too, as it would
# let a finding through.
set -uo pipefail
here="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
"$here/setup.sh" || exit 1
. "$here/lib/lib.sh"

for file in "$@"; do
  # A link is the file that it points to, which the check reads apart.
  [ -f "$file" ] && [ ! -L "$file" ] || continue
  case "$file" in /*) ;; *) file="$PWD/$file" ;; esac
  check_prose "$file"
done

if [ "${#notes[@]}" -gt 0 ]; then
  printf 'prose.sh: %s\n' "${notes[@]}" >&2
fi
# The report says what the checks are for, before the findings and again
# after them, so that a writer rewrites each part for its reader and
# doesn't only swap the words of a finding. Issue #17 holds the reason.
if [ -n "$fails$shows" ]; then
  cat <<'EOF'
The checks found text that its reader may not understand. Each finding marks
text to rethink, not words to swap. Find what the reader needs from the
text, and rewrite the sentence or the paragraph for that. Keep each fact,
condition and example that the text holds. Don't reword a sentence only to
clear a finding: a rewrite that clears it and loses the meaning is worse
than the finding.

EOF
  if [ -n "$fails" ]; then
    echo "These findings stop the commit:"
    echo
    printf '%s' "${fails//$PWD\//}"
  fi
  if [ -n "$shows" ]; then
    echo "These findings don't stop the commit. Rethink each one too:"
    echo
    printf '%s' "${shows//$PWD\//}"
  fi
  cat <<'EOF'
Rewrite each part for its reader. Don't reword a sentence only to clear
a finding.
EOF
fi
[ -z "$fails" ] && [ "${#notes[@]}" -eq 0 ]
