//
//  BookDetailClient.swift
//  fingerprint-library
//
//  Created by Youngmin Cho on 10/17/26.
//

import Foundation
import ComposableArchitecture

struct BookDetailClient: Sendable {
    var fetchDescription: @Sendable (_ isbn13: String) async throws -> BookDescription?
}

extension BookDetailClient: DependencyKey {
    static let liveValue = BookDetailClient(
        fetchDescription: { isbn13 in
            guard let apiKey = await AppConfiguration.yes24APIKey else {
                throw BookDetailClientError.missingAPIKey
            }
            return try await Yes24BookDetailService().fetchDescription(isbn13: isbn13, apiKey: apiKey)
        }
    )

    static let testValue = BookDetailClient(fetchDescription: { _ in nil })
}

nonisolated struct Yes24BookDetailService: Sendable {
    var load: @Sendable (URLRequest) async throws -> (Data, URLResponse) = {
        try await URLSession.shared.data(for: $0)
    }

    func fetchDescription(isbn13: String, apiKey: String) async throws -> BookDescription? {
        var components = URLComponents(string: "https://apis.yes24.com/v1/goods/itemDetail")
        components?.queryItems = [
            URLQueryItem(name: "searchType", value: "ISBN13"),
            URLQueryItem(name: "query", value: isbn13)
        ]
        guard let url = components?.url else { throw BookDetailClientError.invalidURL }

        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "X-Api-Key")
        let (data, response) = try await load(request)
        guard let http = response as? HTTPURLResponse else {
            throw BookDetailClientError.invalidResponse
        }
        let result = try? JSONDecoder().decode(Yes24DetailResponse.self, from: data)
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
        guard let item = items.first(where: { $0.isbn13 == isbn13 }),
              let introduction = item.contentDetail?.bookIntroduction else { return nil }

        let text = BookText.plainText(introduction)
        guard !text.isEmpty else { return nil }
        // 소개를 표시할 때 같은 상품의 Yes24 원문 링크도 제공한다.
        guard let sourceURL = item.link, sourceURL.scheme?.lowercased() == "https",
              let host = sourceURL.host?.lowercased(),
              host == "yes24.com" || host.hasSuffix(".yes24.com") else {
            throw BookDetailClientError.invalidResponse
        }
        return BookDescription(text: text, sourceURL: sourceURL)
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
    let link: URL?
    let contentDetail: Yes24ContentDetail?
}

private nonisolated struct Yes24ContentDetail: Decodable {
    let bookIntroduction: String?
}

nonisolated enum BookDetailClientError: Error {
    case missingAPIKey
    case invalidURL
    case invalidResponse
    case serviceError
}

extension DependencyValues {
    var bookDetailClient: BookDetailClient {
        get { self[BookDetailClient.self] }
        set { self[BookDetailClient.self] = newValue }
    }
}
