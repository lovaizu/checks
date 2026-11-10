# Lovaizu checks

The checks that lovaizu repositories share. Each repository names this one in its `lefthook.yml`, and gets the same checks before each commit and in CI.

## What it checks

The checks are for the text that people and agents read. They stop text that falls short of the standard, so that the writer looks at it again and rewrites it for its reader.

Each language has a file and a job of its own, as which languages a repository holds, and in which files, is the case of each repository:

- `english` of `english.yml` checks the English, by [Vale](https://vale.sh) with the [Google developer documentation style](https://developers.google.com/style).
- `japanese` of `japanese.yml` checks the Japanese, by [textlint](https://textlint.org). It runs these rules:
  - [`textlint-rule-preset-ja-technical-writing`](https://github.com/textlint-ja/textlint-rule-preset-ja-technical-writing)
  - [`@textlint-ja/textlint-rule-preset-ai-writing`](https://github.com/textlint-ja/textlint-rule-preset-ai-writing)
  - [`textlint-rule-ja-hiragana-keishikimeishi`](https://github.com/lostandfound/textlint-rule-ja-hiragana-keishikimeishi), [`textlint-rule-ja-hiragana-hojodoushi`](https://github.com/lostandfound/textlint-rule-ja-hiragana-hojodoushi) and [`textlint-rule-ja-hiragana-fukushi`](https://github.com/lostandfound/textlint-rule-ja-hiragana-fukushi)
  - [`textlint-rule-ja-space-between-half-and-full-width`](https://github.com/textlint-ja/textlint-rule-ja-space-between-half-and-full-width), with `space: never`
  - [`textlint-rule-prh`](https://github.com/textlint-rule/textlint-rule-prh), when the repository names its dictionary
  - The filters [`textlint-filter-rule-allowlist`](https://github.com/textlint/textlint-filter-rule-allowlist) and [`textlint-filter-rule-comments`](https://github.com/textlint/textlint-filter-rule-comments)

Each tool reads a file as it reads the file's format, and the checks change nothing in it. Vale reads Markdown and the [other formats that it knows](https://docs.vale.sh/formats), and reads the rest as plain text. A format that needs a program that isn't installed, such as `rst2html` for reStructuredText, fails the check. textlint reads Markdown and plain text.

A finding at the level warning or error stops the commit. A finding at a lower level, suggestion in Vale and info in textlint, shows in the report and doesn't stop the commit. Each rule keeps the level that its tool gives it.

The report says what the checks are for before the findings, and again in short after them.

## Use it in a repository

Install [mise](https://mise.jdx.dev/installing-mise.html) and [lefthook](https://lefthook.dev). Then name this repository in `lefthook.yml`, at a tag, and name in `configs` the file of each language that your repository holds. Neither job has a glob of its own, so a job checks each staged file unless you give it its files with `glob` and `exclude`.

For a repository that holds only English:

```yaml
remotes:
  - git_url: https://github.com/lovaizu/checks
    ref: v0.2.0
    configs:
      - english.yml
```

For a repository that holds both languages, give each job its files, or each job checks the files of the other language too. A file that holds both languages goes to both jobs only if you give it to both. For example, for English files in the root and Japanese files in `docs/ja`:

```yaml
glob_matcher: doublestar
remotes:
  - git_url: https://github.com/lovaizu/checks
    ref: v0.2.0
    configs:
      - english.yml
      - japanese.yml

pre-commit:
  jobs:
    - name: english
      glob: "*.md"
      exclude:
        - "notes/**"
    - name: japanese
      glob: "docs/ja/**/*.md"
```

With [`glob_matcher: doublestar`](https://lefthook.dev/configuration/glob_matcher/), `*.md` matches only the files in the root, and `docs/ja/**/*.md` matches the files in `docs/ja` and below. To turn off a language, leave its file out of `configs`. The settings of the files in `configs` take precedence over those of your `lefthook.yml`, so `skip: true` on a job doesn't turn it off.

Run `lefthook install` once in each clone. In CI, add this step after `actions/checkout`, at the commit of the same tag:

```yaml
- uses: lovaizu/checks@<commit of v0.2.0>
```

The first run installs the tools of `mise.toml` with the sha256 of `mise.lock`, and textlint and its rules with the integrity of `textlint/package-lock.json`, into `~/.cache/lovaizu-checks`.

## Change a setting

Change a setting when the case of your repository needs it. The people of the repository decide it, not an agent that wants a finding to go away. Write only what you change: the checks lay your file over their defaults.

### English

Write a `.vale.ini` of your own. Vale reads [`vale/.vale.ini`](vale/.vale.ini) as its defaults, and lays over them the `.vale.ini` in the directory of each file, or in the nearest parent that has one. For example, to make a rule stop the commit, and to allow the words of your own vocabulary:

```ini
StylesPath = styles
Vocab = Team

[*]
Google.Passive = warning
```

Vale then reads `styles/config/vocabularies/Team/accept.txt`. To leave out a pattern, such as a path, name it in [`TokenIgnores`](https://vale.sh/docs/keys/tokenignores) or [`BlockIgnores`](https://vale.sh/docs/keys/blockignores). Vale applies them only to the formats of markup, such as Markdown.

### Japanese

Write a `.textlintrc` of your own, in JSON or YAML, where textlint looks for it: the root of the repository, or the field `textlint` of `package.json`. textlint reads only one settings file, so the checks merge yours into [`textlint/.textlintrc.json`](textlint/.textlintrc.json), and give textlint the result. For example, to show a rule without stopping the commit, to allow a word, and to name a dictionary of `prh`:

```yaml
rules:
  preset-ja-technical-writing:
    sentence-length:
      severity: info
  prh:
    rulePaths:
      - prh.yml
filters:
  allowlist:
    allow:
      - 御社
```

Your file changes only the part that it names:

- An object adds its keys to those of the defaults.
- `true` turns on a rule and keeps the options of the defaults, including those of a preset.
- An array adds its items to those of the defaults.
- `false`, or any other value, takes the place of the default.

A `.textlintrc.js` or `.textlintrc.cjs` fails the check, as JavaScript can't merge into the defaults. To leave out a part of a file, use the comments of `textlint-filter-rule-comments`, such as `<!-- textlint-disable -->`.

## Check other text

A repository that checks text inside another format, such as the strings of a JSON file, adds a job of its own. The job prints the text as Markdown at the line numbers of the file, and gives that file to `prose.sh english` or `prose.sh japanese`.

## Change the checks

- A tool: change its version in `mise.toml`, then run `mise lock --platform linux-x64,linux-arm64,macos-arm64,macos-x64`.
- textlint or a rule: change its version in `textlint/package.json`, then run `npm install --package-lock-only --ignore-scripts` in `textlint`.

`tests/run.sh` checks that each case in `tests/cases/english` and `tests/cases/japanese` passes, shows, or fails as its name says. `tests/consumer.sh` checks a repository that names this one, with one language and with both, with its own globs, `.vale.ini` and `.textlintrc`.
