# Template for the Homebrew cask. The release workflow fills in VERSION and SHA256 and
# pushes the result to the tap repository as Casks/devsweep.rb.
cask "devsweep" do
  version "VERSION"
  sha256 "SHA256"

  url "https://github.com/Lukitaduarte/DevSweep/releases/download/v#{version}/DevSweep-#{version}.zip",
      verified: "github.com/Lukitaduarte/DevSweep/"
  name "DevSweep"
  desc "Menu bar app that cleans developer processes and caches"
  homepage "https://github.com/Lukitaduarte/DevSweep"

  # The app updates itself through Sparkle.
  auto_updates true
  depends_on macos: ">= :sonoma"

  app "DevSweep.app"

  zap trash: [
    "~/Library/Preferences/io.github.devsweep.DevSweep.plist",
    "~/Library/Caches/io.github.devsweep.DevSweep",
    "~/Library/HTTPStorages/io.github.devsweep.DevSweep",
    "~/.config/devsweep",
  ]
end
