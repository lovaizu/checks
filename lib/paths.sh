# Where setup.sh puts what the checks run, for setup.sh and lib.sh, and
# where to report a failure that they don't know the cause of. $root is the
# root of this repository.
issues=https://github.com/lovaizu/checks/issues
cache="${XDG_CACHE_HOME:-$HOME/.cache}/lovaizu-checks"
# textlint and its rules, and a new directory for each change of the
# lockfile, which pins each package with its integrity.
if command -v sha256sum >/dev/null; then
  textlint_sum="$(sha256sum "$root/textlint/package-lock.json")"
else
  # macOS has no sha256sum.
  textlint_sum="$(shasum -a 256 "$root/textlint/package-lock.json")"
fi
textlint_dir="$cache/textlint-${textlint_sum:0:16}"

# mise installs only what mise.lock pins, with the sha256 that it keeps, and
# reads mise.toml here without asking whether to trust it.
export MISE_LOCKED=1
export MISE_TRUSTED_CONFIG_PATHS="$root/mise.toml${MISE_TRUSTED_CONFIG_PATHS:+:$MISE_TRUSTED_CONFIG_PATHS}"
