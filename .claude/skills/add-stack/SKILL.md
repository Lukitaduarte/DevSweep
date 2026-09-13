---
name: add-stack
description: Add or change what DevSweep detects and cleans for a developer stack (processes in limbo, caches, SDK versions, per-project build folders) by editing stacks/*.yaml. Use when asked to support a new tool, language, framework or IDE, or to fix a process or cache that is wrongly flagged or missed.
---

# Add or change a stack

Changes go in `stacks/*.yaml`. Swift is only needed for a new provider. Read the "File anatomy" section of `CONTRIBUTING.md` first; it is the schema reference.

## 1. Research before writing

- Find where the tool really keeps its data from **official docs** (cache dirs, SDK install dirs, daemons, environment variables that relocate them such as `GOPATH` or `ANDROID_HOME`).
- Classify every item honestly:
  - `safe`: regenerated with no download.
  - `redownload`: comes back, but with a download.
  - `data_loss`: anything the user could miss.
- Prefer the tool's own cleanup command (`run:`) when one exists, and keep `paths` so the size can be measured. Add `then_delete: true` only if the command leaves the folder behind.
- For processes, work out what "stuck" means:
  - Started by an editor or terminal that went away → `orphan` (the default).
  - Daemons that are always parented by launchd → `{ when: idle, minutes, max_cpu }`.
  - Build steps that hang → `{ when: orphan_or_older, minutes }`.
  - Things that should never be suggested → `never`.

It's fine to look at this machine read-only to confirm (`ls`, `du -sh`, `ps -axww -o pid,ppid,etime,command`). **Never** delete or kill anything to test.

## 2. Write the YAML

- Extend the existing file for the stack, or copy `docs/stack-template.yaml` to `stacks/<stack>.yaml` for a new one.
- `id`s must be unique within the bundled files.
- Paths must start with `~/` or `${VAR:-~/default}`. Use `{a,b}` alternatives instead of repeating lines.
- Narrow globs with `keep_newest`/`sort_by: version`, `older_than_days`, `name_matches`, `file_contains`, or use `project:` for per-project folders.
- Processes: make matchers specific. Reuse shared matchers with `ref:`. Mark broad catch-alls `fallback: true`. Order matters: first match wins.
- `suggest_above`: pick a size that is really worth an interruption. Use `auto_suggest: false` for occasional cleanups.
- Texts: `en` is required; add `pt-BR` and `es` too. Quote strings containing `: ` or starting with `{`.
- No usernames, company names or private URLs, even in comments.

## 3. Verify

```bash
swift test --filter StackDefinitionTests              # schema, unknown keys, paths, refs, icons
swift test --filter ProcessGroupingTests              # rule ordering against the real stacks
DEVSWEEP_LIVE=1 swift test --filter LiveReportTests   # what the new entries find on this Mac (read-only)
swift test                                            # everything, incl. PrivacyTests
```

- For a new or broader process rule, add a case to `Tests/DevSweepTests/ProcessTests.swift` (`ProcessGroupingTests`). It should show that the rule matches its target and does not steal a process from a more specific rule.
- If the live report shows nothing because the tool isn't installed, say so in the PR description rather than guessing.

## 4. Provider (only if YAML can't express it)

Implement it in `Sources/DevSweep/Storage/StorageProviders.swift`: add the name to `StorageProviders.names` and a case in `run`. Put user-visible text in `tr()` keys in all three locales, document it in the Providers table of `CONTRIBUTING.md`, and add a test.

## 5. Commit

`feat(stacks): <what>` for new detection, `fix(stacks): <what>` for false positives or negatives.
