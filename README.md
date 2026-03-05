<img width="150" height="150" alt="swiftTorrent app icon" src="https://github.com/user-attachments/assets/78d3d3fa-8da2-4e8b-8d40-e1687bcbaddc" />

# swiftTorrent

[![Status](https://img.shields.io/badge/status-active-success)](https://github.com/maxhewett/swiftTorrent)
[![Platform](https://img.shields.io/badge/platform-macOS-blue)](https://www.apple.com/macos/)
[![Apple%20Silicon](https://img.shields.io/badge/arch-Apple%20Silicon-black)](https://developer.apple.com/documentation/apple-silicon)
[![Swift](https://img.shields.io/badge/swift-5.0-orange)](https://www.swift.org/)
[![License: GPL%20v3](https://img.shields.io/badge/license-GPLv3-blue.svg)](/Users/max/Developer/swiftTorrent/LICENSE)

swiftTorrent is a macOS torrent app focused on movie and TV workflows, with a Swift-native UI and metadata-aware torrent presentation.

## Features

- SwiftUI-first macOS interface with custom animations and media-centric UX.
- Sonarr and Radarr-friendly workflows.
- Category-based post-download file handling (move/copy behavior).
- Torrent name cleanup and normalization for better readability.
- Poster/title enrichment via Trakt/tvdb-style metadata sources.

## Screenshots

### Main App
<img width="80% " height="auto" alt="stnewscreenshot" src="https://github.com/user-attachments/assets/1ecd78da-b74b-4767-a33f-d2389cee7004" />

### WebUI
<img width="80%" height="auto" alt="stwebui" src="https://github.com/user-attachments/assets/3fb104c6-d3f6-40bb-9add-13641fb136dd" />

## Tech Stack

- Primary language: **Swift**
- UI: **SwiftUI**
- Core engine bridge: **Objective-C++** (`TorrentCore`)
- Torrent backend: **libtorrent-rasterbar** (bundled dynamic libraries)
- Additional bundled native dependencies: **Boost**, **OpenSSL**

## Platform Support

- macOS (Apple Silicon)

> The project is currently built for Apple Silicon only.

## Getting Started

### Requirements

- macOS with Xcode installed
- Apple Silicon Mac

### Build and Run

1. Open [`swiftTorrent.xcodeproj`](/Users/max/Developer/swiftTorrent/swiftTorrent.xcodeproj) in Xcode.
2. Select the `swiftTorrent` scheme.
3. Build and run from Xcode.

## Repository Layout

- [`swiftTorrent/`](/Users/max/Developer/swiftTorrent/swiftTorrent) - SwiftUI app source code.
- [`TorrentCore/`](/Users/max/Developer/swiftTorrent/TorrentCore) - Native bridge framework for torrent engine integration.
- [`Frameworks/`](/Users/max/Developer/swiftTorrent/Frameworks) - Bundled third-party native libraries and headers.

## Sparkle Channels

- Stable appcast: `https://maxhewett.github.io/swiftTorrent/appcast.xml`
- Beta appcast: `https://maxhewett.github.io/swiftTorrent/beta/appcast.xml`
- In-app opt-in: `Settings > General > Updates > Update Channel`
- Publish beta release/appcast: `scripts/publish_sparkle_release.sh <version> <app-or-zip> [notes] --channel beta`

## License

Licensed under the [GNU GPL v3.0](/Users/max/Developer/swiftTorrent/LICENSE).
