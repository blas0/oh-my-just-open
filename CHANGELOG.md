# Changelog

All notable changes to this project are documented here. Format based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versioning follows [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added
- Sparkle 2 in-app updates (EdDSA-signed, sandboxed XPC installer).
- Developer ID signing + notarization pipeline (`scripts/release.sh`).
- App Sandbox + Hardened Runtime enabled for distribution.
- Cloudflare R2 hosting for DMG, Sparkle ZIP, and appcast feed.
- Homebrew Cask template (`scripts/oh-my-just-open.rb.template`).

## [1.0.0] - 2026-05-25

### Added
- Initial public release.
- URL Schemes and File Types tabs with per-row default-app pickers.
- "All Apps" toggle to surface every claimant for a given type.
- Confirmation sheet for URL schemes and high-impact file types.
- About tab with project info and update link.
