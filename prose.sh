#!/bin/bash
# Checks the prose of each file given, and fails on any finding: English by
# Vale with the Google developer documentation style, and Japanese by lint.py
# of the skill natural-japanese. It reads all the text of Markdown, plain text
# and HTML, the comments of code, the messages of shell scripts, and the
# descriptions of JSON files. It takes the paths of the files, after
# --message when they're commit messages. A check that can't run fails too,
# as it would let a finding through.
set -uo pipefail
here="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
"$here/setup.sh" || exit 1
. "$here/lib/lib.sh"

message=""
if [ "${1:-}" = --message ]; then
  message=1
  shift
fi
for file in "$@"; do
  # A link is the file that it points to, which the check reads apart.
  [ -f "$file" ] && [ ! -L "$file" ] || continue
  case "$file" in /*) ;; *) file="$PWD/$file" ;; esac
  if [ -n "$message" ]; then
    # git leaves out the lines that start with #, so the check does too. The
    # trailers of the last paragraph, such as Co-Authored-By, are fields,
    # not prose. Each line left out stays as an empty line, so that the line
    # numbers of the findings stay those of the message.
    made=$((made + 1))
    text="$work/message-$made.md"
    sed 's/^#.*//' "$file" | awk '
      { line[NR] = $0 }
      END {
        last = NR
        while (last > 0 && line[last] == "") last--
        first = last
        while (first > 0 && line[first] ~ /^[A-Za-z][A-Za-z0-9-]*: /) first--
        if (first < last && (first == 0 || line[first] == "")) for (i = first + 1; i <= last; i++) line[i] = ""
        for (i = 1; i <= NR; i++) print line[i]
      }' >"$text"
    check_english "$text" md "$(vale_config "$PWD")" null "the commit message"
    check_japanese "$text" null "the commit message"
  else
    check_prose "$file" null "$(vale_config "$(dirname "$file")")"
  fi
done

if [ "${#notes[@]}" -gt 0 ]; then
  printf 'prose.sh: %s\n' "${notes[@]}" >&2
fi
if [ -n "$report" ]; then
  printf '%s' "${report//$PWD\//}"
  exit 1
fi
[ "${#notes[@]}" -eq 0 ]
