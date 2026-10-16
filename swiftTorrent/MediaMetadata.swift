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
    var sources: Set<String> = []

    func formattedTitle(normalizingFormEncodedSpaces: Bool = false) -> String {
        Self.formattedTitle(title, year: year, normalizingFormEncodedSpaces: normalizingFormEncodedSpaces)
    }

    static func formattedTitle(_ title: String, year: Int?, normalizingFormEncodedSpaces: Bool = false) -> String {
        var base = title
        if normalizingFormEncodedSpaces {
            base = base.replacingOccurrences(of: "+", with: " ")
        }
        base = base.trimmingCharacters(in: .whitespacesAndNewlines)
        if let year {
            for suffix in [" (\(year))", " \(year)"] where base.hasSuffix(suffix) {
                base.removeLast(suffix.count)
                base = base.trimmingCharacters(in: .whitespacesAndNewlines)
                break
            }
            return "\(base) (\(year))"
        }
        return base
    }
}
