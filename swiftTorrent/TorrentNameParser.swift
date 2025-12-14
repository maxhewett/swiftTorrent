//
//  TorrentNameParser.swift
//  swiftTorrent
//
//  Created by Max Hewett on 14/12/2025.
//

import Foundation

enum TorrentNameParser {
    struct Parsed {
        let query: String
        let year: Int?
        let season: Int?
        let episode: Int?
    }

    static func parse(_ raw: String) -> Parsed {
        var s = raw

        // Normalize separators
        s = s.replacingOccurrences(of: "_", with: " ")
        s = s.replacingOccurrences(of: ".", with: " ")
        s = s.replacingOccurrences(of: "-", with: " ")
        s = s.replacingOccurrences(of: "  ", with: " ")

        // Remove bracketed groups [..] (..)
        s = stripBracketed(s)

        // Capture SxxEyy (TV)
        let se = extractSeasonEpisode(s)
        if let se {
            s = removeSeasonEpisodeTokens(from: s)
        }

        // Capture year (movies often)
        let year = extractYear(s)
        if let year {
            // remove the year token from query
            s = s.replacingOccurrences(of: "\(year)", with: " ")
        }

        // Remove common release/junk tokens
        s = removeJunkTokens(from: s)

        // Collapse whitespace
        s = s.split(whereSeparator: \.isWhitespace).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)

        // If we ended up empty, fall back to raw
        if s.isEmpty { s = raw }

        return Parsed(query: s, year: year, season: se?.season, episode: se?.episode)
    }

    // MARK: - Helpers

    private static func stripBracketed(_ input: String) -> String {
        var out = input

        // remove [ ... ]
        out = out.replacingOccurrences(of: #"\[[^\]]*\]"#, with: " ", options: .regularExpression)
        // remove ( ... )
        out = out.replacingOccurrences(of: #"\([^\)]*\)"#, with: " ", options: .regularExpression)

        return out
    }

    private static func extractYear(_ input: String) -> Int? {
        // Matches 19xx or 20xx
        let pattern = #"\b(19[0-9]{2}|20[0-9]{2})\b"#
        guard let r = input.range(of: pattern, options: .regularExpression) else { return nil }
        return Int(input[r])
    }

    private static func extractSeasonEpisode(_ input: String) -> (season: Int, episode: Int)? {
        // S01E02 / s1e2
        let pattern = #"\b[Ss](\d{1,2})[Ee](\d{1,2})\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = input as NSString
        guard let match = regex.firstMatch(in: input, range: NSRange(location: 0, length: ns.length)) else { return nil }
        let season = Int(ns.substring(with: match.range(at: 1))) ?? 0
        let episode = Int(ns.substring(with: match.range(at: 2))) ?? 0
        return (season, episode)
    }

    private static func removeSeasonEpisodeTokens(from input: String) -> String {
        // remove SxxEyy patterns
        input.replacingOccurrences(of: #"\b[Ss]\d{1,2}[Ee]\d{1,2}\b"#, with: " ", options: .regularExpression)
    }

    private static func removeJunkTokens(from input: String) -> String {
        var s = input

        // Common junk tokens (case-insensitive)
        let junk = [
            "1080p","720p","2160p","4k","hdr","dv","dovi",
            "x264","x265","h264","h265","hevc","avc",
            "aac","ac3","eac3","dts","truehd","atmos",
            "web","webrip","webdl","web-dl","bluray","bdrip","dvdrip","remux",
            "proper","repack","rerip","limited","internal","readnfo",
            "yts","rarbg",
            "extended","uncut",
            "multisub","subbed","subs","dubbed",
            "complete","season","episode",
            "torrent","mp4","mkv"
        ]

        for token in junk {
            s = s.replacingOccurrences(of: #"\b\#(token)\b"#,
                                       with: " ",
                                       options: [.regularExpression, .caseInsensitive])
        }

        // remove leftover empty punctuation-ish sequences
        s = s.replacingOccurrences(of: #"[^A-Za-z0-9\s']"#, with: " ", options: .regularExpression)

        return s
    }
}
