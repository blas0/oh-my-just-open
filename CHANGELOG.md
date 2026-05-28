# Changelog

All notable changes to this project are documented here. Format based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versioning follows [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added
- Ad-hoc signed DMG build pipeline (`scripts/release-unsigned.sh`).
- App Sandbox + Hardened Runtime enabled for distribution.
- Self-hosted Homebrew tap (`blas0/homebrew-omjo`); updates ship via `brew upgrade --cask`.

## [1.0.0] - 2026-05-25

### Added
- Initial public release.
- URL Schemes and File Types tabs with per-row default-app pickers.
- "All Apps" toggle to surface every claimant for a given type.
- Confirmation sheet for URL schemes and high-impact file types.
- About tab with project info and update link.
