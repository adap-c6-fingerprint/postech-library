import Foundation

/// 정보나루 API의 주소·쿼리 인증·전송을 한곳에서 관리한다.
nonisolated struct Data4LibraryAPIClient: Sendable {
    enum Endpoint: Sendable {
        case relatedBooks
        case bookDetail

        var path: String {
            switch self {
            case .relatedBooks: "recommandList"
            case .bookDetail: "srchDtlList"
            }
        }
    }

    var httpClient: HTTPClient = .urlSession()
    var baseURL = URL(string: "https://data4library.kr/api")!

    func coverURL(isbn13: String, apiKey: String) async throws -> URL? {
        let result = try await fetch(.bookDetail, isbn13: isbn13, apiKey: apiKey)
        guard result.isSuccessful else { throw Data4LibraryAPIError.invalidResponse }
        let decoded = try JSONDecoder().decode(DetailResponse.self, from: result.data)
        guard let raw = decoded.response.detail?.first?.book.bookImageURL else { return nil }
        return Self.secureCoverURL(raw)
    }

    static func secureCoverURL(_ raw: String) -> URL? {
        guard var parts = URLComponents(string: raw), parts.host?.isEmpty == false else { return nil }
        switch parts.scheme?.lowercased() {
        case "https": break
        case "http": parts.scheme = "https"
        default: return nil
        }
        return parts.url
    }

    func fetch(_ endpoint: Endpoint, isbn13: String, apiKey: String) async throws -> HTTPResponse {
        var components = URLComponents(
            url: baseURL.appending(path: endpoint.path), resolvingAgainstBaseURL: false
        )
        var items = [
            URLQueryItem(name: "authKey", value: apiKey),
            URLQueryItem(name: "isbn13", value: isbn13)
        ]
        if case .relatedBooks = endpoint {
            items.append(URLQueryItem(name: "type", value: "mania"))
        }
        items.append(URLQueryItem(name: "format", value: "json"))
        components?.queryItems = items
        guard let url = components?.url else { throw URLError(.badURL) }
        return try await httpClient.send(URLRequest(url: url))
    }

    private nonisolated struct DetailResponse: Decodable {
        let response: Body
        nonisolated struct Body: Decodable { let detail: [Detail]? }
        nonisolated struct Detail: Decodable { let book: Book }
        nonisolated struct Book: Decodable { let bookImageURL: String? }
    }
}

nonisolated enum Data4LibraryAPIError: Error { case invalidResponse }
