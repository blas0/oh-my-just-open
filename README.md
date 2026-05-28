# oh-my-just-open

A minimal macOS default-app manager. Pick which app opens which URL scheme or file type — without digging through Finder's "Get Info" panels one at a time.

## Install

**Homebrew (recommended)**

```sh
brew tap blas0/omjo
brew install --cask oh-my-just-open
```

Brew handles macOS's quarantine flag for you — no first-launch friction.

**Direct download**

Grab the latest `.dmg` directly: [oh-my-just-open-latest.dmg](https://pub-06563b7bc8e246b69c21fe5af1f67b88.r2.dev/releases/oh-my-just-open-latest.dmg). Drag the app to `/Applications`.

Because the build is ad-hoc signed (no Apple Developer Program subscription backing it), macOS will refuse to open it on first launch with *"can't be opened because Apple cannot check it for malicious software."* Clear the quarantine flag once and you're done:

```sh
xattr -dr com.apple.quarantine /Applications/oh-my-just-open.app
```

Or right-click the app → **Open** → **Open Anyway** in the dialog. Future launches and Sparkle auto-updates work normally.

Per-version downloads and release notes are also on the [Releases page](https://github.com/blas0/oh-my-just-open/releases).

## Use

- The **URLs** tab lists every URL scheme registered on your Mac (`http://`, `mailto:`, custom app schemes, etc.). Pick a default from any row's menu.
- The **Files** tab does the same for file types (`.pdf`, `.png`, `.txt`, …).
- The **All Apps** toggle shows every claimant for a type, not just the system-blessed list. Useful when an app claims a type but doesn't appear in the standard picker.
- Changes apply via `LaunchServices`. URL schemes and high-impact file types prompt for confirmation; other changes apply silently.

In-app updates are handled by [Sparkle](https://sparkle-project.org/) — the app checks for new versions automatically and offers to install them.

## Build from source

Requires Xcode 16+ and macOS 26 SDK.

```sh
git clone https://github.com/blas0/oh-my-just-open.git
cd oh-my-just-open
xcodebuild -project oh-my-just-open.xcodeproj -scheme oh-my-just-open -configuration Debug build
```

Or open `oh-my-just-open.xcodeproj` in Xcode and run.

## Contributing

Bugs and feature requests welcome — open an issue or PR.

## License

MIT — see [LICENSE](./LICENSE).
