import ComposableArchitecture
import Foundation
import UIKit

nonisolated struct RecommendationCacheClient: Sendable {
    var restore: @Sendable () async throws -> CachedRecommendations?
    var prepare: @Sendable ([Book]) async throws -> CachedRecommendations
    var retainDisplayedCovers: @Sendable ([URL]) async -> Void = { _ in }
    var saveBooks: @Sendable ([Book]) async throws -> CachedRecommendations = { books in
        CachedRecommendations(books: books, savedAt: .distantPast, coverFiles: [:])
    }
}

extension RecommendationCacheClient: DependencyKey {
    static let liveValue = Self(
        restore: { try await store.restore() },
        prepare: { try await preparer.prepare($0) },
        retainDisplayedCovers: { await store.retainDisplayedCovers($0) },
        saveBooks: { books in
            try await store.save(books: books, covers: [:], savedAt: Date())
        }
    )
    static let testValue = Self(
        restore: { nil },
        prepare: { books in
            CachedRecommendations(books: books, savedAt: .distantPast, coverFiles: [:])
        }
    )

    nonisolated private static let store = RecommendationCacheStore(
        directory: URL.applicationSupportDirectory
            .appendingPathComponent("RecommendationCache-v3", isDirectory: true)
    )

    nonisolated private static let preparer = RecommendationCachePreparer(
        store: store, loadCover: { try await BookCoverClient.liveValue.pngData($0) },
        lookupYes24: { try await BookCoverPipeline.yes24Cover.url(for: $0) }
    )
}

nonisolated extension DependencyValues {
    var recommendationCacheClient: RecommendationCacheClient {
        get { self[RecommendationCacheClient.self] }
        set { self[RecommendationCacheClient.self] = newValue }
    }
}
