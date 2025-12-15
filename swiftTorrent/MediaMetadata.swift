//
//  MediaMetadata.swift
//  swiftTorrent
//
//  Created by Max Hewett on 14/12/2025.
//

import Foundation

struct MediaMetadata: Hashable {
    enum MediaType: Hashable {
        case movie
        case show
    }

    let type: MediaType
    let title: String
    let year: Int?
    let traktID: Int?
    let tmdbID: Int?
    let imdbID: String?
    let tvdbID: Int?
    let overview: String?
    var posterURL: URL?
    var localPosterPath: URL?
    var displaySuffix: String?
}
