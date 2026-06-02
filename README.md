<img width="150" height="150" alt="swiftTorrent icon" src="https://github.com/user-attachments/assets/2c91bada-00ff-4b38-b124-3ad611b99843" />


# swiftTorrent

[![Status](https://img.shields.io/badge/status-active-success)](https://github.com/maxhewett/swiftTorrent)
[![Platform](https://img.shields.io/badge/platform-macOS-blue)](https://www.apple.com/macos/)
[![Apple%20Silicon](https://img.shields.io/badge/arch-Apple%20Silicon-black)](https://developer.apple.com/documentation/apple-silicon)
[![Swift](https://img.shields.io/badge/swift-5.0-orange)](https://www.swift.org/)
[![License: GPL%20v3](https://img.shields.io/badge/license-GPLv3-blue.svg)](/Users/max/Developer/swiftTorrent/LICENSE)

swiftTorrent is a macOS torrent app focused on movie and TV workflows, with a Swift-native UI and metadata-aware torrent presentation.

## Features

- SwiftUI-first macOS interface with a media-centric UX.
- Sonarr and Radarr-friendly workflows.
- Category-based post-download file handling (move/copy behavior).
- Torrent name cleanup and normalization for better readability.
- Poster/title enrichment via Trakt/tvdb-style metadata sources.

## Screenshots

<img width="50%" height="auto" alt="swiftTorrent 2026-06-02 21 53 29" src="https://github.com/user-attachments/assets/6c56add9-9d4a-4c13-bb1e-7b352e5290e0" /><img width="50%" height="auto" alt="swiftTorrent 2026-06-02 21 53 39" src="https://github.com/user-attachments/assets/40b10a92-1a78-4da2-85c7-172dd979d7ad" />
<img width="50%" height="auto" alt="swiftTorrent 2026-06-02 21 54 07" src="https://github.com/user-attachments/assets/c84e2053-ce9b-4677-b372-dd2ce51971d4" /><img width="50%" height="auto" alt="swiftTorrent 2026-06-02 21 53 48" src="https://github.com/user-attachments/assets/e62f9d07-1d53-4709-aa68-dc502506d7cb" />




## Tech Stack

- Primary language: **Swift**
- UI: **SwiftUI**
- Core engine bridge: **Objective-C++** (`TorrentCore`)
- Torrent backend: **libtorrent-rasterbar** (bundled dynamic libraries)
- Additional bundled native dependencies: **Boost**, **OpenSSL**

## Platform Support

- macOS (Apple Silicon)

> The project is currently built for Apple Silicon only.

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
