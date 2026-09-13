## What this changes

<!-- New stack, new rule, fix, translation… -->

## Checklist

- [ ] `swift test` passes locally
- [ ] For stack changes: ran `DEVSWEEP_LIVE=1 swift test --filter LiveReportTests` and the new entries find what I expect
- [ ] `risk` reflects what actually happens (`safe` / `redownload` / `data_loss`)
- [ ] Commands in `run:` only use the stack's official CLI
- [ ] No absolute paths, usernames, company names or private URLs
- [ ] New texts have at least `en` (other languages fall back to English)
