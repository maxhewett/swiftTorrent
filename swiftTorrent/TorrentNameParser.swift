//
//  TorrentNameParser.swift
//  swiftTorrent
//
//  Created by Max Hewett on 14/12/2025.
//

import Foundation

enum TorrentNameParser {

    struct Parsed: Hashable {
        let query: String
        let year: Int?
        let season: Int?
        let episode: Int?
        let isComplete: Bool

        var suffix: String? {
            if isComplete { return "Complete" }
            if let s = season, let e = episode { return String(format: "S%02dE%02d", s, e) }
            if let s = season { return String(format: "S%02d", s) }
            return nil
        }
    }

    static func parse(_ name: String) -> Parsed {
        let cleaned = normalizeSeparators(name)
        let lower = cleaned.lowercased()

        let rawYear = firstMatchInt(lower, pattern: #"\b(19\d{2}|20\d{2})\b"#)

        let currentYear = Calendar.current.component(.year, from: Date())
        let year: Int? = {
            guard let y = rawYear else { return nil }
            guard y >= 1950 && y <= (currentYear + 1) else { return nil }
            return y
        }()

        // Completion-ish flags (packs / full seasons / collections)
        let isComplete =
            lower.contains("complete") ||
            lower.contains("season pack") ||
            lower.contains("full season") ||
            lower.contains("全集") ||
            lower.contains("collection") ||
            containsSeasonRange(lower) ||
            containsMultiSeasonToken(lower)

        // --- Season / Episode detection ---
        var season: Int? = nil
        var episode: Int? = nil

        if let (s, e) = firstMatchInts(lower, pattern: #"\bs(\d{1,2})\s*e(\d{1,3})\b"#, options: [.caseInsensitive]) {
            season = s
            episode = e
        } else if let (s, e) = firstMatchInts(lower, pattern: #"\b(\d{1,2})\s*x\s*(\d{1,3})\b"#, options: [.caseInsensitive]) {
            season = s
            episode = e
        } else {
            // Season pack formats (no single episode)
            season =
                firstMatchInt(lower, pattern: #"\bseason\s*(\d{1,2})\b"#, options: [.caseInsensitive]) ??
                firstMatchInt(lower, pattern: #"\bseries\s*(\d{1,2})\b"#, options: [.caseInsensitive]) ??
                // IMPORTANT: keep this bounded with word boundary so it doesn't hit x265 etc.
                firstMatchInt(lower, pattern: #"\bs(\d{1,2})\b"#, options: [.caseInsensitive])

            episode = nil
        }

        // If it looks like a multi-episode pack (E01-E10 / E01E02 / etc), don’t show episode.
        if containsEpisodeRange(lower) || containsMultiEpisodeToken(lower) {
            episode = nil
        }

        // If it's a "complete" pack / multi-season pack, don't show a single episode either.
        if isComplete {
            episode = nil
        }

        // Build query: remove common junk + season/episode/year tokens
        var q = cleaned

        // Remove year (only if plausible)
        if let y = year {
            q = stripRegex(q, #"(?<!\d)\#(y)(?!\d)"#) // exact year token
        }

        // Remove season/episode markers
        q = stripRegex(q, #"\bS\d{1,2}\s*E\d{1,3}\b"#, options: [.caseInsensitive])
        q = stripRegex(q, #"\b\d{1,2}\s*x\s*\d{1,3}\b"#, options: [.caseInsensitive])

        // Remove season-only markers (keep boundaries!)
        q = stripRegex(q, #"\bS\d{1,2}\b"#, options: [.caseInsensitive])
        q = stripRegex(q, #"\bSeason\s*\d{1,2}\b"#, options: [.caseInsensitive])
        q = stripRegex(q, #"\bSeries\s*\d{1,2}\b"#, options: [.caseInsensitive])

        // Remove obvious pack ranges that shouldn’t influence the title
        q = stripRegex(q, #"\bS\d{1,2}\s*-\s*S\d{1,2}\b"#, options: [.caseInsensitive])
        q = stripRegex(q, #"\bSeason\s*\d{1,2}\s*-\s*\d{1,2}\b"#, options: [.caseInsensitive])

        // Remove common tags (rough) — plus numeric-ish codec tokens
        q = stripRegex(q, #"\b(480p|720p|1080p|2160p|4k|hdr|sdr|dv|dolby|vision|x264|x265|h264|h265|hevc|avc|webrip|web\-dl|webdl|bluray|bdrip|dvdrip|hdrip|cam|ts|tc|aac|ac3|dts|truehd|atmos|remux|repack|proper|extended|unrated|rarbg|yts|eztv)\b"#, options: [.caseInsensitive])

        q = q.replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // If query ended up empty, fallback to cleaned original
        let finalQuery = q.isEmpty ? cleaned : q

        return Parsed(
            query: finalQuery,
            year: year,
            season: season,
            episode: episode,
            isComplete: isComplete
        )
    }

    // MARK: - Helpers

    private static func normalizeSeparators(_ s: String) -> String {
        s.replacingOccurrences(of: ".", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "[", with: " ")
            .replacingOccurrences(of: "]", with: " ")
            .replacingOccurrences(of: "(", with: " ")
            .replacingOccurrences(of: ")", with: " ")
            .replacingOccurrences(of: "{", with: " ")
            .replacingOccurrences(of: "}", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func firstPlausibleYear(_ s: String, min: Int, max: Int) -> Int? {
        // Find any 4-digit number, then validate range.
        guard let re = try? NSRegularExpression(pattern: #"\b(\d{4})\b"#) else { return nil }
        let range = NSRange(s.startIndex..<s.endIndex, in: s)
        let matches = re.matches(in: s, range: range)

        for m in matches {
            guard m.numberOfRanges >= 2, let rr = Range(m.range(at: 1), in: s) else { continue }
            if let y = Int(s[rr]), (min...max).contains(y) {
                return y
            }
        }
        return nil
    }

    private static func firstMatchInt(_ s: String, pattern: String, options: NSRegularExpression.Options = []) -> Int? {
        guard let r = try? NSRegularExpression(pattern: pattern, options: options) else { return nil }
        let range = NSRange(s.startIndex..<s.endIndex, in: s)
        guard let m = r.firstMatch(in: s, range: range), m.numberOfRanges >= 2,
              let rr = Range(m.range(at: 1), in: s) else { return nil }
        return Int(s[rr])
    }

    private static func firstMatchInts(_ s: String, pattern: String, options: NSRegularExpression.Options = []) -> (Int, Int)? {
        guard let r = try? NSRegularExpression(pattern: pattern, options: options) else { return nil }
        let range = NSRange(s.startIndex..<s.endIndex, in: s)
        guard let m = r.firstMatch(in: s, range: range), m.numberOfRanges >= 3,
              let r1 = Range(m.range(at: 1), in: s),
              let r2 = Range(m.range(at: 2), in: s),
              let a = Int(s[r1]), let b = Int(s[r2]) else { return nil }
        return (a, b)
    }

    private static func stripRegex(_ s: String, _ pattern: String, options: NSRegularExpression.Options = []) -> String {
        guard let r = try? NSRegularExpression(pattern: pattern, options: options) else { return s }
        let range = NSRange(s.startIndex..<s.endIndex, in: s)
        let out = r.stringByReplacingMatches(in: s, range: range, withTemplate: " ")
        return out.replacingOccurrences(of: "  ", with: " ")
    }

    private static func containsEpisodeRange(_ lower: String) -> Bool {
        (try? NSRegularExpression(pattern: #"\be(\d{1,3})\s*-\s*e(\d{1,3})\b"#, options: [.caseInsensitive]))
            .map { re in
                re.firstMatch(in: lower, range: NSRange(lower.startIndex..<lower.endIndex, in: lower)) != nil
            } ?? false
    }

    private static func containsMultiEpisodeToken(_ lower: String) -> Bool {
        // e.g. "E01E02" / "E01 E02"
        (try? NSRegularExpression(pattern: #"\be\d{1,3}\s*e\d{1,3}\b"#, options: [.caseInsensitive]))
            .map { re in
                re.firstMatch(in: lower, range: NSRange(lower.startIndex..<lower.endIndex, in: lower)) != nil
            } ?? false
    }

    private static func containsSeasonRange(_ lower: String) -> Bool {
        // S01-S03 / Season 1-3
        (try? NSRegularExpression(pattern: #"\b(s\d{1,2}\s*-\s*s\d{1,2}|season\s*\d{1,2}\s*-\s*\d{1,2})\b"#, options: [.caseInsensitive]))
            .map { re in
                re.firstMatch(in: lower, range: NSRange(lower.startIndex..<lower.endIndex, in: lower)) != nil
            } ?? false
    }

    private static func containsMultiSeasonToken(_ lower: String) -> Bool {
        // "seasons 1 2 3" / "seasons 1-3" / "season 1-5"
        (try? NSRegularExpression(pattern: #"\bseasons?\s*\d{1,2}(\s*[-,]\s*\d{1,2}|\s+\d{1,2})+\b"#, options: [.caseInsensitive]))
            .map { re in
                re.firstMatch(in: lower, range: NSRange(lower.startIndex..<lower.endIndex, in: lower)) != nil
            } ?? false
    }
}
