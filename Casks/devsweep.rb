# Homebrew cask, served straight from this repository:
#
#   brew tap lukitaduarte/devsweep https://github.com/Lukitaduarte/DevSweep
#   brew install --cask devsweep
#
# It points at the stable "latest release" URL and lets the app update itself through
# Sparkle, so this file doesn't change from release to release.
cask "devsweep" do
  version :latest
  sha256 :no_check

  url "https://github.com/Lukitaduarte/DevSweep/releases/latest/download/DevSweep.zip",
      verified: "github.com/Lukitaduarte/DevSweep/"
  name "DevSweep"
  desc "Menu bar app that cleans developer processes and caches"
  homepage "https://github.com/Lukitaduarte/DevSweep"

  auto_updates true
  depends_on macos: :sonoma

  app "DevSweep.app"

  zap trash: [
    "~/Library/Preferences/io.github.devsweep.DevSweep.plist",
    "~/Library/Caches/io.github.devsweep.DevSweep",
    "~/Library/HTTPStorages/io.github.devsweep.DevSweep",
    "~/.config/devsweep",
  ]
end
