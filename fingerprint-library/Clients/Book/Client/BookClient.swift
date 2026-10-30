//
//  BookClient.swift
//  2026-C6-M06-Fingerprint-library
//
//  Created by Youngmin Cho on 10/15/26.
//

import Foundation
import ComposableArchitecture

nonisolated struct BookClient: Sendable {
    var search: @Sendable (_ request: BookSearchRequest) async throws -> [Book]
    
    /// URL 생성은 인증과 분리해 자료 유형 필터를 오프라인에서도 검증한다.
    nonisolated static func searchURL(for request: BookSearchRequest) throws -> URL {
        try PrimoAPIClient.searchURL(
            query: "any,contains,\(request.query)", resourceTypes: resourceTypes(for: request.category)
        )
    }

    private static func resourceTypes(for category: BookSearchCategory) -> [String] {
        switch category {
        case .all:
            ["books", "printed_book", "journals"]
        case .monograph:
            ["books", "printed_book"]
        case .journal:
            ["journals"]
        }
    }

    nonisolated static func publicationYear(from value: String?) -> String? {
        guard let value,
              let range = value.range(
                of: #"(?<![0-9])(?!0000)[0-9]{4}(?![0-9])"#,
                options: .regularExpression
              ) else {
            return nil
        }

        return String(value[range])
    }

    nonisolated static func publisher(
        from values: [String]?,
        fallback: [String]?
    ) -> String? {
        nonEmpty(
            values?.compactMap { nonEmpty($0) }.joined(separator: ", ")
        ) ?? nonEmpty(
            fallback?.compactMap { nonEmpty($0) }.joined(separator: ", ")
        )
    }

    private nonisolated static func nonEmpty(_ value: String?) -> String? {
        guard let text = value?.trimmingCharacters(
            in: .whitespacesAndNewlines
        ), !text.isEmpty else {
            return nil
        }
        
        return text
    }
}

extension BookClient: DependencyKey {
    static let liveValue = BookClient(
        search: { searchRequest in
            guard let apiKey = await AppConfiguration.primoAPIKey else {
                throw BookClientError.missingAPIKey
            }
            
            @Dependency(\.httpClient) var httpClient
            let result: HTTPResponse
            do {
                result = try await PrimoAPIClient(httpClient: httpClient, apiKey: apiKey).search(
                    query: "any,contains,\(searchRequest.query)",
                    resourceTypes: resourceTypes(for: searchRequest.category)
                )
            } catch is HTTPClientError {
                throw BookClientError.invalidResponse
            }
            guard result.isSuccessful else { throw BookClientError.invalidResponse }
            return try BookClient.books(from: result.data)
        }
    )

    static let testValue = BookClient(
        search: { _ in
            return []
        }
    )

