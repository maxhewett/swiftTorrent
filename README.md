<img width="150" height="150" alt="swiftTorrent app icon" src="https://github.com/user-attachments/assets/78d3d3fa-8da2-4e8b-8d40-e1687bcbaddc" />

# swiftTorrent

swiftTorrent is a macOS torrent app focused on movie and TV workflows, with a Swift-native UI and metadata-aware torrent presentation.

![swiftTorrent screenshot](https://github.com/user-attachments/assets/9a2b06fe-6d07-4cb6-a9c2-a6c4c284b0b6)

## Features

- SwiftUI-first macOS interface with custom animations and media-centric UX.
- Sonarr and Radarr-friendly workflows.
- Category-based post-download file handling (move/copy behavior).
- Torrent name cleanup and normalization for better readability.
- Poster/title enrichment via Trakt/tvdb-style metadata sources.

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

## Language Statistics on GitHub

This repository vendors large native dependency trees under `Frameworks/`, which can skew GitHub language stats toward C/C++.

A [`.gitattributes`](/Users/max/Developer/swiftTorrent/.gitattributes) file is included to mark vendored framework files so Linguist better reflects the app's primary language (Swift).

## License

Licensed under the [GNU GPL v3.0](/Users/max/Developer/swiftTorrent/LICENSE).
