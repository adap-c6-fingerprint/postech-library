import Foundation

/// 도서관 검색·추천·소장 조회가 공통으로 사용하는 Primo 요청 구성과 전송.
nonisolated struct PrimoAPIClient: Sendable {
    static let defaultBaseURL = URL(string: "https://api-ap.hosted.exlibrisgroup.com")!

    var httpClient: HTTPClient = .urlSession()
    var baseURL: URL = defaultBaseURL
    var apiKey: String? = nil

    static func searchURL(
        baseURL: URL = defaultBaseURL,
        query: String,
        resourceTypes: [String] = [],
        offset: Int = 0,
        limit: Int = 20
    ) throws -> URL {
        var components = URLComponents(
            url: baseURL.appending(path: "primo/v1/search"),
            resolvingAgainstBaseURL: false
        )
        var items = [
            URLQueryItem(name: "vid", value: "82POSTECH_INST:82POSTECH"),
            URLQueryItem(name: "tab", value: "LibraryCatalog"),
            URLQueryItem(name: "scope", value: "MyInstitution"),
            URLQueryItem(name: "q", value: query)
        ]
        if !resourceTypes.isEmpty {
            items.append(URLQueryItem(
                name: "multiFacets",
                value: resourceTypes.map { "facet_rtype,include,\($0)" }.joined(separator: "|,|")
            ))
        }
        items += [
            URLQueryItem(name: "lang", value: "ko"),
            URLQueryItem(name: "offset", value: String(offset)),
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "skipDelivery", value: "false")
        ]
        components?.queryItems = items
        guard let url = components?.url else { throw URLError(.badURL) }
        return url
    }

    func search(
        query: String,
        resourceTypes: [String] = [],
        offset: Int = 0,
        limit: Int = 20,
        timeout: TimeInterval = 60
    ) async throws -> HTTPResponse {
        let url = try Self.searchURL(
            baseURL: baseURL, query: query, resourceTypes: resourceTypes, offset: offset, limit: limit
        )
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let apiKey { request.setValue("apikey \(apiKey)", forHTTPHeaderField: "Authorization") }
        return try await httpClient.send(request)
    }
}
