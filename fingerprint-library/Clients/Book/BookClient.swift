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
            
            components?.queryItems = [
                URLQueryItem(name: "vid", value: "82POSTECH_INST:82POSTECH"),
                URLQueryItem(name: "tab", value: "LibraryCatalog"),
                URLQueryItem(name: "scope", value: "MyInstitution"),
                URLQueryItem(name: "q", value: "any,contains,\(query)"),
                URLQueryItem(name: "qInclude", value: "facet_rtype,exact,books"),
                URLQueryItem(name: "lang", value: "ko"),
                URLQueryItem(name: "offset", value: "0"),
                URLQueryItem(name: "limit", value: "20"),
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
                LibraryResponse.self,
                from: data
            )
            
            var seen = Set<[String?]>()
            
            return decodedResponse.result.compactMap { item -> Book? in
                let isbn = BookClient.nonEmpty(item.isbn)
                let controlNumber = BookClient.nonEmpty(item.controlNumber)
                
                // 중복인지 판단할 기준
                let key: [String?]
                
                if let controlNumber {
                    key = ["control", controlNumber]
                } else {
                    key = [
                        "metadata",
                        isbn,
                        BookClient.nonEmpty(item.title),
                        BookClient.nonEmpty(item.author),
                        BookClient.nonEmpty(item.publisher),
                        BookClient.nonEmpty(item.publicationYear)
                    ]
                }
                
                // 이미 나온 레코드는 제외
                guard seen.insert(key).inserted else {
                    return nil
                }
                
                // 제어번호가 없으면 생성 시 UUID를 한 번 부여
                let id = controlNumber.map { "control:\($0)" }
                    ?? "local:\(UUID().uuidString)"
                
                return Book(
                    id: id,
                    isbn: isbn,
                    controlNumber: controlNumber,
                    title: item.title,
                    author: item.author ?? "저자 정보 없음",
                    publisher: item.publisher,
                    publicationYear: item.publicationYear,
                    description: nil,
                    imageURL: item.imageURLString.flatMap { value -> URL? in
                        let path = value.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard
                            !path.isEmpty,
                            let baseURL = URL(string: "https://cover.nl.go.kr/")
                                else {
                            return nil
                        }
                        return URL(
                            string: path,
                            relativeTo: baseURL
                        )?.absoluteURL
                    }
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
    var bookClient: BookClient {
        get { self[BookClient.self] }
        set { self[BookClient.self] = newValue }
    }
    
}
