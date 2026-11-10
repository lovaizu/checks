#!/bin/bash
# The checks that the action runs on every file of the repository in the
# current directory. lefthook fetches the remotes of lefthook.yml only when
# it installs the hooks, so ci.sh installs them first. A run with no job
# would pass and check nothing, so ci.sh fails when pre-commit has no job.
set -euo pipefail
lefthook install
jobs="$(lefthook dump --format json | jq '.["pre-commit"].jobs // [] | length')"
if [ "$jobs" -eq 0 ]; then
  echo "ci.sh: the pre-commit hook of lefthook.yml has no job, so ci.sh would check nothing." >&2
  echo "  Fix: name lovaizu/checks in the remotes of lefthook.yml, with english.yml, japanese.yml, or both in configs." >&2
  exit 1
fi
lefthook run pre-commit --all-files --no-auto-install
