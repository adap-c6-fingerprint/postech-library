//
//  BookSearchClient.swift
//  fingerprint-library
//
//  Created by 이시온 on 10/30/26.
//

import ComposableArchitecture

nonisolated struct BookSearchClient: Sendable {
    var cached : @Sendable (BookSearchRequest) -> [Book]?
    var search: @Sendable (_ request: BookSearchRequest, _ refreshing: Bool)
async throws -> [Book]

    static func live(bookClient: BookClient, cache: BookSearchResultCache) -> Self {
        Self (
            cached: { cache.load($0) },
            search: { request, refreshing in
                if refreshing { cache.remove(request) }
                let books = try await bookClient.search(request)
                try Task.checkCancellation()
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

nonisolated extension DependencyValues {
    var bookSearchClient: BookSearchClient {
        get { self[BookSearchClient.self] }
        set { self[BookSearchClient.self] = newValue }
    }
}
