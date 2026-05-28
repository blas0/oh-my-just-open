# oh-my-just-open

A minimal macOS default-app manager. Pick which app opens which URL scheme or file type — without digging through Finder's "Get Info" panels one at a time.

## Install

```sh
brew tap blas0/omjo
brew install --cask oh-my-just-open
```

Homebrew is the only supported install path. Updates ship via `brew upgrade --cask oh-my-just-open`.

## Use

- The **URLs** tab lists every URL scheme registered on your Mac (`http://`, `mailto:`, custom app schemes, etc.). Pick a default from any row's menu.
- The **Files** tab does the same for file types (`.pdf`, `.png`, `.txt`, …).
- The **All Apps** toggle shows every claimant for a type, not just the system-blessed list. Useful when an app claims a type but doesn't appear in the standard picker.
- Changes apply via `LaunchServices`. URL schemes and high-impact file types prompt for confirmation; other changes apply silently.

## Contributing

Bugs and feature requests welcome — open an issue or PR.

## License

MIT — see [LICENSE](./LICENSE).
