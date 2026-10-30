//
//  RelatedBooksClient.swift
//  fingerprint-library
//
//  Created by Youngmin Cho on 10/18/26.
//

import Foundation
import ComposableArchitecture

struct RelatedBooksClient: Sendable {
    var fetch: @Sendable (_ isbn13: String) async throws -> [Book]
}

extension RelatedBooksClient: DependencyKey {
    static let liveValue = RelatedBooksClient(
        fetch: { rawISBN in
            guard let isbn13 = BookISBN.isbn13(from: rawISBN) else {
                throw RelatedBooksClientError.invalidISBN
            }

            guard let apiKey = await AppConfiguration.data4LibraryAPIKey else {
                throw RelatedBooksClientError.missingAPIKey
            }

            // 요청 주소 구성
            var components = URLComponents(
                string: "https://data4library.kr/api/recommandList"
            )

            components?.queryItems = [
                URLQueryItem(name: "authKey", value: apiKey),
                URLQueryItem(name: "isbn13", value: isbn13),
                URLQueryItem(name: "type", value: "mania"),
                URLQueryItem(name: "format", value: "json")
            ]

            guard let url = components?.url else {
                throw RelatedBooksClientError.invalidURL
            }

            // API 호출
            let (data, response) = try await URLSession.shared.data(from: url)

            guard
                let httpResponse = response as? HTTPURLResponse,
                (200..<300).contains(httpResponse.statusCode)
            else {
                throw RelatedBooksClientError.invalidResponse
            }

            // JSON을 Swift 응답 타입으로 변환
            let decoded = try JSONDecoder().decode(
                RelatedBooksResponse.self,
                from: data
            )

            // 응답의 도서 정보를 앱의 Book으로 변환
            var seenISBNs = Set<String>()

            return decoded.response.docs.compactMap { document -> Book? in
                let item = document.book

                guard
                    let relatedISBN = BookISBN.isbn13(from: item.isbn13),
                    relatedISBN != isbn13,
                    seenISBNs.insert(relatedISBN).inserted
                else {
                    return nil
                }

                let imageURL = item.bookImageURL.flatMap { value -> URL? in
                    guard
                        let url = URL(string: value),
                        let scheme = url.scheme?.lowercased(),
                        ["https", "http"].contains(scheme),
                        url.host != nil
                    else {
                        return nil
                    }

                    return url
                }

                return Book(
                    id: "isbn:\(relatedISBN)",
                    isbn: relatedISBN,
                    controlNumber: nil,
                    title: item.bookname,
                    author: item.authors ?? "저자 정보 없음",
                    publisher: item.publisher,
                    publicationYear: item.publication_year,
                    description: nil,
                    imageURL: imageURL
                )
            }
        }
    )

    static let testValue = RelatedBooksClient(
        fetch: { _ in [] }
    )
}

// JSON의 response → docs → book 구조에 대응
private nonisolated struct RelatedBooksResponse: Decodable {
    let response: RelatedBooksPayload
}

private nonisolated struct RelatedBooksPayload: Decodable {
    let docs: [RelatedBookDocument]
}

private nonisolated struct RelatedBookDocument: Decodable {
    let book: RelatedBookDTO
}

private nonisolated struct RelatedBookDTO: Decodable {
    let bookname: String
    let authors: String?
    let publisher: String?
    let publication_year: String?
    let isbn13: String
    let bookImageURL: String?
}

nonisolated enum RelatedBooksClientError: Error {
    case invalidISBN
    case missingAPIKey
    case invalidURL
    case invalidResponse
}

// Feature에서 사용할 의존성 등록
extension DependencyValues {
    var relatedBooksClient: RelatedBooksClient {
        get { self[RelatedBooksClient.self] }
        set { self[RelatedBooksClient.self] = newValue }
    }
}
