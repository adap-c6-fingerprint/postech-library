import Foundation

nonisolated struct Yes24BookDetailService: Sendable {
    var relay: BookAPIClient = .init()

    func fetchCoverURL(isbn13: String) async throws -> URL? {
        guard let raw = try await matchingItem(isbn13: isbn13)?.cover,
              let url = URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme?.lowercased() == "https", let host = url.host?.lowercased(),
              host == "yes24.com" || host.hasSuffix(".yes24.com"),
              url.user == nil, url.password == nil else { return nil }
        return url
    }

    func fetchDescription(isbn13: String) async throws -> BookDescription? {
        guard let item = try await matchingItem(isbn13: isbn13),
              let introduction = item.contentDetail?.bookIntroduction else { return nil }
        let text = BookText.plainText(introduction)
        guard !text.isEmpty else { return nil }
        guard let sourceURL = item.link, sourceURL.scheme?.lowercased() == "https",
              let host = sourceURL.host?.lowercased(),
              host == "yes24.com" || host.hasSuffix(".yes24.com") else {
            throw BookDetailClientError.invalidResponse
        }
        return BookDescription(text: text, sourceURL: sourceURL)
    }

    private func matchingItem(isbn13: String) async throws -> Yes24DetailItem? {
        guard BookISBN.isbn13(from: isbn13) == isbn13 else { return nil }
        let items = [
            URLQueryItem(name: "searchType", value: "ISBN13"),
            URLQueryItem(name: "query", value: isbn13)
        ]
        let response: HTTPResponse
        do {
            response = try await relay.send(.yes24Detail, queryItems: items, timeout: 15)
        } catch is HTTPClientError {
            throw BookDetailClientError.invalidResponse
        }
        let http = response.response
        let result = try? JSONDecoder().decode(Yes24DetailResponse.self, from: response.data)
        // SEARCH_002도 404이므로 상품이 없다는 오류만 빈 결과로 처리한다.
        if http.statusCode == 404,
           let code = result?.errorCode, ["GOODS_001", "GOODS_002"].contains(code) {
            return nil
        }
        guard (200..<300).contains(http.statusCode), let result else {
            throw BookDetailClientError.invalidResponse
        }
        guard result.success, result.errorCode?.isEmpty != false else {
            throw BookDetailClientError.serviceError
        }
        guard let items = result.data?.items else { throw BookDetailClientError.invalidResponse }
        return items.first(where: { $0.isbn13 == isbn13 })
    }
}

private nonisolated struct Yes24DetailResponse: Decodable {
    let success: Bool
    let errorCode: String?
    let data: Yes24DetailData?
}

private nonisolated struct Yes24DetailData: Decodable {
    let items: [Yes24DetailItem]
}

private nonisolated struct Yes24DetailItem: Decodable {
    let isbn13: String?
    let cover: String?
    let link: URL?
    let contentDetail: Yes24ContentDetail?
}

private nonisolated struct Yes24ContentDetail: Decodable {
    let bookIntroduction: String?
}

nonisolated enum BookDetailClientError: Error {
    case invalidURL
    case invalidResponse
    case serviceError
}
