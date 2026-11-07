#!/bin/bash
# Runs ci.sh, as the action does, in a new repository whose lefthook.yml
# names this repository in remotes, at the commit checked out here. The
# repository has a file with a finding, so ci.sh must fail on it. A run
# that checks no file would pass, and that's what this test catches.
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
dir="$(mktemp -d)"
trap 'rm -rf "$dir"' EXIT
# lefthook fetches a remote by a branch or a tag, so this commit gets a tag
# of its own in a copy of this repository.
git clone -q "$here" "$dir/checks"
git -C "$dir/checks" checkout -q "$(git -C "$here" rev-parse HEAD)"
git -C "$dir/checks" tag test
git init -q "$dir/consumer"
cd "$dir/consumer" || exit 1
printf 'remotes:\n  - git_url: %s\n    ref: test\n    configs:\n      - hooks.yml\n' "$dir/checks" >lefthook.yml
# A case with a finding, as tests/run.sh knows it.
cp "$here/tests/cases/fail-english.md" notes.md
want=Google.Latin
git add -A
out="$(bash "$here/ci.sh" 2>&1)"
status=$?
if [ "$status" -eq 0 ] || ! grep -qF "$want" <<<"$out"; then
  echo "Failed: ci.sh should fail on notes.md with $want, but it exited $status with:"
  echo "$out"
  exit 1
fi

# With no remote, pre-commit has no job, and ci.sh must fail, not pass.
printf 'pre-commit:
  jobs: []
' >lefthook.yml
out="$(bash "$here/ci.sh" 2>&1)"
status=$?
if [ "$status" -eq 0 ] || ! grep -qF "has no job" <<<"$out"; then
  echo "Failed: ci.sh should fail on a lefthook.yml with no job, but it exited $status with:"
  echo "$out"
  exit 1
fi
echo "The consumer cases passed."
