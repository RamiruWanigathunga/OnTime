# Contributing to OnTime

Thanks for your interest in contributing. Whether you are fixing a bug,
improving docs, or proposing a feature, help is welcome.

## Code of Conduct

This project is governed by our [Code of Conduct](CODE_OF_CONDUCT.md). By
participating, you agree to follow it.

## How to Contribute

### 1. Reporting Bugs

Check existing issues first. When filing a bug, include:

- **macOS version** (e.g. macOS 14.5 / 15.x / 26.x)
- **OnTime version** (About pane) or commit hash if building from source
- **Steps to reproduce**
- **Expected vs actual** behavior
- Screenshots or Console logs when useful

### 2. Suggesting Features

Open an issue with a clear title, the use case, and why it helps menu-bar timer
users. Mockups or short clips help.

### 3. Pull Requests

1. Fork the repository and branch from `main`:

   ```bash
   git checkout -b feature/my-change
   ```

2. Follow the coding guidelines below.
3. Build and run tests locally (see below).
4. Open a PR against `main` with a concise description of **why**.

## Local Development

### Prerequisites

- macOS 14.0+
- Xcode 15+ (Xcode 16 / 26 recommended)
- Command Line Tools

### Build & run

```bash
# From the repository root (the folder that contains OnTime.xcodeproj)
xcodebuild -project OnTime.xcodeproj -scheme OnTime -destination 'platform=macOS' build
```

Or open `OnTime.xcodeproj` in Xcode, select the **OnTime** scheme, and run
(Cmd+R).

### Tests

```bash
xcodebuild test -project OnTime.xcodeproj -scheme OnTime -destination 'platform=macOS'
```

> **Note:** Host-based tests require matching code signing Team IDs between the
> app and the test bundle. Prefer running tests from Xcode with your Personal
> Team selected if CLI signing fails with “different Team IDs”.

## Project Structure

- `OnTime/` — macOS app sources (SwiftUI + AppKit menu bar)
- `OnTimeTests/` — XCTest suite
- `OnTime.xcodeproj` — Xcode project (SPM: KeyboardShortcuts, Sparkle)
- `scripts/` — packaging helpers (e.g. DMG)
- `appcast.xml` — Sparkle update feed (empty until the first public ZIP)
- `images/` — README screenshots

## Coding Guidelines

- Prefer clear Swift over cleverness; match existing file style.
- Keep menu-bar and Settings behavior aligned with macOS conventions unless a
  deviation is intentional and documented.
- No network tracking; session logs stay local (JSONL under Application Support).
- Do not commit secrets, Sparkle private keys, or personal signing material.

## License & Contribution Ownership

By contributing (pull requests, patches, or issues), you agree that:

1. Your contributions are governed by the project’s
   [PolyForm Shield License 1.0.0](LICENSE).
2. You grant Ramiru Wanigathunga an irrevocable, worldwide, royalty-free license
   to use, modify, distribute, re-license, and include your contributions in
   OnTime while preserving sole ownership of the software by the Licensor.
