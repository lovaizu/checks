# Lovaizu checks

The checks that lovaizu repositories share. Each repository names this one in its `lefthook.yml`, and gets the same checks before each commit and in CI.

## What it checks

`prose.sh` checks the prose that a repository keeps, and fails on any finding:

- English, by [Vale](https://vale.sh) with the [Google developer documentation style](https://developers.google.com/style).
- Japanese, by `lint.py` of the skill [natural-japanese](https://github.com/coji/natural-japanese).

It reads all the text of Markdown, plain text and HTML, the comments of code, the messages of shell scripts, and the descriptions of JSON files. It checks each commit message too.

## Use it in a repository

Install [mise](https://mise.jdx.dev/installing-mise.html) and [lefthook](https://lefthook.dev). Then name this repository in `lefthook.yml`, at a tag:

```yaml
remotes:
  - git_url: https://github.com/lovaizu/checks
    ref: v0.1.0
    configs:
      - hooks.yml

# Files that the checks leave out, such as notes that are not kept.
pre-commit:
  exclude:
    - "notes/**"
```

Run `lefthook install` once in each clone. In CI, add this step after `actions/checkout`, at the commit of the same tag:

```yaml
- uses: lovaizu/checks@<commit of v0.1.0>
```

The first run installs the tools of `mise.toml` with the sha256 of `mise.lock`, and natural-japanese and its Python packages into `~/.cache/lovaizu-checks`.

## Change the checks

- A tool: change its version in `mise.toml`, then run `mise lock --platform linux-x64,linux-arm64,macos-arm64,macos-x64`.
- natural-japanese: read the new commit in full, then name it in `lib/paths.sh`.
- The Python packages: see `setup.sh`.

`tests/run.sh` checks that each case in `tests/cases` passes or fails as its name says.
