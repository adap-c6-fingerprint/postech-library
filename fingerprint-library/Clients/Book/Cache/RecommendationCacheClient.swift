import ComposableArchitecture
import Foundation
import UIKit

nonisolated struct RecommendationCacheClient: Sendable {
    var restore: @Sendable () async throws -> CachedRecommendations?
    var prepare: @Sendable ([Book]) async throws -> CachedRecommendations
    var retainDisplayedCovers: @Sendable ([URL]) async -> Void = { _ in }
}

extension RecommendationCacheClient: DependencyKey {
    static let liveValue = Self(
        restore: { try await store.restore() },
        prepare: { try await preparer.prepare($0) },
        retainDisplayedCovers: { await store.retainDisplayedCovers($0) }
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
            // 표지 선택 정책 변경: 이전 저해상도 파일 대신 새 묶음을 준비한다.
            .appendingPathComponent("RecommendationCache-v2", isDirectory: true)
    )

    private static let preparer = RecommendationCachePreparer(store: store, loadCover: BookCoverClient.liveValue.pngData)
    // .shared를 직접 호출하지 않고 BookCoverClient만 넘겨줌
}

extension DependencyValues {
    var recommendationCacheClient: RecommendationCacheClient {
        get { self[RecommendationCacheClient.self] }
        set { self[RecommendationCacheClient.self] = newValue }
    }
}
