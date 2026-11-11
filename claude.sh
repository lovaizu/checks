#!/bin/bash
# The Claude Code hook of the checks, which lefthook runs as the job
# claude-code, with the input of Claude Code on stdin. A repository runs it
# by `lefthook run claude-code` in its .claude/settings.json, so lefthook
# runs this script at the version that lefthook.yml names.
#
# Before a Bash command, the hook checks the texts that the command would
# keep and that no commit hook sees: the message of a `git commit`, and the
# title, body or comment of a `gh issue` or `gh pr` command. Such a text has
# no path, so each job of these checks in lefthook.yml checks it, with the
# settings of the root of the repository. When the check finds a problem,
# the command doesn't run.
# After Claude Code writes a file, the hook checks it with the jobs of
# these checks, through lefthook, so that the globs and excludes of the
# repository apply.
# The findings go back to Claude Code, so that it rethinks the text. What
# the hook can't check, it says. It prints only the JSON that Claude Code
# reads, and exits 0 unless it can't print that JSON.
set -uo pipefail
unset CDPATH
here="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
input="$(cat)"
# Most commands keep no text and write no file, so the hook doesn't read
# them further. The input is JSON, so a quote can come before a name.
case "$input" in
  *'"PreToolUse"'*) grep -qE '(^|[^[:alnum:]_-])(git|gh)([^[:alnum:]_-]|$)' <<<"$input" || exit 0 ;;
  *'"tool_name":"Bash"'* | *'"tool_name": "Bash"'*) grep -qE '>|(^|[^[:alnum:]_-])tee([^[:alnum:]_-]|$)' <<<"$input" || exit 0 ;;
esac
# Without jq, the hook can't print its JSON, so it fails, and Claude Code
# shows the first line of stderr.
"$here/setup.sh" >&2 || exit 1
eval "$(MISE_LOCKED=1 MISE_TRUSTED_CONFIG_PATHS="$here/mise.toml" mise -C "$here" env -s bash)"

# lefthook runs the job in the root of the repository.
root="$(pwd -P)"
event="$(jq -r '.hook_event_name // empty' <<<"$input")"
cwd="$(jq -r '.cwd // empty' <<<"$input")"
[ -d "$cwd" ] || cwd="$root"
fails=""
shows=""
notes=()
work=""
trap '[ -z "$work" ] || rm -rf "$work"' EXIT

# Prints the result as the JSON of a hook of event $event. $1 says what the
# findings are in, and $2 what Claude Code does next.
answer() {
  local note=""
  [ "${#notes[@]}" -gt 0 ] && note="lovaizu/checks: ${notes[*]}"
  jq -n --arg event "$event" --arg fails "$fails" --arg shows "$shows" --arg note "$note" \
    --arg what "$1" --arg next "$2" '
    ([if $fails != "" then "The checks found these problems in \($what). \($next)\n\n\($fails)" else empty end,
      if $shows != "" then "The checks found these in \($what), which don'"'"'t stop it. Rethink each one too.\n\n\($shows)" else empty end,
      if $note != "" then $note else empty end] | join("\n\n")) as $context |
    (if $fails != "" and $event == "PreToolUse" then
      {hookSpecificOutput: {hookEventName: $event, permissionDecision: "deny", permissionDecisionReason: $context}}
    elif $fails != "" then {decision: "block", reason: $context}
    elif $context != "" then {hookSpecificOutput: {hookEventName: $event, additionalContext: $context}}
    else empty end)
    + (if $note != "" then {systemMessage: $note} else {} end)'
}

# The jobs of these checks in the pre-commit hook of the repository, the
# jobs that run prose.sh. The name of each is the language that it checks.
mapfile -t jobs < <(lefthook dump --format json 2>/dev/null | jq -r '.["pre-commit"].jobs // [] | .[] | select(.script == "prose.sh") | .name')
if [ "${#jobs[@]}" -eq 0 ]; then
  notes+=("The pre-commit hook of lefthook.yml in $root has no job of these checks, so the hook checked nothing. Fix: name english.yml, japanese.yml, or both in configs.")
  answer "" ""
  exit 0
fi

# Adds output $2 of a check that exited $1 to $fails or $shows.
add() {
  [ -n "$2" ] || return 0
  if [ "$1" -eq 0 ]; then shows+="$2"$'\n\n'; else fails+="$2"$'\n\n'; fi
}

