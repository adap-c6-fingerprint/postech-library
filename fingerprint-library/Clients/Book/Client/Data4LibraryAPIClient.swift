import Foundation

/// 정보나루의 쿼리·응답 해석은 유지하고 인증·전송은 중계 Client에 맡긴다.
nonisolated struct Data4LibraryAPIClient: Sendable {
    enum Endpoint: Sendable {
        case relatedBooks
        case bookDetail

    }

    var relay: BookAPIClient = .init()

    func coverURL(isbn13: String) async throws -> URL? {
        let result = try await fetch(.bookDetail, isbn13: isbn13)
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

    func fetch(_ endpoint: Endpoint, isbn13: String) async throws -> HTTPResponse {
        var items = [URLQueryItem(name: "isbn13", value: isbn13)]
        if case .relatedBooks = endpoint {
            items.append(URLQueryItem(name: "type", value: "mania"))
        }
        items.append(URLQueryItem(name: "format", value: "json"))
        return try await relay.send(endpoint == .relatedBooks ? .data4LibraryRelated : .data4LibraryDetail, queryItems: items)
    }

    private nonisolated struct DetailResponse: Decodable {
        let response: Body
        nonisolated struct Body: Decodable { let detail: [Detail]? }
        nonisolated struct Detail: Decodable { let book: Book }
        nonisolated struct Book: Decodable { let bookImageURL: String? }
    }
}

nonisolated enum Data4LibraryAPIError: Error { case invalidResponse }
