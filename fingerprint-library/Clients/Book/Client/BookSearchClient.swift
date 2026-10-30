//
//  BookSearchClient.swift
//  fingerprint-library
//
//  Created by 이시온 on 10/30/26.
//

import ComposableArchitecture

nonisolated struct BookSearchClient: Sendable {
    var cached : @Sendable (BookSearchRequest) -> [Book]?
    // BookSearchResultCache에 결과가 있으면 돌려준다
    var search: @Sendable (_ request: BookSearchRequest, _ refreshing: Bool)
async throws -> [Book]
    // 서버에서 검색 후 BookSearchResultCache에 저장

    static func live(bookClient: BookClient, cache: BookSearchResultCache) -> Self {
        Self (
            cached: { cache.load($0) },
            search: { request, refreshing in
                if refreshing { cache.remove(request) } // 새로고침이면 오래된 결과를 버린다
                let books = try await bookClient.search(request) // 서버에 검색
                try Task.checkCancellation() // 그 사이 검색이 취소됐으면 보관함에 안 넣고 멈추기
                cache.save(books, for: request)
                return books
            }
        )
    }
}

extension BookSearchClient: DependencyKey {
    static let liveValue = Self.live(bookClient: .liveValue, cache: BookSearchResultCache())
    static let testValue = Self(cached: { _ in nil }, search: { _, _ in [] })
}

extension DependencyValues {
    var bookSearchClient: BookSearchClient {
        // BookSearchFeature.swift에서 @Dependency(\.bookSearchClient)로 호출됨
        get { self[BookSearchClient.self] }
        set { self[BookSearchClient.self] = newValue }
    }
}