if [ "$event" = PreToolUse ]; then
  command="$(jq -r '.tool_input.command // empty' <<<"$input")"
  # shfmt parses the command as Bash does, here-documents and quotes too,
  # without running any of it. A command that it can't parse fails in Bash
  # too, so the hook doesn't check it.
  texts="$(shfmt --to-json <<<"$command" 2>/dev/null | jq -c -f "$here/lib/command-texts.jq" 2>/dev/null)" || exit 0
  # prose.sh reads a file from the root, as each file gets the settings
  # from its directory up to the root, so the copies go in a directory of
  # the root.
  i=0
  files=()
  whats=()
  while IFS= read -r item; do
    [ -n "$item" ] || continue
    what="$(jq -r .what <<<"$item")"
    file="$(jq -r '.file // empty' <<<"$item")"
    if [ -n "$file" ]; then
      case "$file" in /*) ;; *) file="$cwd/$file" ;; esac
      if [ ! -f "$file" ]; then
        notes+=("The hook didn't check $what, as $file isn't there before the command runs.")
        continue
      fi
    elif jq -e '.text == null' <<<"$item" >/dev/null; then
      notes+=("The hook didn't check $what, as the command makes it when it runs, such as from a variable. Write the text in the command, or in a file that exists before it runs.")
      continue
    fi
    [ -n "$work" ] || work="$(mktemp -d "$root/.claude-code.XXXXXX")" || exit 1
    i=$((i + 1))
    # A title and a commit message are plain text, and GitHub reads a body
    # or a comment as Markdown.
    case "$what" in "the body of"* | "the comment of"*) ext=md ;; *) ext=txt ;; esac
    path="${work#"$root/"}/text-$i.$ext"
    if [ -n "$file" ]; then cp "$file" "$root/$path"; else jq -j .text <<<"$item" >"$root/$path"; fi
    files+=("$path")
    whats+=("$what")
  done < <(jq -c '.[] | select(has("name") | not)' <<<"$texts")
  if [ "${#files[@]}" -gt 0 ]; then
    for job in "${jobs[@]}"; do
      out="$("$here/prose.sh" "$job" "${files[@]}" 2>&1)"
      status=$?
      for i in "${!files[@]}"; do out="${out//"${files[$i]}"/"${whats[$i]}"}"; done
      add "$status" "$out"
    done
  fi
  answer "the text that this command would keep, so the command didn't run" \
    "Rethink the text, then run the command again. The line numbers count from the first line of each text."
  exit 0
fi

# PostToolUse: the file of a Write or an Edit, or each file that a Bash
# command wrote by a redirect or by tee.
if [ "$(jq -r '.tool_name' <<<"$input")" = Bash ]; then
  command="$(jq -r '.tool_input.command // empty' <<<"$input")"
  written="$(shfmt --to-json <<<"$command" 2>/dev/null | jq -r -f "$here/lib/command-texts.jq" 2>/dev/null | jq -r '.[] | .name // empty')" || exit 0
else
  written="$(jq -r '.tool_input.file_path // empty' <<<"$input")"
fi
# lefthook matches its globs and excludes on the path from the root. A file
# outside the repository isn't its text, so the hook leaves it.
paths=()
while IFS= read -r file; do
  [ -n "$file" ] || continue
  case "$file" in /*) ;; *) file="$cwd/$file" ;; esac
  [ -f "$file" ] || continue
  dir="$(cd "$(dirname "$file")" && pwd -P)" || continue
  case "$dir/" in "$root/"*) ;; *) continue ;; esac
  path="${dir#"$root"}/${file##*/}"
  paths+=("${path#/}")
done <<<"$written"
[ "${#paths[@]}" -gt 0 ] || exit 0
args=()
for job in "${jobs[@]}"; do args+=(--job "$job"); done
for path in "${paths[@]}"; do args+=(--file "$path"); done
out="$(LEFTHOOK_OUTPUT=execution_out lefthook run pre-commit --no-auto-install --no-tty --colors off "${args[@]}" 2>&1)"
status=$?
# The globs and excludes of the repository leave out each file.
[ "$status" -ne 0 ] && grep -q '^Error: .*no job matching' <<<"$out" && exit 0
# lefthook adds a line of its own with the exit status.
add "$status" "$(grep -vE '^exit status [0-9]+$' <<<"$out" | sed -e :a -e '/^\n*$/{$d;N;ba' -e '}')"
answer "${paths[*]}" "Rethink each one in the file before you go on."
exit 0
