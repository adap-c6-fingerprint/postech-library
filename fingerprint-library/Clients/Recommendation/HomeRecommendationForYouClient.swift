//
//  Untitled.swift
//  fingerprint-library
//
//  Created by 이시온 on 10/30/26.
//

import ComposableArchitecture
import Foundation

enum HomeRecommendationForYouError: Error, Equatable {
    case empty
    case insufficientReplacements
}

nonisolated struct HomeRecommendationForYouClient: Sendable {
    var restore: @Sendable (_ displayedCovers: [URL]) async -> CachedRecommendations?
    var refresh: @Sendable (_ count: Int, _ displayedCovers: [URL]) async throws -> CachedRecommendations
    var prepareReplacement: @Sendable (_ count: Int, _ replacing: [Book]) async throws -> [Book]
    var saveReplacement: @Sendable (_ books: [Book], _ displayedCovers: [URL]) async throws -> CachedRecommendations
    
    static func live (
        recommendation: @escaping @Sendable (_ count: Int, _ replacing: [Book]) async throws -> [Book],
        cache: RecommendationCacheClient,
        initial: (@Sendable () async -> [Book])? = nil
    ) -> Self {
        Self(
            restore: { covers in
            await cache.retainDisplayedCovers(covers)
            if let cached = try? await cache.restore() { return cached }
            guard let initial else { return nil }
            let books = await initial()
            guard !books.isEmpty else { return nil }
            return CachedRecommendations(books: books, savedAt: .distantPast, coverFiles: [:])
        },
        refresh: { count, displayedCovers in
            let books = try await recommendation(count, [])
            try Task.checkCancellation()
            guard !books.isEmpty else { throw HomeRecommendationForYouError.empty }
            await cache.retainDisplayedCovers(displayedCovers)
            return try await cache.prepare(books)
        },
        prepareReplacement: { count, replacing in
            let books = try await recommendation(count, replacing)
            try Task.checkCancellation()
            guard books.count == count else {
                throw HomeRecommendationForYouError.insufficientReplacements
            }
            return books
        },
        saveReplacement: { books, displayedCovers in
            try Task.checkCancellation()
            await cache.retainDisplayedCovers(displayedCovers)
            return try await cache.saveBooks(books)
        }
        )
    }
}

extension HomeRecommendationForYouClient: DependencyKey {
    static let liveValue = Self.live(
        recommendation: { count, replacing in
            try await BookRecommendationClient.fetchFromDataset(
                count: count, replacing: replacing,
                dataset: .liveValue, recentlyViewed: .liveValue, related: .liveValue
            )
        },
        cache: .liveValue,
        initial: {
            await BookRecommendationClient.initialDatasetPicks(
                dataset: .liveValue, count: DatasetRecommendation.displayCount
            )
        }
    )
    static let testValue = Self.live(recommendation: { _, _ in [] }, cache: .testValue)
}

nonisolated extension DependencyValues {
    var homeRecommendationForYouClient: HomeRecommendationForYouClient {
        get { self[HomeRecommendationForYouClient.self] }
        set { self[HomeRecommendationForYouClient.self] = newValue }
    }
}
