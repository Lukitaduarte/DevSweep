---
name: add-language
description: Add a new UI language to DevSweep or update translations in locales/*.yaml and the texts of stacks/*.yaml. Use when asked to translate the app, fix a translation, or add strings for new UI.
---

# Add or update a language

## New language

1. Pick the locale code the system uses in `Locale.preferredLanguages`: `fr`, `de`, `it`, `ja`, `pt-PT`, `zh-Hans`… The file name is the code.
2. Copy `locales/en.yaml` to `locales/<code>.yaml` and set `_name` to the language's own name (`Français`, `Deutsch`).
3. Translate every value:
   - Keep `{placeholders}` exactly.
   - Keep leading and trailing spaces in values such as `list.and_separator` and `provider.installers.trash_note`.
   - Keep the double quotes around values.
   - Keys ending in `.one` are optional singular forms; drop them or add more if the language needs them.
   - Match the tone of `en.yaml`: short, plain, no exclamation marks.
   - Keep technical terms that developers use untranslated (cache, build, limbo, daemon, DerivedData…) when that's the common usage in that language.
4. Optional:
   - Add `<code>:` texts next to `en` in `stacks/*.yaml` names and descriptions (anything missing falls back to English).
   - Add `Resources/<code>.lproj/InfoPlist.strings` with `NSAppleEventsUsageDescription`.

## New strings for new UI

Add the key to **all** locale files in the same position (sections mirror `en.yaml`), then use `tr("key")` or `tr("key", count: n)` in Swift. Never build keys dynamically; `LocalizationTests` finds keys by scanning for literal `tr("…")` calls.

## Verify

```bash
swift test --filter LocalizationTests   # same keys and placeholders as en.yaml, every key used in Sources exists
make app && open build/DevSweep.app     # then Settings → Language to eyeball it
```

Check that long translations don't truncate in the 470 pt wide popover (tabs, footer button, settings rows).

Commit: `feat(i18n): add <Language>` or `fix(i18n): …`.
