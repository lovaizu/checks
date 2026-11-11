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
  - `ja-no-unneeded-comma` of these checks, in [`textlint/unneeded-comma.mjs`](textlint/unneeded-comma.mjs). It finds the comma `、` after the clause at the head of a sentence, where the clause can modify only one part of the rest. By default, the clause has at most 30 characters, and the sentence at most 60. The options `maxHead` and `maxSentence` change these.
  - [`textlint-rule-prh`](https://github.com/textlint-rule/textlint-rule-prh), when the repository names its dictionary
  - The filters [`textlint-filter-rule-allowlist`](https://github.com/textlint/textlint-filter-rule-allowlist) and [`textlint-filter-rule-comments`](https://github.com/textlint/textlint-filter-rule-comments)

Each tool reads a file in the format that its extension names. textlint reads Markdown and plain text, and a file of another format fails the check, with the extensions that textlint reads, so give the job `japanese` only those files. The checks read text in UTF-8 alone. A file in another encoding fails the check. A file with a null byte, such as an image, holds no text, so it passes. A check that a tool fails to run fails too, with all that the tool printed.

A finding at the level warning or error stops the commit. A finding at a lower level, suggestion in Vale and info in textlint, shows in the report and doesn't stop the commit. Each rule keeps the level that its tool gives it.

The report says what the checks are for before the findings, and again in short after them.

## Use it in a repository

Install [mise](https://mise.jdx.dev/installing-mise.html) and [lefthook](https://lefthook.dev). Then name this repository in `lefthook.yml`, at a tag, and name in `configs` the file of each language that your repository holds. Neither job has a glob of its own, so a job checks each staged file unless you give it its files with `glob` and `exclude`.

For a repository that holds only English, the job checks each staged file, including the files that hold no prose, such as `LICENSE` and a lockfile, and their findings stop the commit. Leave those files out with `exclude`. Which files to leave out is the case of your repository. For example:

```yaml
remotes:
  - git_url: https://github.com/lovaizu/checks
    ref: v0.2.0
    configs:
      - english.yml

pre-commit:
  jobs:
    - name: english
      exclude:
        - LICENSE
        - "*.lock"
```

For a repository that holds only Japanese, give the job only the files of a format that textlint reads, such as Markdown. Each other file that you stage, such as `lefthook.yml` and `.textlintrc`, fails the check. For example:

```yaml
remotes:
  - git_url: https://github.com/lovaizu/checks
    ref: v0.2.0
    configs:
      - japanese.yml

pre-commit:
  jobs:
    - name: japanese
      glob: "*.md"
```

With the default glob matcher of lefthook, `*.md` matches a Markdown file in any directory.

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

From v0.1.x, write `english.yml`, `japanese.yml`, or both in `configs` in place of `hooks.yml`. lefthook skips a file of `configs` that doesn't exist and says nothing, and `ci.sh` fails when no job of these checks remains.

Run `lefthook install` once in each clone. In CI, add this step after `actions/checkout`, at the commit of the same tag:

```yaml
- uses: lovaizu/checks@<commit of v0.2.0>
```

The first run installs the tools of `mise.toml` with the sha256 of `mise.lock`, and textlint and its rules with the integrity of `textlint/package-lock.json`, into `~/.cache/lovaizu-checks`.

## Change a setting

Change a setting when the case of your repository needs it. The people of the repository decide it, not an agent that wants a finding to go away. Write only what you change: the checks lay your file over their defaults. The checks find the settings of each file from the directory of the file up to the root of the repository, and no further. So a settings file applies to each file in its directory and below, and a file with none gets the defaults alone. To leave out a file, use `exclude` of its job in `lefthook.yml`.

### English

Write a `.vale.ini` of your own. Vale reads [`vale/.vale.ini`](vale/.vale.ini) as its defaults, and lays over them the nearest `.vale.ini`, `_vale.ini` or `vale.ini`. For example, to make a rule stop the commit, and to allow the words of your own vocabulary:

```ini
StylesPath = styles
Vocab = Team

[*]
Google.Passive = warning
```

Vale then reads `styles/config/vocabularies/Team/accept.txt`. To leave out a pattern, such as a path, name it in [`TokenIgnores`](https://vale.sh/docs/keys/tokenignores) or [`BlockIgnores`](https://vale.sh/docs/keys/blockignores). Vale applies them only to the formats of markup, such as Markdown.

### Japanese

Write a `.textlintrc` of your own, in JSON or YAML, or the field `textlint` of `package.json`. textlint reads only one settings file, so the checks merge yours into [`textlint/.textlintrc.json`](textlint/.textlintrc.json), and give textlint the result. For example, to show a rule without stopping the commit, to allow a word, and to name a dictionary of `prh`:

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

- An object adds its keys to those of the defaults, and each value of a key that both have merges the same way.
- A key with no value, such as `rules:` with nothing under it, changes nothing.
- `true` turns on a rule and keeps the options of the defaults, including those of a preset.
- An array adds its items to those of the defaults.
- `false`, or any other value, takes the place of the default.
- A rule, a preset or a filter is the same by its short name, such as `prh`, and by the name of its package, such as `textlint-rule-prh`.
- The checks read a path in the options of `prh` and `allowlist` from the directory of your file.

A `.textlintrc.js` or `.textlintrc.cjs` fails the check, as JavaScript can't merge into the defaults. To leave out a part of a file, use the comments of `textlint-filter-rule-comments`, such as `<!-- textlint-disable -->`.

## Change the checks

- A tool: change its version in `mise.toml`, then run `mise lock --platform linux-x64,linux-arm64,macos-arm64,macos-x64`.
- textlint or a rule: change its version in `textlint/package.json`, then run `npm install --package-lock-only --ignore-scripts` in `textlint`.

`tests/run.sh` checks that each case in `tests/cases/english` and `tests/cases/japanese` passes, shows, or fails as its name says, and checks each thing that the checks must do with one case. `tests/consumer.sh` checks a repository that names this one, with one language and with both, with its own globs, `.vale.ini` and `.textlintrc`.
