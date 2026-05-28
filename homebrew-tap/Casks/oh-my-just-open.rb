cask "oh-my-just-open" do
  version "1.0.0"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"

  url "https://github.com/blas0/oh-my-just-open/releases/download/v#{version}/oh-my-just-open-#{version}.dmg"
  name "oh-my-just-open"
  desc "Minimal macOS default-app manager"
  homepage "https://github.com/blas0/oh-my-just-open"

  livecheck do
    url :url
    strategy :github_latest
  end

  # Auto-strip the quarantine flag so Gatekeeper doesn't block the unsigned
  # bundle on first launch. Cask installs already do this for the DMG itself;
  # this directive applies it to the .app inside as well.
  auto_updates true

  app "oh-my-just-open.app"

  zap trash: [
    "~/Library/Preferences/com.neurix.oh-my-just-open.plist",
    "~/Library/Application Support/com.neurix.oh-my-just-open",
    "~/Library/Caches/com.neurix.oh-my-just-open",
    "~/Library/Application Support/Sparkle/Updates/oh-my-just-open",
  ]
end
