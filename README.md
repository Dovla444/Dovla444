# Tide

A small personal iOS/iPadOS app that keeps an Obsidian vault on the device in sync with a private GitHub repository, without Git showing up in the UI.

**Current phase: 0 (spike).** The app is a test bench, not the final UI. See [docs/PHASE0.md](docs/PHASE0.md) for the report and the device test protocol.

## Layout

| Path | What |
|---|---|
| `Config/Signing.xcconfig` | **The only file to edit:** Team ID and bundle ID prefix |
| `Config/` | Shared build settings, Info.plists, entitlements (App Group + Keychain group) |
| `Tide/` | App target |
| `TideWidgets/` | Widget (and later Control Center) extension |
| `Shared/` | Sources compiled into both app and extension (App Intents) |
| `SyncKit/` | Local Swift package: libgit2 wrapper, storage, sync engine (later), tests |
| `docs/` | Phase reports |

## Build

1. Set `DEVELOPMENT_TEAM` and `TIDE_BUNDLE_PREFIX` in `Config/Signing.xcconfig`.
2. Open `Tide.xcodeproj` in Xcode 26 and run the `Tide` scheme on a device (iOS 18+).

SyncKit tests: `cd SyncKit && swift test` (macOS, no network needed).
