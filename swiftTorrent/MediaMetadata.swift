//
//  MediaMetadata.swift
//  swiftTorrent
//
//  Created by Max Hewett on 14/12/2025.
//

import Foundation

struct MediaMetadata: Codable, Hashable {
    enum MediaType: String, Codable { case movie, show }

    let type: MediaType
    let title: String
    let year: Int?
    let traktID: Int?
    let tmdbID: Int?
    let overview: String?
    let posterURL: URL?
}
