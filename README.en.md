# Badminton Club (iPad)

[中文](README.md) | English

Fully offline badminton club app for iPad (SwiftUI). No network, no accounts — all data is stored locally. Supports multiple clubs, multiple courts, and a Chinese / English UI. Feature-complete port of the [Android version](https://github.com/doskey75506/Badminton_android).

Main features:

- **Members**: record name, gender, and initial rating
- **Tonight**: one-tap check-in; automatically generates balanced pairings for every free court (singles 1v1 / doubles 2v2)
- **Matches in progress**: substitute players mid-match, enter scores (ratings update automatically), void mistakenly generated matches
- **Four independent standings**: Open Singles / Women's Singles / Open Doubles / Women's Doubles
- **History**: filter by time range and by player; view scores and rating changes
- **Data export / import**: zip backup via the system document picker; importing **fully overwrites** this device's data (never merges)
- **Chinese / English**: switch anytime

## Requirements

- Xcode 16 or newer
- iOS 17.0+, iPad only (`TARGETED_DEVICE_FAMILY=2`, bundle id `com.badminton.club`)

## Development commands

```bash
# Core logic tests (43, run on the macOS host — no simulator needed)
swift test

# Build the app (CODE_SIGNING_ALLOWED=NO is required — no DEVELOPMENT_TEAM is set)
xcodebuild -project App/Badminton.xcodeproj -scheme Badminton \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath build CODE_SIGNING_ALLOWED=NO build
# Output: build/Build/Products/Debug-iphonesimulator/Badminton.app

# Install on the simulator (device "Badminton iPad", ID 72CE393C-DB6B-4B20-AD65-5EBCCE74B9C8)
xcrun simctl boot 72CE393C-DB6B-4B20-AD65-5EBCCE74B9C8
xcrun simctl install 72CE393C-DB6B-4B20-AD65-5EBCCE74B9C8 build/Build/Products/Debug-iphonesimulator/Badminton.app
xcrun simctl launch 72CE393C-DB6B-4B20-AD65-5EBCCE74B9C8 com.badminton.club
```

There is no lint step (no swiftformat/swiftlint in this repo); rely on `swift test` + `xcodebuild` warnings.

## Project layout

- `Package.swift` + `Sources/BadmintonKit/` — SPM package with the pure logic (models, ratings, matchmaking, storage, zip); no UIKit/SwiftUI. Unit tests live in `Tests/BadmintonTests/` (ported from the three Android `core` test suites plus a zip compatibility test)
- `App/Badminton/` — SwiftUI UI (six pages + welcome view; page switching is plain state)
- `App/Badminton.xcodeproj/` — hand-written Xcode 16 project (file-system-synchronized groups) referencing the local SPM package at `..`

## Data

- JSON in the app sandbox at `Library/Application Support/data/`: `clubs.json` plus per-club `members.json` / `attendance.json` / `settings.json` / `matches.json`
- Fully offline: no internet, no accounts; uninstalling deletes everything — use "Export data" for anything important
- Backup / new device: export to a zip, then tap "Import data" on the new device and pick that file. **Importing completely overwrites this device's data — no merging**
- The backup format matches the Android app, so both platforms can import each other's exports

## Language

Switch between 中文 / English anytime in the menu.
