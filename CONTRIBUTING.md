# Contributing to DevSweep

Most contributions don't need Swift. What DevSweep knows about each stack lives in YAML files under [`stacks/`](stacks), and the UI translations live in [`locales/`](locales).

## Setup

```bash
swift test                                            # unit tests + validation of every stack and locale file
swift run DevSweep                                    # runs from the checkout, reading ./stacks and ./locales
make app                                              # builds build/DevSweep.app
DEVSWEEP_LIVE=1 swift test --filter LiveReportTests   # read-only report of what DevSweep finds on your Mac
```

Notifications only work from the bundled app (`make app`), not from `swift run`.

## Adding or improving a stack

1. Copy [`docs/stack-template.yaml`](docs/stack-template.yaml) to `stacks/<stack>.yaml`, or add entries to an existing file.
2. Run `swift test`. The loader rejects unknown keys (and suggests the key you probably meant), missing fields, invalid regular expressions, absolute paths and references to matchers or providers that don't exist.
3. Run the live report to check that your entries find what you expect on your machine.
4. Open a pull request.

To iterate without rebuilding, put files in `~/.config/devsweep/stacks/` and click **Settings → Stacks → Reload** in the app. Entries there override bundled entries with the same `id`, and `disabled: true` turns a bundled entry off. This is also how users customize DevSweep without forking it.

## File anatomy

```yaml
stack:      # which stack this file describes
matchers:   # optional reusable process matchers
processes:  # process rules
storage:    # things on disk that can be cleaned
```

Top-level keys starting with `x-` are ignored, which is useful for YAML anchors (see `stacks/android.yaml`).

### `stack`

