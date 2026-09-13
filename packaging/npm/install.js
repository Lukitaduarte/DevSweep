#!/usr/bin/env node
// Downloads a DevSweep release, checks it against the SHA-256 published with it, and
// installs the app. Run with `npx devsweep`.
//
//   npx devsweep                 install the latest release into /Applications
//   npx devsweep --version 0.2.0 install a specific version
//   npx devsweep --to ~/Applications
//   npx devsweep --no-open       don't launch the app afterwards
"use strict";

const { createHash } = require("node:crypto");
const { execFileSync } = require("node:child_process");
const { mkdtemp, mkdir, rm, writeFile, readdir } = require("node:fs/promises");
const { existsSync } = require("node:fs");
const { tmpdir, homedir } = require("node:os");
const { join } = require("node:path");

const REPOSITORY = "Lukitaduarte/DevSweep";

function parseArguments(argv) {
  const options = { destination: "/Applications", open: true, version: null };
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (argument === "--version" || argument === "-v") {
      options.version = argv[++index];
    } else if (argument === "--to") {
      options.destination = argv[++index].replace(/^~(?=$|\/)/, homedir());
    } else if (argument === "--no-open") {
      options.open = false;
    } else if (argument === "--help" || argument === "-h") {
      options.help = true;
    } else {
      throw new Error(`unknown option: ${argument}`);
    }
  }
  return options;
}

async function fetchRelease(version) {
  const url = version
    ? `https://api.github.com/repos/${REPOSITORY}/releases/tags/v${version}`
    : `https://api.github.com/repos/${REPOSITORY}/releases/latest`;
  const response = await fetch(url, { headers: { accept: "application/vnd.github+json" } });
  if (!response.ok) {
    throw new Error(`cannot read the release (${response.status}). Is the version right?`);
  }
  return response.json();
}

async function download(url) {
  const response = await fetch(url, { redirect: "follow" });
  if (!response.ok) {
    throw new Error(`download failed (${response.status}): ${url}`);
  }
  return Buffer.from(await response.arrayBuffer());
}

async function main() {
  const options = parseArguments(process.argv.slice(2));
  if (options.help) {
    console.log("usage: npx devsweep [--version x.y.z] [--to /Applications] [--no-open]");
    return;
  }
  if (process.platform !== "darwin") {
    throw new Error("DevSweep is a macOS app.");
  }

  const release = await fetchRelease(options.version);
  const asset = release.assets.find((item) => /^DevSweep-.*\.zip$/.test(item.name));
  if (!asset) {
    throw new Error(`release ${release.tag_name} has no app attached yet.`);
  }
  const checksumAsset = release.assets.find((item) => item.name === `${asset.name}.sha256`);

  console.log(`Downloading DevSweep ${release.tag_name}…`);
  const archive = await download(asset.browser_download_url);

  if (!checksumAsset) {
    throw new Error(
      `release ${release.tag_name} has no ${asset.name}.sha256 file, so the download can't be verified. ` +
        "Install another version, or download it from the releases page if you know what you're doing."
    );
  }
  const expected = (await download(checksumAsset.browser_download_url)).toString().trim().split(/\s+/)[0];
  const actual = createHash("sha256").update(archive).digest("hex");
  if (expected !== actual) {
    throw new Error(`checksum mismatch: expected ${expected}, got ${actual}`);
  }
  console.log("Checksum verified.");

  const workingDirectory = await mkdtemp(join(tmpdir(), "devsweep-"));
  try {
    const archivePath = join(workingDirectory, asset.name);
    await writeFile(archivePath, archive);
    execFileSync("/usr/bin/ditto", ["-x", "-k", archivePath, workingDirectory]);

    const app = (await readdir(workingDirectory)).find((name) => name.endsWith(".app"));
    if (!app) {
      throw new Error("the archive did not contain an app.");
    }
    const target = join(options.destination, app);
    if (existsSync(target)) {
      console.log(`Replacing ${target}…`);
      try {
        execFileSync("/usr/bin/pkill", ["-x", "DevSweep"], { stdio: "ignore" });
      } catch {
        // Not running, nothing to stop.
      }
      await rm(target, { recursive: true, force: true });
    }
    // Without this, copying into a folder that doesn't exist yet would turn the folder
    // itself into the app bundle.
    await mkdir(options.destination, { recursive: true });
    execFileSync("/bin/cp", ["-R", join(workingDirectory, app), options.destination]);
    console.log(`Installed ${target}`);

    if (options.open) {
      execFileSync("/usr/bin/open", [target]);
      console.log("DevSweep is now in your menu bar.");
    }
  } finally {
    await rm(workingDirectory, { recursive: true, force: true });
  }
}

main().catch((error) => {
  console.error(`devsweep: ${error.message}`);
  process.exit(1);
});
