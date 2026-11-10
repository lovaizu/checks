#!/bin/bash
# Runs ci.sh, as the action does, in a new repository whose lefthook.yml
# names this repository in remotes, at the commit checked out here. The
# repository gives the English and the Japanese jobs their files by glob,
# and changes the settings of the tools in their own files, which the
# checks lay over their defaults. A run that checks no file would pass, and that's what this
# test catches.
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
dir="$(mktemp -d)"
trap 'rm -rf "$dir"' EXIT
failed=0
# Fails the test when ci.sh doesn't exit $1 with each text that the rest
# names, or prints text $2, which the globs leave out.
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
# With doublestar, *.md matches the files in the root alone, and
# docs/ja/**/*.md matches the files right in docs/ja too.
cat >lefthook.yml <<YAML
glob_matcher: doublestar
remotes:
  - git_url: $dir/checks
    ref: test
    configs:
      - hooks.yml
pre-commit:
  jobs:
    - name: english
      glob: "*.md"
    - name: japanese
      glob: "docs/ja/**/*.md"
YAML
# Cases with findings, as tests/run.sh knows them, and a file that the
# globs leave out. The English README names a Japanese key, which the
# Japanese rules would read as a sentence of Japanese.
mkdir -p docs/ja
cp "$here/tests/cases/english/fail-english.md" README.md
printf '\nPress the key ⌘英かな to switch the input method to English, and press it again to go back to the Japanese input method of macOS.\n' >>README.md
cp "$here/tests/cases/japanese/fail-japanese.md" docs/ja/guide.md
cp "$here/tests/cases/english/fail-english.md" left-out.txt
git add -A
expect 1 "textlint on README.md" Google.Latin "Vale on README.md" "textlint on docs/ja/guide.md" "no-mix-dearu-desumasu (error)"
expect 1 left-out.txt
expect 1 "Vale on docs/ja/guide.md"

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
