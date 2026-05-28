# homebrew-tap (skeleton)

This directory is the template for a separate, self-hosted Homebrew tap repo
that lives at **`github.com/blas0/homebrew-omjo`** (not in this repo).

Why a self-hosted tap instead of the official `homebrew/cask`:
the app ships ad-hoc signed without Apple notarization, and the official
cask repo rejects un-notarized apps. A user-tap has no such review gate.

## One-time setup (do this once, after the first release exists)

```sh
# 1. Create the public tap repo on GitHub.
gh repo create blas0/homebrew-omjo --public --description "Homebrew tap for oh-my-just-open"

# 2. Clone it next to this repo.
cd "$REPO_PARENT"   # parent dir where you keep checkouts
git clone git@github.com:blas0/homebrew-omjo.git
cd homebrew-omjo

# 3. Seed it from this skeleton.
mkdir -p Casks
cp "$APP_REPO_ROOT/homebrew-tap/Casks/oh-my-just-open.rb" Casks/
cp "$APP_REPO_ROOT/homebrew-tap/README.md" README.md  # then edit for the tap repo

# 4. Fill in real version + sha256 for the first release (see below), commit, push.
git add . && git commit -m "Add oh-my-just-open cask v1.0.0" && git push
```

End-user install once the tap is live:

```sh
brew tap blas0/omjo
brew install --cask oh-my-just-open
```

## Per-release update flow

After each `./scripts/release-unsigned.sh` run that produces a new DMG:

```sh
# 1. Get the new version and sha256 from the release output.
VERSION=1.0.1
SHA256=$(shasum -a 256 "$APP_REPO_ROOT/dist/oh-my-just-open-${VERSION}.dmg" | awk '{print $1}')

# 2. Update the cask file in the tap repo.
cd "$TAP_REPO_ROOT"
sed -i '' "s/version \".*\"/version \"${VERSION}\"/" Casks/oh-my-just-open.rb
sed -i '' "s/sha256 \"[a-f0-9]*\"/sha256 \"${SHA256}\"/" Casks/oh-my-just-open.rb

# 3. Verify locally before pushing.
brew audit --cask Casks/oh-my-just-open.rb
brew install --cask --force ./Casks/oh-my-just-open.rb

# 4. Commit + push.
git add Casks/oh-my-just-open.rb
git commit -m "oh-my-just-open ${VERSION}"
git push
```

## Notes on the cask

- No `auto_updates` directive: updates ship via `brew upgrade --cask
  oh-my-just-open`, not via an in-app updater.
- `livecheck` with `:github_latest` lets `brew bump-cask-pr`-style automation
  notice new GitHub releases.
- `zap` cleans the app's prefs/support/cache dirs so `brew uninstall
  --cask --zap` actually leaves no trace.
- No `depends_on macos:` clause is set here; the cask template includes
  one for macOS 26+ (`>= :tahoe`). Add it here too if you want brew to
  refuse install on older macOS.
