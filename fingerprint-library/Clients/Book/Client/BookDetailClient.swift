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
            @Dependency(\.httpClient) var httpClient
            return try await Yes24BookDetailService(relay: .init(httpClient: httpClient))
                .fetchDescription(isbn13: isbn13)
        }
    )

    static let testValue = BookDetailClient(fetchDescription: { _ in nil })
}

extension DependencyValues {
    var bookDetailClient: BookDetailClient {
        get { self[BookDetailClient.self] }
        set { self[BookDetailClient.self] = newValue }
    }
}
