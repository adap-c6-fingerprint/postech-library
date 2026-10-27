//
//  BookRecommendationClient.swift
//  fingerprint-library
//
//  Created by Youngmin Cho on 10/26/26.
//

import Foundation
import ComposableArchitecture

struct BookRecommendationClient: Sendable {
    var fetch: @Sendable (_ count: Int) async throws -> [Book]
}

extension BookRecommendationClient: DependencyKey {
    static let liveValue: Self = .random
    
    static let random = Self(
        fetch: { count in
            guard count > 0 else { return [] }
            
            @Dependency(\.bookClient) var bookClient
            
            let keywords = ["소설", "과학", "역사", "예술"]
            let keyword = keywords.randomElement() ?? "소설"
            
            let books = try await bookClient.search(keyword)
            
            return Array(books.shuffled().prefix(count))
        }
    )
    
    static let testValue = Self(
        fetch: { _ in [] }
    )
}

extension DependencyValues {
    var bookRecommendationClient: BookRecommendationClient {
        get { self[BookRecommendationClient.self] }
        set { self[BookRecommendationClient.self] = newValue }
    }
}
