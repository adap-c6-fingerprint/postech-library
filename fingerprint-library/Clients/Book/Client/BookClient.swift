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

    /// 검색 응답의 변환 오류를 기존 Client 오류로 전달한다.
    nonisolated static func books(from data: Data) throws -> [Book] {
        do {
            return try PrimoBookMapper.books(from: data)
        } catch PrimoBookMapper.MappingError.invalidResponse {
            throw BookClientError.invalidResponse
        }
    }

    private enum BookClientError: LocalizedError {
        case missingAPIKey
        case invalidResponse
        
        var errorDescription: String? {
            switch self {
            case .missingAPIKey:
                return "API 키가 없습니다."
                
            case .invalidResponse:
                return "서버에서 올바르지 않은 응답을 받았습니다."
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
