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
# lefthook would stash the changes below of a staged lefthook.yml, in a
# repository with no commit.
git add .vale.ini .textlintrc
expect 0 left-out.txt "Google.Latin (suggestion)" "no-mix-dearu-desumasu (info)"

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
# The Claude Code hook, run by the command of the README, in a repository
# like those of v0.2.0, with a Japanese job alone. Claude Code gives the
# hook its input on stdin and reads the JSON on stdout.
command="$(sed -n '/^```json$/,/^```$/p' "$here/README.md" | sed '1d;$d' | jq -r '.hooks.PreToolUse[0].hooks[0].command')"
[ "$(sed -n '/^```json$/,/^```$/p' "$here/README.md" | sed '1d;$d' | jq -r '.hooks.PostToolUse[0].hooks[0].command')" = "$command" ] ||
  { echo "Failed: the README should register the same command for both events."; failed=1; }
git init -q "$dir/claude"
cd "$dir/claude" || exit 1
cat >lefthook.yml <<YAML
remotes:
  - git_url: $dir/checks
    ref: test
    configs:
      - japanese.yml
pre-commit:
  jobs:
    - name: japanese
      glob: "*.md"
YAML
lefthook install >/dev/null
# Runs the hook with the input of event $1 for a tool, as jq makes it from
# the JSON $2 of the tool.
hook() {
  jq -n --arg event "$1" --arg cwd "$PWD" --argjson tool "$2" '{hook_event_name: $event, cwd: $cwd} + $tool' | bash -c "$command"
}
run=(hook PreToolUse "$(jq -n --arg c "gh pr create --title 'Add the hook' --body '$(cat "$here/tests/cases/japanese/fail-japanese.md")'" '{tool_name: "Bash", tool_input: {command: $c}}')")
expect 0 systemMessage '"permissionDecision": "deny"' "textlint on the body of gh pr create:" "no-mix-dearu-desumasu (error)"
run=(hook PreToolUse "$(jq -n --arg c "gh pr create --title 'Add the hook' --body '$(cat "$here/tests/cases/japanese/pass-japanese.md")'" '{tool_name: "Bash", tool_input: {command: $c}}')")
expect 0 "."
run=(hook PreToolUse '{"tool_name": "Bash", "tool_input": {"command": "gh issue comment 1 --body \"$text\""}}')
expect 0 deny "systemMessage" "didn't check the body of gh issue comment"
# After a Write, the hook checks the file, unless the glob leaves it out.
cp "$here/tests/cases/japanese/fail-japanese.md" guide.md
cp "$here/tests/cases/japanese/fail-japanese.md" guide.txt
run=(hook PostToolUse "$(jq -n --arg f "$PWD/guide.md" '{tool_name: "Write", tool_input: {file_path: $f}}')")
expect 0 systemMessage '"decision": "block"' "textlint on guide.md:"
run=(hook PostToolUse '{"tool_name": "Bash", "tool_input": {"command": "cat guide.md > guide.txt"}}')
expect 0 "."

# A new version in lefthook.yml alone changes the version that the hook
# runs. Before lefthook fetches it, the hook says so, and Claude Code shows
# the first line of stderr.
git -C "$dir/checks" tag next
sed -i.orig 's/ref: test/ref: next/' lefthook.yml && rm lefthook.yml.orig
run=(hook PreToolUse '{"tool_name": "Bash", "tool_input": {"command": "git commit -m \"これは文である。これは文です。\""}}')
expect 1 deny "hook claude-code doesn't exist"
lefthook install >/dev/null
[ -d "$(git rev-parse --git-path info/lefthook-remotes/checks-next)" ] || { echo "Failed: lefthook install should fetch the version next."; failed=1; }
expect 0 systemMessage '"permissionDecision": "deny"' "textlint on the commit message:"

[ "$failed" -eq 0 ] && echo "The consumer cases passed."
exit "$failed"
