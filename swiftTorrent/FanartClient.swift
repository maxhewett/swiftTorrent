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
            return try await moviePoster(imdbID: media.imdbID)
        case .show:
            return try await tvPoster(tvdbID: media.tvdbID)
        }
    }

    private func moviePoster(imdbID: String?) async throws -> URL? {
        guard let imdbID, !imdbID.isEmpty else { return nil }

        let url = URL(string: "https://webservice.fanart.tv/v3/movies/\(imdbID)?api_key=\(apiKey)")!
        let (data, _) = try await URLSession.shared.data(from: url)

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard
            let posters = json?["movieposter"] as? [[String: Any]],
            let first = posters.first,
            let urlString = first["url"] as? String
        else { return nil }

        return URL(string: urlString)
    }

    private func tvPoster(tvdbID: Int?) async throws -> URL? {
        guard let tvdbID, tvdbID > 0 else { return nil }

        let url = URL(string: "https://webservice.fanart.tv/v3/tv/\(tvdbID)?api_key=\(apiKey)")!
        let (data, _) = try await URLSession.shared.data(from: url)

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard
            let posters = json?["tvposter"] as? [[String: Any]],
            let first = posters.first,
            let urlString = first["url"] as? String
        else { return nil }

        return URL(string: urlString)
    }
}
