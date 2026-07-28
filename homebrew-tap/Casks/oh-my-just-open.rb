cask "oh-my-just-open" do
  version "1.0.0"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"

  url "https://github.com/blas0/mac-os-apps/releases/download/oh-my-just-open-v#{version}/oh-my-just-open-#{version}.dmg"
  name "oh-my-just-open"
  desc "Minimal macOS default-app manager"
  homepage "https://github.com/blas0/mac-os-apps/tree/main/oh-my-just-open"

  livecheck do
    url :url
    strategy :github_latest
  end

  app "oh-my-just-open.app"

  zap trash: [
    "~/Library/Preferences/com.neurix.oh-my-just-open.plist",
    "~/Library/Application Support/com.neurix.oh-my-just-open",
    "~/Library/Caches/com.neurix.oh-my-just-open",
  ]
end
