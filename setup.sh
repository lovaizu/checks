#!/bin/bash
# Installs what the checks run: the tools of mise.toml, by mise with the
# sha256 of mise.lock, textlint and its rules, by npm with the integrity
# of textlint/package-lock.json, the skill natural-japanese at the commit
# that lib/paths.sh pins, and the Python packages of lint.py, from
# requirements.txt with their sha256. It does nothing more where all of
# these are already in place, so prose.sh runs it before each check.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$root/lib/paths.sh"

if ! command -v mise >/dev/null; then
  echo "setup.sh: mise isn't installed, so it can't install the tools of the checks." >&2
  echo "  Fix: install mise as https://mise.jdx.dev/installing-mise.html says, then run $0 again." >&2
  exit 1
fi
mise -C "$root" install --quiet

mkdir -p "$cache"
if [ ! -d "$natural_japanese" ]; then
  # git checks the content against the commit's hash. A GitHub source
  # archive isn't used, as GitHub doesn't promise that its bytes stay the same.
  part="$(mktemp -d "$cache/natural-japanese.XXXXXX")"
  trap 'rm -rf "$part"' EXIT
  git -C "$part" init -q
  git -C "$part" fetch -q --depth 1 https://github.com/coji/natural-japanese.git "$natural_japanese_sha"
  git -C "$part" checkout -q FETCH_HEAD
  mv "$part" "$natural_japanese"
  trap - EXIT
fi

if [ ! -x "$textlint_dir/node_modules/.bin/textlint" ]; then
  # npm ci installs only what package-lock.json pins, and checks each
  # package against its integrity. No package runs a script of its own.
  part="$(mktemp -d "$cache/textlint.XXXXXX")"
  trap 'rm -rf "$part"' EXIT
  cp "$root/textlint/package.json" "$root/textlint/package-lock.json" "$part/"
  mise -C "$root" exec -- npm ci --prefix "$part" --ignore-scripts --no-audit --no-fund --loglevel=error >/dev/null
  mv "$part" "$textlint_dir"
  trap - EXIT
fi

if [ ! -x "$venv/bin/python" ]; then
  # To update requirements.txt, run in this directory:
  # uv pip compile --generate-hashes --python-version 3.10 --universal --no-header requirements.in -o requirements.txt
  mise -C "$root" exec -- uv venv -q --python '>=3.10' "$venv.part"
  VIRTUAL_ENV="$venv.part" mise -C "$root" exec -- uv pip install -q --require-hashes -r "$root/requirements.txt"
  mv "$venv.part" "$venv"
fi
