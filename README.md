# Lovaizu checks

The checks that lovaizu repositories share. Each repository names this one in its `lefthook.yml`, and gets the same checks before each commit and in CI.

## What it checks

`prose.sh` checks the prose that a repository keeps, and fails on any finding:

- English, by [Vale](https://vale.sh) with the [Google developer documentation style](https://developers.google.com/style).
- Japanese, by `lint.py` of the skill [natural-japanese](https://github.com/coji/natural-japanese).

It reads all the text of each file that it gets:

- Markdown, plain text and HTML: all the text but code, as Vale reads it.
- SVG: the text that the figure shows, such as `<title>`, `<desc>` and `<text>`, but none of its markup or style.
- Code: the comments, and the messages of a shell script.
- JSON, YAML and `.toml` files: every string value, and the comments.
- Any other text file: all of it, as plain text.

It checks each commit message too, but the lines that git leaves out and the trailers, such as `Co-Authored-By`. A binary file, such as an image, holds no text to read.

## Use it in a repository

Install [mise](https://mise.jdx.dev/installing-mise.html) and [lefthook](https://lefthook.dev). Then name this repository in `lefthook.yml`, at a tag:

```yaml
remotes:
  - git_url: https://github.com/lovaizu/checks
    ref: v0.1.0
    configs:
      - hooks.yml
```

Run `lefthook install` once in each clone. In CI, add this step after `actions/checkout`, at the commit of the same tag:

```yaml
- uses: lovaizu/checks@<commit of v0.1.0>
```

The first run installs the tools of `mise.toml` with the sha256 of `mise.lock`, and natural-japanese and its Python packages into `~/.cache/lovaizu-checks`.

## Leave text out

A repository leaves out the text that it doesn't want the checks to read.

To leave out a file, name it in `exclude` of `pre-commit` in `lefthook.yml`:

```yaml
pre-commit:
  exclude:
    - "notes/**"
    - LICENSE
```

To leave out a pattern, such as a word of code, write a `.vale.ini` of your own. Vale uses it, in place of the one of the checks, for each file in its directory and below. Give it the Google style, and the pattern in [`TokenIgnores`](https://vale.sh/docs/keys/tokenignores) or [`BlockIgnores`](https://vale.sh/docs/keys/blockignores):

```ini
[*]
BasedOnStyles = Google
TokenIgnores = ubuntu-latest
```

Keep the patterns under `[*]`. The checks give Vale the string values of a file and the messages of a shell script in a Markdown file of their own, so a section for a file type doesn't apply to them. lint.py doesn't read `.vale.ini`, so leave out a file to skip its Japanese.

## Change the checks

- A tool: change its version in `mise.toml`, then run `mise lock --platform linux-x64,linux-arm64,macos-arm64,macos-x64`.
- natural-japanese: read the new commit in full, then name it in `lib/paths.sh`.
- The Python packages: see `setup.sh`.

`tests/run.sh` checks that each case in `tests/cases` passes or fails as its name says.
