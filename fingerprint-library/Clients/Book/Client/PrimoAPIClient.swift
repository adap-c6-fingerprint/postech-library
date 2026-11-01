import Foundation

/// 도서관 검색·추천·소장 조회가 공통으로 사용하는 Primo 요청 구성과 전송.
nonisolated struct PrimoAPIClient: Sendable {
    static let defaultBaseURL = APIRelayEnvironment.development.baseURL

    var relay: BookAPIClient = .init()

    /// 재시도 정책이 필요 없는 조회에서 HTTP 성공 응답의 본문을 반환한다.
    func searchData(
        query: String, resourceTypes: [String] = [], offset: Int = 0, limit: Int = 20
    ) async throws -> Data {
        let result: HTTPResponse
        do {
            result = try await search(query: query, resourceTypes: resourceTypes, offset: offset, limit: limit)
        } catch is HTTPClientError {
            throw PrimoAPIError.invalidResponse
        }
        guard result.isSuccessful else { throw PrimoAPIError.invalidResponse }
        return result.data
    }

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
        let url = try Self.searchURL(query: query, resourceTypes: resourceTypes, offset: offset, limit: limit)
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return try await relay.send(.primoSearch, queryItems: items, timeout: timeout)
    }
}

nonisolated enum PrimoAPIError: Error { case invalidResponse }
