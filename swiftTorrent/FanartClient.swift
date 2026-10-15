//
//  FanartClient.swift
//  swiftTorrent
//
//  Created by Max Hewett on 14/12/2025.
//

import Foundation

struct FanartClient {
    let apiKey: String

    func posterURL(for media: MediaMetadata) async throws -> URL? {
        switch media.type {
        case .movie:
            return try await moviePoster(tmdbID: media.tmdbID, imdbID: media.imdbID)
        case .show:
            return try await tvPoster(tvdbID: media.tvdbID)
        }
    }

    private func moviePoster(tmdbID: Int?, imdbID: String?) async throws -> URL? {
        let identifier: String
        if let tmdbID, tmdbID > 0 {
            identifier = String(tmdbID)
        } else if let imdbID, !imdbID.isEmpty {
            identifier = imdbID
        } else {
            return nil
        }

        let url = URL(string: "https://webservice.fanart.tv/v3/movies/\(identifier)?api_key=\(apiKey)")!
        let data = try await responseData(from: url)

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let posters = json?["movieposter"] as? [[String: Any]] ?? []
        return bestPosterURL(from: posters)
    }

    private func tvPoster(tvdbID: Int?) async throws -> URL? {
        guard let tvdbID, tvdbID > 0 else { return nil }

        let url = URL(string: "https://webservice.fanart.tv/v3/tv/\(tvdbID)?api_key=\(apiKey)")!
        let data = try await responseData(from: url)

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let posters = json?["tvposter"] as? [[String: Any]] ?? []
        return bestPosterURL(from: posters)
    }

    private func responseData(from url: URL) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let response = response as? HTTPURLResponse else { throw LookupError.invalidResponse }
        guard (200..<300).contains(response.statusCode) else {
            throw LookupError.httpStatus(response.statusCode)
        }
        return data
    }

    private func bestPosterURL(from posters: [[String: Any]]) -> URL? {
        let ranked = posters.compactMap { poster -> (URL, Int, Int)? in
            guard let urlString = poster["url"] as? String, let url = URL(string: urlString) else { return nil }
            let language = (poster["lang"] as? String ?? "").lowercased()
            let languageRank = language == "en" ? 2 : (language.isEmpty ? 1 : 0)
            let likes = Int(poster["likes"] as? String ?? "") ?? (poster["likes"] as? Int ?? 0)
            return (url, languageRank, likes)
        }
        return ranked.sorted {
            if $0.1 != $1.1 { return $0.1 > $1.1 }
            return $0.2 > $1.2
        }.first?.0
    }

    enum LookupError: LocalizedError {
        case invalidResponse
        case httpStatus(Int)

        var errorDescription: String? {
            switch self {
            case .invalidResponse: return "Fanart.tv returned an invalid HTTP response."
            case .httpStatus(let status): return "Fanart.tv returned HTTP \(status)."
            }
        }
    }
}
