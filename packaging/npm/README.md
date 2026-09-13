# @lukitaduarte/devsweep

Installer for [DevSweep](https://github.com/Lukitaduarte/DevSweep), a macOS menu bar app that finds developer processes stuck in limbo and the caches, builds and simulator data that Flutter, iOS, Android, Node and Go leave behind.

```bash
npx @lukitaduarte/devsweep                  # install the latest release into /Applications and launch it
npx @lukitaduarte/devsweep --version 0.2.0  # install a specific version
npx @lukitaduarte/devsweep --to ~/Applications --no-open
```

The command downloads the release from GitHub, verifies it against the SHA-256 published with it, and copies the app into place. The app keeps itself updated afterwards.

macOS only. MIT licensed.
