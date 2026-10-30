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
}
