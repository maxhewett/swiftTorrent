import Foundation

final class TVDBClient {
    enum EntityType: String {
        case movie
        case series

        var mediaType: MediaMetadata.MediaType {
            self == .movie ? .movie : .show
        }
    }

    struct Candidate: Hashable {
        let title: String
        let year: Int?
        let type: MediaMetadata.MediaType
        let tvdbID: Int?
        let tmdbID: Int?
        let imdbID: String?
        let overview: String?
        let posterURL: URL?
    }

    private let apiKey: String
    private let subscriberPIN: String?
    private let baseURL = URL(string: "https://api4.thetvdb.com/v4")!

    init(apiKey: String, subscriberPIN: String?) {
        self.apiKey = apiKey
        self.subscriberPIN = subscriberPIN
    }

    func search(query: String, year: Int?, types: [EntityType]) async throws -> [Candidate] {
        let token = try await login()
        var candidates: [Candidate] = []
        for type in types {
            var components = URLComponents(url: baseURL.appendingPathComponent("search"), resolvingAgainstBaseURL: false)!
            components.queryItems = [
                URLQueryItem(name: "query", value: query),
                URLQueryItem(name: "type", value: type.rawValue),
                URLQueryItem(name: "limit", value: "20")
            ]
            if let year { components.queryItems?.append(URLQueryItem(name: "year", value: String(year))) }
            guard let url = components.url else { continue }

            var request = URLRequest(url: url)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            let data = try await perform(request)
            let response = try JSONDecoder().decode(SearchResponse.self, from: data)
            candidates.append(contentsOf: response.data.compactMap { $0.candidate(type: type) })
        }
        return candidates
    }

    private func login() async throws -> String {
        let url = baseURL.appendingPathComponent("login")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body = ["apikey": apiKey]
        if let subscriberPIN, !subscriberPIN.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            body["pin"] = subscriberPIN.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let data = try await perform(request)
        let response = try JSONDecoder().decode(LoginResponse.self, from: data)
        guard !response.data.token.isEmpty else { throw LookupError.missingToken }
        return response.data.token
    }

    private func perform(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw LookupError.invalidResponse }
        guard (200..<300).contains(response.statusCode) else {
            let body = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw LookupError.httpStatus(response.statusCode, body.map { String($0.prefix(400)) })
        }
        return data
    }

    private struct LoginResponse: Decodable {
        struct DataPayload: Decodable { let token: String }
        let data: DataPayload
    }

    private struct SearchResponse: Decodable {
        let data: [SearchRecord]
    }

    private struct SearchRecord: Decodable {
        let id: FlexibleValue?
        let tvdbID: FlexibleValue?
        let name: String?
        let year: FlexibleValue?
        let overview: String?
        let imageURL: String?
        let remoteIDs: [RemoteID]?

        enum CodingKeys: String, CodingKey {
            case id, name, year, overview
            case tvdbID = "tvdb_id"
            case imageURL = "image_url"
            case remoteIDs = "remote_ids"
            case overviews
        }

        private let overviews: [String: String]?

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try? container.decodeIfPresent(FlexibleValue.self, forKey: .id)
            tvdbID = try? container.decodeIfPresent(FlexibleValue.self, forKey: .tvdbID)
            name = try? container.decodeIfPresent(String.self, forKey: .name)
            year = try? container.decodeIfPresent(FlexibleValue.self, forKey: .year)
            overview = try? container.decodeIfPresent(String.self, forKey: .overview)
            imageURL = try? container.decodeIfPresent(String.self, forKey: .imageURL)
            remoteIDs = try? container.decodeIfPresent([RemoteID].self, forKey: .remoteIDs)
            overviews = try? container.decodeIfPresent([String: String].self, forKey: .overviews)
        }

        func candidate(type: EntityType) -> Candidate? {
            guard let name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            let resolvedID = tvdbID?.intValue ?? id?.intValue
            let tmdbID = remoteIDs?.first(where: { $0.type.lowercased().contains("tmdb") })?.id.intValue
            let imdbID = remoteIDs?.first(where: { $0.type.lowercased().contains("imdb") })?.id.stringValue
            return Candidate(
                title: name,
                year: year?.intValue,
                type: type.mediaType,
                tvdbID: resolvedID,
                tmdbID: tmdbID,
                imdbID: imdbID,
                overview: overview ?? overviews?["eng"] ?? overviews?.values.first,
                posterURL: imageURL.flatMap(URL.init(string:))
            )
        }
    }

    private struct RemoteID: Decodable {
        let id: FlexibleValue
        let type: String
    }

    private struct FlexibleValue: Decodable {
        let stringValue: String

        var intValue: Int? { Int(stringValue) }

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let string = try? container.decode(String.self) {
                stringValue = string
            } else if let integer = try? container.decode(Int.self) {
                stringValue = String(integer)
            } else {
                stringValue = ""
            }
        }
    }

    enum LookupError: LocalizedError {
        case invalidResponse
        case missingToken
        case httpStatus(Int, String?)

        var errorDescription: String? {
            switch self {
            case .invalidResponse: return "TheTVDB returned an invalid HTTP response."
            case .missingToken: return "TheTVDB login succeeded without returning a token."
            case .httpStatus(let status, let body):
                if let body, !body.isEmpty { return "TheTVDB returned HTTP \(status): \(body)" }
                return "TheTVDB returned HTTP \(status)."
            }
        }
    }
}
