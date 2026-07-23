import Foundation

struct WebSearchResult: Codable, Hashable, Sendable {
    let title: String
    let url: URL
    let highlights: [String]
    let publishedDate: String?
}

enum ExaSearchError: LocalizedError {
    case missingAPIKey
    case invalidResponse
    case requestFailed(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey: "Add an EXA_API_KEY before using web search."
        case .invalidResponse: "Exa returned an unreadable search response."
        case let .requestFailed(statusCode, message): "Exa search failed (\(statusCode)): \(message)"
        }
    }
}

/// Raw Exa retrieval for Lilbud's one intentional network capability. Results
/// stay small and are passed back into Pi; Exa never writes the final chat reply.
@MainActor
final class ExaSearchService {
    private let session: URLSession
    private let apiKey: @Sendable () -> String?

    init(session: URLSession = .shared, apiKey: @escaping @Sendable () -> String? = { ProcessInfo.processInfo.environment["EXA_API_KEY"] }) {
        self.session = session
        self.apiKey = apiKey
    }

    func search(_ tool: SearchWebTool) async throws -> [WebSearchResult] {
        guard let apiKey = apiKey(), !apiKey.isEmpty else { throw ExaSearchError.missingAPIKey }

        var request = URLRequest(url: URL(string: "https://api.exa.ai/search")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.httpBody = try JSONEncoder().encode(ExaRequest(tool: tool))

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ExaSearchError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(decoding: data, as: UTF8.self)
            throw ExaSearchError.requestFailed(statusCode: http.statusCode, message: String(body.prefix(300)))
        }
        let decoded = try JSONDecoder().decode(ExaResponse.self, from: data)
        return decoded.results.compactMap { result in
            guard let url = URL(string: result.url) else { return nil }
            return WebSearchResult(title: result.title ?? result.url, url: url, highlights: result.highlights ?? [], publishedDate: result.publishedDate)
        }
    }
}

private struct ExaRequest: Encodable {
    let query: String
    let type = "auto"
    let numResults: Int
    let contents: Contents

    struct Contents: Encodable {
        let highlights = true
        let maxAgeHours: Int?
    }

    init(tool: SearchWebTool) {
        query = tool.query
        numResults = min(max(tool.maxResults, 1), 10)
        // "recent" tells Exa to refresh cache older than one day. "any" keeps
        // the fast cached path and is suitable for stable questions.
        contents = Contents(maxAgeHours: tool.freshness == .recent ? 24 : nil)
    }
}

private struct ExaResponse: Decodable {
    let results: [Result]
    struct Result: Decodable {
        let title: String?
        let url: String
        let highlights: [String]?
        let publishedDate: String?
    }
}

/// Formats the provider's response as bounded, source-labelled tool output for
/// Pi. The app may also use these exact records to render citations in SwiftUI.
enum SearchToolOutput {
    static func format(_ results: [WebSearchResult]) -> String {
        guard !results.isEmpty else { return "No web results found." }
        return results.enumerated().map { index, result in
            let excerpt = result.highlights.prefix(2).joined(separator: " ")
            let date = result.publishedDate.map { " (\($0))" } ?? ""
            return "[\(index + 1)] \(result.title)\(date)\n\(result.url.absoluteString)\n\(excerpt)"
        }.joined(separator: "\n\n")
    }
}
