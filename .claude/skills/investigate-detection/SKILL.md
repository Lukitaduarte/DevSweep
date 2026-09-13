---
name: investigate-detection
description: Explain why DevSweep does or doesn't flag a process as in limbo, doesn't find a cache, shows the wrong size, or doesn't suggest or notify something. Use for bug reports like "X isn't detected", "it wants to kill Y which I'm using", or "why is Z suggested".
---

# Investigate a detection

Everything here is read-only. Don't clean or kill anything to reproduce.

## Start with the live report

```bash
DEVSWEEP_LIVE=1 swift test --filter LiveReportTests
```

It prints the loaded stack issues, every process group with limbo counts, every storage target with size and risk, and the resulting suggestions. It also loads personal overrides from `~/.config/devsweep/stacks`, which are a common reason for "works for me" differences.

## Process not grouped, or grouped under the wrong rule

1. Get the real command line and parent:
   ```bash
   ps -axww -o pid,ppid,uid,rss,%cpu,etime,command | grep -i <name>
   lsof -nP -iTCP -sTCP:LISTEN | grep <pid>
   ```
   Matching uses the full `command` and the executable path from `proc_pidpath`. For Electron helpers and dart snapshots the executable path differs from the first word of the command.
2. Rules are tried in stack `order`, then file order, then `fallback: true` rules. The first match wins, and children of a matched process join its group unless they match a different rule themselves. Look for an earlier, broader rule that catches it first (for example `dart-other`, `local-servers`, the `script-runtime` matcher).
3. Reproduce in a unit test in `Tests/DevSweepTests/ProcessTests.swift` with `ProcInfo` fixtures. Use neutral paths (`/opt/…`, `/p/…`), never real ones from the machine.

## Wrong limbo verdict

`ProcessScanner.evaluate`:
- `orphan` → PPID == 1.
- `orphan_or_older` → orphan or `etime` > minutes.
- `idle` → `etime` > minutes and `%cpu` < max_cpu. `%cpu` is a decaying average.
- App helpers → the process lives under `Contents/Frameworks/`, its name contains "Helper", it is orphaned, and the main app isn't running.

Something legitimately parented by launchd (a login item, a daemon) should use `idle` or `never`, not `orphan`.

## Cache missing or wrong size

1. Expand the glob by hand: `ls -d ~/path/*` and check environment overrides (`echo $GOPATH`). GUI apps don't inherit the shell environment, so a `${VAR:-default}` falls back to the default.
2. Check the filters: `keep_newest`/`only_newest` with `sort_by: version` group by the extracted version (`version_pattern`), `older_than_days` uses modification time, `file_contains` reads a file relative to each match.
3. `project:` entries need the project under a folder listed in Settings → project folders, found within 4 levels, with the marker at its root. Activity comes from the modification date of git metadata, markers and `activity_files`.
4. Sizes come from `du -sk` over the resolved paths. Zero-size targets are hidden.
5. `requires_path` silently skips an entry when that path is missing.

## Not suggested or not notified

`Advisor.build`:
- Storage: `auto_suggest` must be true and size ≥ `min(suggest_above, user setting)`. Low disk lowers the bar to 500 MB.
- Limbo processes: RAM ≥ the user's limbo setting, or ≥ 2 processes, or `suggest_even_if_small`.
- In-use heavy processes: only when memory is tight.

Notifications (`AppModel.notifyIfNeeded`) have their own thresholds plus a cooldown per suggestion (3 h for processes, 24 h for disk), stored under `notifiedAt` in the app's defaults.

## Fix

Usually a YAML change: follow the `add-stack` skill. Add a regression test that fails before the fix.
