#!/bin/bash
# Runs ci.sh, as the action does, in a new repository whose lefthook.yml
# names this repository in remotes, at the commit checked out here. The
# repository chooses the languages by the files in configs. With one
# language, its job checks each file. With both, the repository gives each
# job its files by glob. The repository changes the settings of the tools in
# their own files, which the checks lay over their defaults. A run that
# checks no file would pass, and that's what this test catches.
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
dir="$(mktemp -d)"
trap 'rm -rf "$dir"' EXIT
failed=0
# The command that expect runs: ci.sh, as the action runs it, unless a case
# names another.
run=(bash "$here/ci.sh")
# Fails the test when the command doesn't exit $1 with each text that the
# rest names, or prints a line that matches the extended regular expression
# $2, which the case leaves out.
expect() {
  local code="$1" left="$2" out status want
  shift 2
  out="$("${run[@]}" 2>&1)"
  status=$?
  for want in "$@"; do
    grep -qF -- "$want" <<<"$out" || status="$status, without $want"
  done
  grep -qE -- "$left" <<<"$out" && status="$status, with $left"
  if [ "$status" != "$code" ]; then
    echo "Failed: ${run[*]} should exit $code with $*, but it exited $status with:"
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
# Cases with findings, as tests/run.sh knows them, and a file that the
# globs leave out. The English README names a Japanese key, which the
# Japanese rules would read as a sentence of Japanese.
mkdir -p docs/ja
cp "$here/tests/cases/english/fail-english.md" README.md
printf '\nPress the key ⌘英かな to switch the input method to English, and press it again to go back to the Japanese input method of macOS.\n' >>README.md
cp "$here/tests/cases/japanese/fail-japanese.md" docs/ja/guide.md
cp "$here/tests/cases/english/fail-english.md" left-out.txt
# Files that hold no prose, which a job with no glob checks too.
cp "$here/LICENSE" "$here/mise.lock" .
git add -A

# With english.yml alone, only the English job runs, and Vale checks each
# file, the README with its Japanese key too.
cat >lefthook.yml <<YAML
remotes:
  - git_url: $dir/checks
    ref: test
    configs:
      - english.yml
YAML
expect 1 "japanese ❯" "english ❯" Google.Latin "Vale on README.md" "Vale on left-out.txt" "Vale on LICENSE" "Vale on mise.lock"
# The repository leaves out the files that hold no prose, as the README
# says.
cat >>lefthook.yml <<YAML
pre-commit:
  jobs:
    - name: english
      exclude:
        - LICENSE
        - "*.lock"
YAML
expect 1 "Vale on (LICENSE|mise.lock)" Google.Latin "Vale on README.md"

# With japanese.yml alone and no glob, each file that textlint doesn't
# read, such as lefthook.yml, fails with the formats that it reads, under
# its path in the repository. With the glob of the README, only the
# Markdown goes to textlint.
cat >lefthook.yml <<YAML
remotes:
  - git_url: $dir/checks
    ref: test
    configs:
      - japanese.yml
YAML
git add -A
expect 1 "english ❯" "japanese ❯" "textlint didn't check LICENSE, lefthook.yml, mise.lock: textlint reads only the files that end in " "Fix: leave each file out of the job japanese"
cat >>lefthook.yml <<YAML
pre-commit:
  jobs:
    - name: japanese
      glob: "*.md"
YAML
git add -A
expect 1 "didn't check" "textlint on docs/ja/guide.md:" "no-mix-dearu-desumasu (error)" "textlint on README.md:"
# The cases below change lefthook.yml, which lefthook would stash if it
# were staged, in a repository with no commit.
git rm -q --cached lefthook.yml

# With both files, the repository gives each job its files. With
# doublestar, *.md matches the files in the root alone, and
# docs/ja/**/*.md matches the files right in docs/ja too.
cat >lefthook.yml <<YAML
glob_matcher: doublestar
remotes:
  - git_url: $dir/checks
    ref: test
    configs:
      - english.yml
      - japanese.yml
pre-commit:
  jobs:
    - name: english
      glob: "*.md"
    - name: japanese
      glob: "docs/ja/**/*.md"
YAML
expect 1 "textlint on README.md" Google.Latin "Vale on README.md" "textlint on docs/ja/guide.md" "no-mix-dearu-desumasu (error)"
expect 1 left-out.txt
expect 1 "Vale on docs/ja/guide.md"

# The settings of the repository change only what they name.
printf '[*]\nGoogle.Latin = suggestion\n' >.vale.ini
printf 'rules:\n  preset-ja-technical-writing:\n    no-mix-dearu-desumasu:\n      severity: info\n' >.textlintrc
git add -A
expect 0 left-out.txt "Google.Latin (suggestion)" "no-mix-dearu-desumasu (info)"

# A rule, a preset or a filter named by its package is the same as by its
# short name: the settings merge into the defaults, and a path in them is
# read from the root of the repository.
cat >.textlintrc <<YAML
rules:
  textlint-rule-preset-ja-technical-writing:
    no-mix-dearu-desumasu: false
  textlint-rule-prh:
    rulePaths:
      - prh.yml
filters:
  textlint-filter-rule-allowlist:
    allow:
      - 設定
YAML
printf 'version: 1\nrules:\n  - expected: 最上位\n    pattern: ルート\n  - expected: 構成\n    pattern: 設定\n' >prh.yml
git add -A
expect 1 "no-mix-dearu-desumasu|=> 構成" "prh (error)" "=> 最上位"

# A staged link gets the check of the file that it points to, under the
# path of the link, though the glob of the job leaves out that file.
mkdir -p docs/en
mv README.md docs/en/guide.md
ln -s docs/en/guide.md README.md
git add -A
expect 1 "Vale on docs/en/guide.md" "Vale on README.md" "Google.Latin (suggestion)"

# With no remote, pre-commit has no job, and ci.sh must fail, not pass.
printf 'pre-commit:\n  jobs: []\n' >lefthook.yml
expect 1 left-out.txt "has no job of lovaizu/checks" "english.yml, japanese.yml, or both"
# With hooks.yml of v0.1.x in configs, which lefthook skips, and a job of
# the repository, no job of the checks runs, and ci.sh must fail too.
cat >lefthook.yml <<YAML
remotes:
  - git_url: $dir/checks
    ref: test
    configs:
      - hooks.yml
pre-commit:
  jobs:
    - name: english
      glob: "*.md"
    - name: other
      run: "true"
YAML
expect 1 left-out.txt "has no job of lovaizu/checks" "english.yml, japanese.yml, or both"
[ "$failed" -eq 0 ] && echo "The consumer cases passed."
exit "$failed"