    /// 검색 응답 변환은 인증과 분리해 소장 위치와 서지 정보를 오프라인에서 검증한다.
    nonisolated static func books(from data: Data) throws -> [Book] {
        let decodedResponse = try JSONDecoder().decode(
            PrimoResponse.self,
            from: data
        )

        var seen = Set<String>()

        let books = decodedResponse.docs.compactMap { document -> Book? in
            guard
                let recordID = BookClient.nonEmpty(
                    document.pnx.control.recordid.first
                ),
                let rawTitle = document.pnx.display.title.first
            else {
                return nil
            }

            let title = BookText.plainText(rawTitle)

            guard !title.isEmpty, seen.insert(recordID).inserted else {
                return nil
            }

            let imageURL = document.delivery?.link?
                .filter {
                    $0.linkType == "thumbnail"
                        || $0.linkType?.hasSuffix("/thumbnail") == true
                }
                .compactMap { link -> URL? in
                    guard
                        let address = link.linkURL,
                        let parts = URLComponents(string: address),
                        parts.scheme?.lowercased() == "https",
                        let host = parts.host, !host.isEmpty
                    else { return nil }

                    // 이미지 대신 정보를 반환하는 조회용 주소는 제외
                    let isLookup = parts.queryItems?.contains {
                        $0.name == "jscmd" && $0.value == "viewapi"
                    } ?? false

                    return isLookup ? nil : parts.url
                }
                .first

            let identity = "primo:\(recordID)"

            return Book(
                id: identity,
                isbn: BookISBN.isbn13(from: document.pnx.addata?.isbn?.joined(separator: " ")),
                controlNumber: identity,
                title: title,
                author: BookClient.nonEmpty(
                    document.pnx.display.creator?
                        .map {
                            // $$Q 앞의 화면 표시용 정보만 사용한다.
                            let displayText = $0.components(separatedBy: "$$Q").first ?? $0
                            return BookText.plainText(displayText)
                        }
                    .filter { !$0.isEmpty }
                    .joined(separator: ", ")
                ) ?? "저자 정보 없음",
                publisher: BookClient.publisher(
                    from: document.pnx.addata?.pub,
                    fallback: document.pnx.addata?.publisher
                ),
                publicationYear: BookClient.publicationYear(from:
                    document.pnx.addata?.date?.first
                ),
                description: nil,
                imageURL: imageURL,
                subLocation: document.delivery?.subLocation
            )
        }

        if !decodedResponse.docs.isEmpty && books.isEmpty {
            throw BookClientError.invalidResponse
        }

        return books
    }

    private nonisolated struct PrimoResponse: Decodable {
        let docs: [PrimoDocument]
    }

    private nonisolated struct PrimoDocument: Decodable {
        let pnx: PrimoPNX
        let delivery: PrimoDelivery?
    }

    private nonisolated struct PrimoDelivery: Decodable {
        let link: [PrimoLink]?
        let holding: [PrimoHolding]?
        let bestlocation: PrimoHolding?

        var subLocation: String? {
            // 명시적인 빈 holding은 소장 정보 없음이며, bestlocation으로 되살리지 않는다.
            let locations = holding.map { $0.compactMap(\.subLocation) }
                ?? [bestlocation?.subLocation].compactMap { $0 }
            var seen = Set<String>()
            let names = locations.map(BookText.plainText)
                .filter { !$0.isEmpty && seen.insert($0).inserted }
            return names.isEmpty ? nil : names.joined(separator: " · ")
        }
    }

    private nonisolated struct PrimoHolding: Decodable {
        let subLocation: String?
    }

    private nonisolated struct PrimoLink: Decodable {
        let linkType: String?
        let linkURL: String?
    }

    private nonisolated struct PrimoPNX: Decodable {
        let control: PrimoControl
        let display: PrimoDisplay
        let addata: PrimoAddData?
    }
    
    private nonisolated struct PrimoAddData: Decodable {
        let isbn: [String]?
        let pub: [String]?
        let publisher: [String]?
        let date: [String]?
    }
    
    private nonisolated struct PrimoControl: Decodable {
        let recordid: [String]
    }

    private nonisolated struct PrimoDisplay: Decodable {
        let title: [String]
        let creator: [String]?
    }
    
    private enum BookClientError: LocalizedError {
        case missingAPIKey
        case invalidURL
        case invalidResponse
        case apiError(code: String?, message: String)
        
        var errorDescription: String? {
            switch self {
            case .missingAPIKey:
                return "API 키가 없습니다."
                
            case .invalidURL:
                return "검색 주소를 생성하지 못했습니다."
                
            case .invalidResponse:
                return "서버에서 올바르지 않은 응답을 받았습니다."
                
            case .apiError:
                return "도서 검색 서비스를 이용할 수 없습니다. 잠시 후 다시 시도해 주세요."
            }
        }
    }
}

extension DependencyValues {
    nonisolated var bookClient: BookClient {
        get { self[BookClient.self] }
        set { self[BookClient.self] = newValue }
    }
    
}
