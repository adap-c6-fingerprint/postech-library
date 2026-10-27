import ComposableArchitecture
import Foundation
import UIKit

nonisolated struct RecommendationCacheClient: Sendable {
    var restore: @Sendable () async throws -> CachedRecommendations?
    var prepare: @Sendable ([Book]) async throws -> CachedRecommendations
}

extension RecommendationCacheClient: DependencyKey {
    static let liveValue = Self(
        restore: { try await store.restore() },
        prepare: { try await preparer.prepare($0) }
    )
    static let testValue = Self(
        restore: { nil },
        prepare: { books in
            CachedRecommendations(
                books: books, savedAt: .distantPast,
                coverFiles: Dictionary(uniqueKeysWithValues: Set(books.compactMap(\.imageURL)).map { ($0, $0) })
            )
        }
    )

    private static let store = RecommendationCacheStore(
        directory: URL.applicationSupportDirectory
            .appendingPathComponent("RecommendationCache", isDirectory: true)
    )

    private static let preparer = RecommendationCachePreparer(store: store, loadCover: { url in
        // 화면에서 이미 받았거나 받고 있는 표지는 기존 공통 로더의 결과를 공유한다.
        let image = try await BookCoverPipeline.shared.image(for: url)
        guard let data = await MainActor.run(body: { image.pngData() }) else {
            throw RecommendationCacheStore.CacheError.invalidImage
        }
        return data
    })
}

extension DependencyValues {
    var recommendationCacheClient: RecommendationCacheClient {
        get { self[RecommendationCacheClient.self] }
        set { self[RecommendationCacheClient.self] = newValue }
    }
}