| Key | Required | Description |
|---|---|---|
| `id` | yes | Unique id. Several files with the same id merge into one stack. |
| `name` | yes | [Text](#text-and-translations). |
| `icon` | no | An [SF Symbol](https://developer.apple.com/sf-symbols/) name. Tests check that it exists. Default `shippingbox`. |
| `order` | no | Lower numbers are matched and displayed first. Default `100`. |

### Text and translations

Every `name` and `description` accepts a plain English string or a map by language:

```yaml
name: Pub cache                     # same in every language
description:
  en: "Packages from pub get."
  pt-BR: "Pacotes do pub get."
  es: "Paquetes de pub get."
```

`en` is required. Missing languages fall back to English, so it's fine to contribute only English. Quote texts that contain `: ` or start with `{`.

Descriptions can use placeholders that DevSweep fills in: `{projects}`, `{project_count}` and `{inactive_days}` for [project](#project) entries, plus any variables a [provider](#providers) sets.

### `processes`

Every process of the current user is tested against the rules. **The first matching rule wins.** Rules are tried in stack `order`, then in file order; rules with `fallback: true` are tried after all others. Processes are grouped with their children, so matching the parent is enough.

| Key | Description |
|---|---|
| `id`, `name` | Required. `description` is optional. |
| `match` | Required. See [match](#match). |
| `limbo` | When a matching process counts as stuck. See [limbo](#limbo). Default `orphan`. |
| `stop` | `{ run: [[command, args…], …] }` runs before sending SIGTERM (e.g. `xcrun simctl shutdown all`). |
| `fallback` | Try this rule after all non-fallback rules. For catch-alls like "other Dart processes". |
| `suggest_even_if_small` | Suggest stopping limbo processes regardless of the user's RAM threshold (hung build scripts). |
| `suggest_when_memory_tight` | Also suggest stopping processes that are in use when memory pressure is high (simulators, emulators). |
| `disabled` | Remove the rule. Mostly used in personal overrides. |

Apps in `/Applications` and their helpers are grouped automatically, so they don't need rules.

#### `match`

All keys in a matcher must match (AND). A list matches if **any** item matches (OR). A single string is a one-item list.

| Key | Matches when |
|---|---|
| `exe_name` | The executable's file name equals one of the values. |
| `exe_name_prefix` | The executable's file name starts with one of the values. |
| `exe_path_contains` | The executable's full path contains one of the values. |
| `command_contains` | The full command line, arguments included, contains one of the values. |
| `command_prefix` | The command line starts with one of the values. |
| `has_ports` | `true`: the process listens on a TCP port. `false`: it doesn't. |
| `user_tool` | `true`: the executable is outside `/System`, `/usr/libexec` and app bundles. |
| `ref` | A named matcher from any file's `matchers`. |
| `any` / `all` / `none` | Lists of matchers: at least one, every one, or none of them must match. |

```yaml
match:
  any:
    - exe_name: esbuild
    - ref: js-runtime                       # node, bun or deno…
      command_contains: [next dev, vite]    # …running next dev or vite
```

#### `limbo`

| Value | Meaning |
|---|---|
| `orphan` | The parent that started it has exited (PPID 1). The default. |
| `{ when: orphan_or_older, minutes: 30 }` | Orphaned, or running longer than N minutes. For build steps that hang. |
| `{ when: idle, minutes: 20, max_cpu: 1 }` | Running for more than N minutes with CPU below `max_cpu`%. For daemons that are always parented by launchd. |
| `never` | Listed but never suggested. |

### `storage`

| Key | Description |
|---|---|
| `id`, `name` | Required. `description` is optional. |
| `risk` | Required. `safe`: regenerated automatically. `redownload`: comes back, but with a download. `data_loss`: user data. `data_loss` items are never cleaned in bulk and always ask for confirmation. |
| `paths` | List of [path specs](#path-specs). |
| `project` | Folders inside detected projects. See [project](#project). |
| `provider` | Name of a Swift [provider](#providers). `provider_options` passes it lists of strings. |
| `method` | `delete` (default), `trash` or `run`. |
| `run` | Commands for `method: run` (implied when `run` is present): a list of `[command, args…]`. Paths are still used to measure size. |
| `then_delete` | With `run`: also delete the paths afterwards. |
| `stop_processes` | Substrings of command lines to terminate before cleaning (daemons holding the files). |
| `auto_suggest` | `false`: only shown in the Storage tab, never suggested proactively. Default `true`. |
| `suggest_above` | Size that triggers a suggestion, like `500MB` or `2GB`. Defaults to the user's setting. |
| `requires_path` | Skip the entry unless this path exists (e.g. only when Xcode was ever used). |
| `disabled` | Remove the entry. |

At least one of `paths`, `project` or `provider` is required.

#### Path specs

A plain string is a glob. **Paths must start with `~/` or `${VAR:-~/default}`.** Absolute paths are rejected, so no one's personal machine layout ends up in the repo.

Supported syntax: `*`, `?`, `[abc]`, `{a,b}` alternatives and `${ENV_VAR:-default}`.

The object form adds filters:

| Key | Description |
|---|---|
| `glob` | Required. |
| `exclude` | File names to leave out. |
| `name_matches` | Regular expression the file name must match. |
| `older_than_days` | Only items not modified for N days. |
| `keep_newest` | Leave the N newest out (clean the old ones). |
| `only_newest` | Select only the N newest. |
| `sort_by` | `modified` (default) or `version`. With `version`, entries with the same version count as one. |
| `version_pattern` | Regular expression that extracts the version; the first capture group is used. Default: the first dotted number. |
| `file_contains` / `file_not_contains` | `{ file: .git/config, text: … }`: keep only folders whose file does or doesn't contain the text. |

```yaml
paths:
  - glob: ~/.gradle/caches/*
    name_matches: '^\d+(\.\d+)+$'
    keep_newest: 1
    sort_by: version
```

#### `project`

Projects are searched in the folders set in the app's Settings.

| Key | Description |
|---|---|
| `markers` | Required. File names that identify the project type at its root (`pubspec.yaml`, `go.mod`…). |
| `paths` | Required. Folders relative to the project root. |
| `activity` | `inactive`, `active` or `any` (default). Inactivity is set by the user (default 21 days). |
| `activity_files` | Extra files whose modification date counts as activity (lockfiles, `src`). Git metadata and markers always count. |

#### Providers

Providers are the Swift escape hatch for things globs can't express, like reading config files. They live in [`Sources/DevSweep/Storage/StorageProviders.swift`](Sources/DevSweep/Storage/StorageProviders.swift).

| Provider | Options | Variables |
|---|---|---|
| `fvm-versions` | none | `version`, `usage`. One entry per installed version. |
| `xcode-unavailable-simulators` | none | none |
| `android-unused-system-images` | `sdk` | none |
| `nvm-non-default-versions` | none | none |
| `old-installers` | `extensions`, `folders` | `count`, `days`, `trash_note` |

To add one, implement it there, add its name to `StorageProviders.names`, and cover it with a test.

## Commit messages

Releases and the changelog are generated from [Conventional Commits](https://www.conventionalcommits.org), so please use them in commit messages or PR titles (PRs are squash-merged):

| Change | Example |
|---|---|
| New detection | `feat(stacks): detect Rust target folders` |
| False positive or negative | `fix(stacks): don't flag the Flutter daemon of an open editor` |
| Translation | `feat(i18n): add French` |
| App behavior | `feat: …`, `fix: …`, `perf: …` |
| Docs, CI, tests | `docs: …`, `ci: …`, `test: …` (not listed in the changelog) |

Every pull request is reviewed automatically by CodeRabbit and a maintainer. Security-sensitive changes (deletion, killing processes, workflows) always get a human review.

## Screenshots

Screenshots show real data from your Mac. Before adding one to the repository or a PR, hide the menu bar icons of other apps and anything that names your projects, employer or private tools:

```bash
swift scripts/redact-screenshot.swift raw.png docs/images/name.png --menubar 27,50 --blur x,y,w,h --cut y0-y1
```

The [`redact-screenshots`](.claude/skills/redact-screenshots/SKILL.md) skill explains how to find the coordinates.

## Using Claude Code

[`CLAUDE.md`](CLAUDE.md) describes the architecture and the rules every change must follow. The skills in [`.claude/skills`](.claude/skills) are step-by-step guides that also work fine as plain reading: `add-stack`, `add-language`, `investigate-detection`, `redact-screenshots` and `release`.

## Guidelines

- **Be honest about risk.** If a cleanup makes the next build download things, it's `redownload`, not `safe`.
- **Commands run on other people's machines.** Stick to the stack's own official CLI (`go clean`, `brew cleanup`, `xcrun simctl`). Reviewers treat YAML commands like code.
- **No personal data.** No absolute paths, usernames, company names or private repository URLs. `swift test` fails if the repository contains your username, home folder or an email address.
- **Avoid nagging.** Pick a `suggest_above` that means "this is really worth it", and set `auto_suggest: false` for things people only clean occasionally.

## Translations

UI strings live in `locales/<code>.yaml` as flat `key: "text"` pairs. `_name` is the language's name written in that language.

To add a language:

1. Copy `locales/en.yaml` to `locales/<code>.yaml`, using codes like `fr`, `de`, `pt-PT` or `zh-Hans`.
2. Translate the values. Keep `{placeholders}` unchanged. Keys ending in `.one` are optional singular forms.
3. Optionally add `<code>:` texts to the stack files and a `Resources/<code>.lproj/InfoPlist.strings`.
4. Run `swift test`. It checks that every locale has the same keys and placeholders as English and that every key used in the code exists.

The app follows the system language, and users can switch it in Settings. Personal translations can also go in `~/.config/devsweep/locales/`.
