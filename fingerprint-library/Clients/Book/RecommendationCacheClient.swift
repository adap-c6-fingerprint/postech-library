import ComposableArchitecture
import Foundation

nonisolated struct RecommendationCacheClient: Sendable {
    var restore: @Sendable () async throws -> CachedRecommendations?
}

extension RecommendationCacheClient: DependencyKey {
    static let liveValue = Self(restore: { try await store.restore() })
    static let testValue = Self(restore: { nil })

    private static let store = RecommendationCacheStore(
        directory: URL.applicationSupportDirectory
            .appendingPathComponent("RecommendationCache", isDirectory: true)
    )
}

extension DependencyValues {
    var recommendationCacheClient: RecommendationCacheClient {
        get { self[RecommendationCacheClient.self] }
        set { self[RecommendationCacheClient.self] = newValue }
    }
}
