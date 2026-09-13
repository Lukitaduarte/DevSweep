---
name: redact-screenshots
description: Prepare screenshots of DevSweep for the README, docs or a pull request by hiding the menu bar icons of other apps and any personal process names, paths, ports or project names. Use whenever an image is about to be added to the repository.
---

# Redact screenshots

Screenshots of DevSweep show real data from the contributor's Mac. Nothing personal may be committed: other apps' menu bar icons, the clock, process or project names that reveal employers or private tools, local ports, paths with usernames.

## 1. Look at each image

Open every image (for Claude: use the Read tool on the file) and list what must go:

- The menu bar: everything except the DevSweep icon on the left.
- Rows naming private tools, company projects or internal services.
- Ports, PIDs, paths with a username, project names in descriptions ("Used by acme-app").
- Content of other windows showing through the translucent popover.

Crop and zoom to get exact pixel coordinates (top-left origin), e.g.:

```bash
sips -c 110 474 --cropOffset 200 0 in.png --out /tmp/zoom.png && sips -z 330 1422 /tmp/zoom.png
```

`sips` ignores `--cropOffset 0 0`; use a height-only crop from the top instead. Divide zoomed coordinates by the zoom factor. Screenshots of a Retina display are usually 2x, so check the pixel size with `sips -g pixelWidth -g pixelHeight`.

## 2. Redact

```bash
swift scripts/redact-screenshot.swift in.png docs/images/<name>.png \
  --menubar 27,50 \            # blur the top 27 px except the first 50 px (the DevSweep icon); double both on 2x images
  --blur 164,423,76,18 \       # pixelate and blur a rectangle: x,y,w,h
  --cut 224-283                # remove a whole row: from its top to the top of the next card
```

- Prefer `--cut` for entire list rows: the list closes up and nobody can tell something was there.
- Use `--blur` for small inline values (ports, numbers inside a row you keep).
- All coordinates refer to the original image; blurs are applied before cuts.

## 3. Verify and clean up

- Read the output images again and zoom into every redacted area. Blurred text must be unreadable, and cuts must not leave half a card.
- Move the raw screenshots out of the repository, e.g. to the Trash with `osascript -e 'tell application "Finder" to delete POSIX file "/abs/path.png"'`. `.gitignore` blocks common raw screenshot names in the root, but don't rely on it.
- Run `swift test --filter PrivacyTests`. It can't read images, so step 3's visual check is what protects you.
