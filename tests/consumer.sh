#!/bin/bash
# Runs ci.sh, as the action does, in a new repository whose lefthook.yml
# names this repository in remotes, at the commit checked out here. The
# repository chooses the files to check by glob, and changes the settings
# of the tools in their own files, which the checks lay over their
# defaults. A run that checks no file would pass, and that's what this
# test catches.
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
dir="$(mktemp -d)"
trap 'rm -rf "$dir"' EXIT
failed=0
# Fails the test when ci.sh doesn't exit $1 with each text that the rest
# names, or prints text $2 that the glob leaves out.
expect() {
  local code="$1" left="$2" out status want
  shift 2
  out="$(bash "$here/ci.sh" 2>&1)"
  status=$?
  for want in "$@"; do
    grep -qF -- "$want" <<<"$out" || status="$status, without $want"
  done
  grep -qF -- "$left" <<<"$out" && status="$status, with $left"
  if [ "$status" != "$code" ]; then
    echo "Failed: ci.sh should exit $code with $*, but it exited $status with:"
    echo "$out"
    failed=1
  fi
}

# lefthook fetches a remote by a branch or a tag, so this commit gets a tag
# of its own in a copy of this repository.
git clone -q "$here" "$dir/checks"
git -C "$dir/checks" checkout -q "$(git -C "$here" rev-parse HEAD)"
git -C "$dir/checks" tag test
git init -q "$dir/consumer"
cd "$dir/consumer" || exit 1
cat >lefthook.yml <<YAML
remotes:
  - git_url: $dir/checks
    ref: test
    configs:
      - hooks.yml
pre-commit:
  jobs:
    - name: prose
      glob: "*.md"
YAML
# Cases with findings, as tests/run.sh knows them, and a file that the
# glob leaves out.
cp "$here/tests/cases/fail-english.md" english.md
cp "$here/tests/cases/fail-japanese.md" japanese.md
cp "$here/tests/cases/fail-english.md" left-out.txt
git add -A
expect 1 left-out.txt Google.Latin "no-mix-dearu-desumasu (error)"

# The settings of the repository change only what they name.
printf '[*]\nGoogle.Latin = suggestion\n' >.vale.ini
printf 'rules:\n  preset-ja-technical-writing:\n    no-mix-dearu-desumasu:\n      severity: info\n' >.textlintrc
git add -A
expect 0 left-out.txt "Google.Latin (suggestion)" "no-mix-dearu-desumasu (info)"

# With no remote, pre-commit has no job, and ci.sh must fail, not pass.
printf 'pre-commit:\n  jobs: []\n' >lefthook.yml
expect 1 left-out.txt "has no job"
[ "$failed" -eq 0 ] && echo "The consumer cases passed."
exit "$failed"
