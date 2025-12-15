//
//  TraktClient.swift
//  swiftTorrent
//
//  Created by Max Hewett on 14/12/2025.
//

import Foundation

final class TraktClient {
    private let clientID: String
    private let base = URL(string: "https://api.trakt.tv")!

    init(clientID: String) {
        self.clientID = clientID
    }

    private func makeRequest(_ path: String, queryItems: [URLQueryItem]) -> URLRequest {
        var comps = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        comps.queryItems = queryItems

        var req = URLRequest(url: comps.url!)
        req.httpMethod = "GET"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(clientID, forHTTPHeaderField: "trakt-api-key")
        req.setValue("2", forHTTPHeaderField: "trakt-api-version")
        return req
    }

    // MARK: - Models (decode only what we need)

    struct SearchResult: Decodable, Hashable {
        let type: String
        let movie: Movie?
        let show: Show?

        struct Movie: Decodable, Hashable {
            let title: String
            let year: Int?
            let ids: IDs
            let overview: String?
        }

        struct Show: Decodable, Hashable {
            let title: String
            let year: Int?
            let ids: IDs
            let overview: String?
        }

        struct IDs: Decodable, Hashable {
            let trakt: Int?
            let slug: String?
            let imdb: String?
            let tmdb: Int?
            let tvdb: Int?
        }
    }

    // MARK: - API

    func searchMovie(query: String, year: Int?) async throws -> SearchResult.Movie? {
        var items = [URLQueryItem(name: "query", value: query)]
        if let year { items.append(URLQueryItem(name: "year", value: "\(year)")) } // ✅ year (not years)

        // Optional: ask for more info
        items.append(URLQueryItem(name: "extended", value: "full"))

        let req = makeRequest("/search/movie", queryItems: items)
        let (data, _) = try await URLSession.shared.data(for: req)
        let results = try JSONDecoder().decode([SearchResult].self, from: data)

        // Trakt sorts by relevance, but year now actually filters, so first is usually correct.
        return results.compactMap(\.movie).first
    }

    func searchShow(query: String, year: Int?) async throws -> SearchResult.Show? {
        var items = [URLQueryItem(name: "query", value: query)]
        if let year { items.append(URLQueryItem(name: "year", value: "\(year)")) } // ✅ year (not years)

        items.append(URLQueryItem(name: "extended", value: "full"))

        let req = makeRequest("/search/show", queryItems: items)
        let (data, _) = try await URLSession.shared.data(for: req)
        let results = try JSONDecoder().decode([SearchResult].self, from: data)

        return results.compactMap(\.show).first
    }
}
