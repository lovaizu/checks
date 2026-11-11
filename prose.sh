#!/bin/bash
# Checks the prose of each file given, in the language that the first
# argument names: english, by Vale with the Google developer documentation
# style, or japanese, by textlint. The repository chooses the files of each
# language, with the glob of each job in its lefthook.yml.
# A finding at the level warning or error fails, and a finding at a lower
# level shows in the report. A check that can't run fails too, as it would
# let a finding through.
set -uo pipefail
# cd follows CDPATH for a relative path, which would lead each path below to
# another directory.
unset CDPATH
here="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
"$here/setup.sh" || exit 1
. "$here/lib/lib.sh"

language="${1:-}"
case "$language" in
  english) check=check_english ;;
  japanese) check=check_japanese ;;
  *)
    echo "prose.sh: the first argument must be english or japanese, not '${1:-}'." >&2
    exit 1
    ;;
esac
shift
# The current directory with no link in it, the root of the repository,
# where the search for settings ends.
cd -P . || exit 1
"$check" "$@"

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
    printf '%s' "$fails"
  fi
  if [ -n "$shows" ]; then
    echo "These findings don't stop the commit. Rethink each one too:"
    echo
    printf '%s' "$shows"
  fi
  cat <<'EOF'
Rewrite each part for its reader. Don't reword a sentence only to clear
a finding.
EOF
fi
[ -z "$fails" ] && [ "${#notes[@]}" -eq 0 ]
