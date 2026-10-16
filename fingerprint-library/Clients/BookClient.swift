//
//  BookClient.swift
//  2026-C6-M06-Fingerprint-library
//
//  Created by Youngmin Cho on 10/15/26.
//

import Foundation
import ComposableArchitecture

struct BookClient: Sendable {
    var search: @Sendable (_ query: String) async throws -> [Book]
}

extension BookClient: DependencyKey {
    static let liveValue = BookClient(
        search: { query in
            guard let apiKey = await AppConfiguration.nationalLibraryAPIKey else {
                throw BookClientError.missingAPIKey
            }

            var components = URLComponents(
                string: "https://www.nl.go.kr/NL/search/openApi/search.do"
                )

            components?.queryItems = [
                URLQueryItem(name: "key", value: apiKey),
                URLQueryItem(name: "apiType", value: "json"),
                URLQueryItem(name: "srchTarget", value: "total"),
                URLQueryItem(name: "kwd", value: query),
                URLQueryItem(name: "pageNum", value: "1"),
                URLQueryItem(name: "pageSize", value: "20"),
                URLQueryItem(name: "category", value: "도서"),
            ]

            guard let url = components?.url else {
                throw BookClientError.invalidURL
            }

            let (data, response) = try await URLSession.shared.data(from: url)

            guard
                let httpResponse = response as? HTTPURLResponse,
                200..<300 ~= httpResponse.statusCode
            else {
                throw BookClientError.invalidResponse
            }

            let decodedResponse = try JSONDecoder().decode(
                LibraryResponse.self,
                from: data
            )

            return decodedResponse.result.map { item in
                Book(
                    isbn: item.isbn ?? item.controlNumber,
                    title: item.title,
                    author: item.author ?? "저자 정보 없음",
                    publisher: item.publisher,
                    publicationYear: item.publicationYear,
                    description: nil,
                    imageURL: nil
                )
            }
        }
    )

    static let testValue = BookClient(
        search: { _ in
            return []
        }
    )

    private struct LibraryResponse: Decodable {
        let result: [LibraryBook]

        enum CodingKeys: String, CodingKey {
            case result
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)

            result = try container.decodeIfPresent(
                [LibraryBook].self,
                forKey: .result
            ) ?? []
        }
    }

    private struct LibraryBook: Decodable {
        let title: String
        let author: String?
        let publisher: String?
        let publicationYear: String?
        let isbn: String?
        let controlNumber: String

        enum CodingKeys: String, CodingKey {
            case title = "titleInfo"
            case author = "authorInfo"
            case publisher = "pubInfo"
            case publicationYear = "pubYearInfo"
            case isbn
            case controlNumber = "controlNo"
        }
    }

    private enum BookClientError: LocalizedError {
        case missingAPIKey
        case invalidURL
        case invalidResponse

        var errorDescription: String? {
            switch self {
            case .missingAPIKey:
                return "API 키가 없습니다."

            case .invalidURL:
                return "검색 주소를 생성하지 못했습니다."

            case .invalidResponse:
                return "서버에서 올바르지 않은 응답을 받았습니다."
            }
        }
    }
}

    extension DependencyValues {
        var bookClient: BookClient {
            get { self[BookClient.self] }
            set { self[BookClient.self] = newValue }
        }

}
