# Where setup.sh puts what the checks run, for setup.sh and lib.sh. $root is
# the root of this repository.

# The skill natural-japanese by coji, under the Massachusetts Institute of
# Technology (MIT) License, at a commit that Claude Code read in full before
# this file named it. Read a new commit in full before you name it here, as
# lovaizu/dotfiles#57 asks.
natural_japanese_sha=840bd400cbcb64c8b64d492a144da54fc05776c5
cache="${XDG_CACHE_HOME:-$HOME/.cache}/lovaizu-checks"
natural_japanese="$cache/natural-japanese-$natural_japanese_sha"
if command -v sha256sum >/dev/null; then
  requirements_sum="$(sha256sum "$root/requirements.txt")"
else
  # macOS has no sha256sum.
  requirements_sum="$(shasum -a 256 "$root/requirements.txt")"
fi
# A change to requirements.txt makes a new virtual environment.
venv="$cache/venv-${requirements_sum:0:16}"

# mise installs only what mise.lock pins, with the sha256 that it keeps, and
# reads mise.toml here without asking whether to trust it.
export MISE_LOCKED=1
export MISE_TRUSTED_CONFIG_PATHS="$root/mise.toml${MISE_TRUSTED_CONFIG_PATHS:+:$MISE_TRUSTED_CONFIG_PATHS}"
