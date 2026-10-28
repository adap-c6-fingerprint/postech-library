//
//  BookClient.swift
//  2026-C6-M06-Fingerprint-library
//
//  Created by Youngmin Cho on 10/15/26.
//

import Foundation
import ComposableArchitecture

nonisolated struct BookClient: Sendable {
    var search: @Sendable (_ query: String) async throws -> [Book]
    
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
        search: { query in
            guard let apiKey = await AppConfiguration.primoAPIKey else {
                throw BookClientError.missingAPIKey
            }
            
            let primoGateway = "https://api-ap.hosted.exlibrisgroup.com"

            var components = URLComponents(
                string: "\(primoGateway)/primo/v1/search"
            )
            
            // name은 Primo 서버가 정한 항목 이름이고, value는 그 항목에 보낼 값
            // 예: name이 limit이고 value가 20이면 URL에 limit=20이 붙음
            components?.queryItems = [
                // vid = view ID. 어떤 Primo 검색 화면의 설정을 사용할지 지정
                // 이 값은 POSTECH 검색 화면의 식별자
                URLQueryItem(name: "vid", value: "82POSTECH_INST:82POSTECH"),

                // tab: 검색 화면 안에서 사용할 탭의 설정 이름
                // LibraryCatalog는 소장자료 검색 탭
                URLQueryItem(name: "tab", value: "LibraryCatalog"),

                // scope: 실제로 어느 자료 범위에서 검색할지 지정
                // MyInstitution은 해당 기관(여기서는 POSTECH)의 자료 범위
                URLQueryItem(name: "scope", value: "MyInstitution"),

                // q = query. 검색 조건을 "검색 필드,검색 방식,검색어" 순서로 보냄
                // any는 통합검색 필드, contains는 포함 검색, query는 사용자가 입력한 검색어
                // 예: query가 사피엔스이면 "any,contains,사피엔스"를 보냄
                URLQueryItem(name: "q", value: "any,contains,\(query)"),

                // 같은 자료 유형의 값은 OR로 묶어 기존 도서와 종이책을 함께 검색한다.
                URLQueryItem(
                    name: "multiFacets",
                    value: "facet_rtype,include,books|,|facet_rtype,include,printed_book"
                ),

                // lang = language. ko는 표시 언어를 한국어로 지정하는 값
                URLQueryItem(name: "lang", value: "ko"),

                // offset: 검색 결과의 앞에서 몇 건을 건너뛸지 지정
                URLQueryItem(name: "offset", value: "0"),

                // limit: 이번 요청에서 받을 검색 결과의 최대 개수
                URLQueryItem(name: "limit", value: "20"),

                // skipDelivery: 소장·이용가능정보 조회를 건너뛸지 지정(Primo VE)
                // true는 생략, false는 생략하지 않고 함께 조회하도록 요청한
                // 여기서 delivery는 배송이 아니라 자료의 소장·이용 정보 조회
                URLQueryItem(name: "skipDelivery", value: "false")
            ]

            
            guard let url = components?.url else {
                throw BookClientError.invalidURL
            }
            
            var request = URLRequest(url: url)
            request.setValue(
                "apikey \(apiKey)",
                forHTTPHeaderField: "Authorization"
            )

            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard
                let httpResponse = response as? HTTPURLResponse,
                200..<300 ~= httpResponse.statusCode
                    else {
                throw BookClientError.invalidResponse
            }
            
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
                    imageURL: imageURL
                )
            }

            if !decodedResponse.docs.isEmpty && books.isEmpty {
                throw BookClientError.invalidResponse
            }

            return books
        }
    )
    
    static let testValue = BookClient(
        search: { _ in
            return []
        }
    )
    
    private nonisolated struct PrimoResponse: Decodable {
        let docs: [PrimoDocument]
    }

    private nonisolated struct PrimoDocument: Decodable {
        let pnx: PrimoPNX
        let delivery: PrimoDelivery?
    }

    private nonisolated struct PrimoDelivery: Decodable {
        let link: [PrimoLink]?
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
    
    private struct LibraryResponse: Decodable {
        let result: [LibraryBook]
        
        enum CodingKeys: String, CodingKey {
            case result
            case errorCode
            case errorMsg
        }
        
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            
            let errorCode = BookClient.nonEmpty(
                try container.decodeIfPresent(String.self, forKey: .errorCode)
            )
            let errorMessage = BookClient.nonEmpty(
                try container.decodeIfPresent(String.self, forKey: .errorMsg)
            )
            
            // API 오류가 있으면 검색 결과를 처리하기 전에 중단
            if errorCode != nil || errorMessage != nil {
                throw BookClientError.apiError(
                    code: errorCode,
                    message: errorMessage ?? "알 수 없는 API 오류"
                )
            }
            
            // api 오류가 없는 응답의 검색 결과 처리
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
        let controlNumber: String?
        let imageURLString: String?
        
        enum CodingKeys: String, CodingKey {
            case title = "titleInfo"
            case author = "authorInfo"
            case publisher = "pubInfo"
            case publicationYear = "pubYearInfo"
            case isbn
            case controlNumber = "controlNo"
            case imageURLString = "imageUrl"
        }
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
