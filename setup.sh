#!/bin/bash
# Installs what the checks run: the tools of mise.toml, by mise with the
# sha256 of mise.lock, and textlint and its rules, by npm with the
# integrity of textlint/package-lock.json. It does nothing more where all
# of these are already in place, so prose.sh runs it before each check.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$root/lib/paths.sh"
# A failure below that this file doesn't name has a cause that setup.sh
# doesn't know, after all that the command printed.
trap 'echo "setup.sh: a command above failed, for a cause that setup.sh doesn'"'"'t know. Fix: run $root/setup.sh again. If it still fails, report it with what it printed in an issue of $issues." >&2' ERR

if ! command -v mise >/dev/null; then
  echo "setup.sh: mise isn't installed, so it can't install the tools of the checks." >&2
  echo "  Fix: install mise as https://mise.jdx.dev/installing-mise.html says, then run $0 again." >&2
  exit 1
fi
mise -C "$root" install --quiet

if [ ! -x "$textlint_dir/node_modules/.bin/textlint" ]; then
  # npm ci installs only what package-lock.json pins, and checks each
  # package against its integrity. No package runs a script of its own.
  mkdir -p "$cache"
  part="$(mktemp -d "$cache/textlint.XXXXXX")"
  trap 'rm -rf "$part"' EXIT
  cp "$root/textlint/package.json" "$root/textlint/package-lock.json" "$part/"
  mise -C "$root" exec -- npm ci --prefix "$part" --ignore-scripts --no-audit --no-fund --loglevel=error >/dev/null
  mv "$part" "$textlint_dir"
  # Where another setup.sh put it there first, mv put this one in it.
  rm -rf "$textlint_dir/${part##*/}"
  trap - EXIT
fi
