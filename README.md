# oh-my-just-open

A minimal macOS default-app manager. Pick which app opens which URL scheme or file type — without digging through Finder's "Get Info" panels one at a time.

## Install

**Homebrew (recommended)**

```sh
brew install --cask oh-my-just-open
```

**Direct download**

Grab the latest `.dmg` from the [Releases page](https://github.com/blas0/oh-my-just-open/releases/latest), open it, and drag the app to `/Applications`.

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
