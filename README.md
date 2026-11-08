# Lovaizu checks

The checks that lovaizu repositories share. Each repository names this one in its `lefthook.yml`, and gets the same checks before each commit and in CI.

## What it checks

`prose.sh` checks the prose that a repository keeps, and fails on any finding:

- English, by [Vale](https://vale.sh) with the [Google developer documentation style](https://developers.google.com/style).
- Japanese, by `lint.py` of the skill [natural-japanese](https://github.com/coji/natural-japanese).

In each file, it reads only the text that the file's format holds as prose for a reader:

| Format | What it reads |
| --- | --- |
| Markdown | All the text that it shows, but code and URLs. In front matter, each string field but those that Claude Code defines as a name or a setting, such as `name`, `model` and `allowed-tools`. |
| Plain text, and any format that this table doesn't name | All of it. |
| HTML and SVG | The text that the page or the figure shows, such as `<title>`, `<desc>` and `<text>` of SVG, and `alt` text. |
| JSON, YAML and `.toml` files | Each string value, and the comments. |
| JSON Schema, named `*.schema.json` | `title`, `description` and `$comment`. |
| A GitHub workflow or action | The comments, the names, and the descriptions of the action and its inputs and outputs. The `run` of a step reads as a shell script, unless the step names another shell. |
| The settings of Claude Code and other tools: `plugin.json`, `marketplace.json`, `hooks.json`, `settings.json`, `package.json`, `pyproject.toml`, `mise.toml`, `lefthook.yml` | The comments and each `description`. |
| `.ini`, `.cfg` and `.coveragerc` files | The comments and the values. |
| `.vale.ini`, `.gitignore` and `requirements.txt` | The comments. |
| Shell scripts | The comments, and the words that `echo` and `printf` show on the terminal. |
| Python, JavaScript, CSS and the other code that Vale knows, and jq | The comments, and the docstrings of Python. |
| A chezmoi template, such as `*.tmpl` | The comments `{{/* ... */}}`, and the rest as the file that the template makes, without its actions `{{ ... }}`. |
| A file with no extension | As the program that its first line `#!` names, or as plain text. |
| A commit message | The subject and the body, but the lines that git leaves out, all below the scissors line, and the trailers, such as `Co-Authored-By`. |
| A binary file, such as an image | Nothing. |

The checks read comments and string values as Markdown, so a span in backticks reads as code. A lockfile and a license read as their format says: leave them out, as no one in the repository writes them. lovaizu/checks#12 says where each row comes from.

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

To leave out a pattern, such as a path, write a `.vale.ini` of your own. Vale uses it, in place of the one of the checks, for each file in its directory and below. Give it the Google style, and the pattern in [`TokenIgnores`](https://vale.sh/docs/keys/tokenignores) or [`BlockIgnores`](https://vale.sh/docs/keys/blockignores):

```ini
[*]
BasedOnStyles = Google
TokenIgnores = ([\w.-]+/[\w./-]+)
```

A pattern applies wherever the checks read Markdown: comments, string values and the text of a figure too. Keep the patterns under `[*]`, as the checks give Vale some of this text in a Markdown file of their own, which a section for a file type doesn't match.

A field of front matter reads as plain text, which a pattern doesn't reach. To leave out a field, name its scope in [`IgnoredScopes`](https://vale.sh/docs/keys/ignoredscopes), before the first section. It adds to the scopes that the checks leave out:

```ini
IgnoredScopes = text.frontmatter.argument-hint
```

lint.py doesn't read `.vale.ini`, so leave out a file to skip its Japanese.

## Change the checks

- A tool: change its version in `mise.toml`, then run `mise lock --platform linux-x64,linux-arm64,macos-arm64,macos-x64`.
- natural-japanese: read the new commit in full, then name it in `lib/paths.sh`.
- The Python packages: see `setup.sh`.

`tests/run.sh` checks that each case in `tests/cases` passes or fails as its name says.
