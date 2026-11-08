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
            CachedRecommendations(books: books, savedAt: .distantPast, coverFiles: [:])
        }
    )

    private static let store = RecommendationCacheStore(
        directory: URL.applicationSupportDirectory
            // 표지 선택 정책 변경: 이전 저해상도 파일 대신 새 묶음을 준비한다.
            .appendingPathComponent("RecommendationCache-v3", isDirectory: true)
            // ✅ 이슈 #237: LCC 관심사로 만든 이전 추천 저장본을 새 하드데이터 추천과 섞지 않는다.
    )

    private static let preparer = RecommendationCachePreparer(
        store: store, loadCover: BookCoverClient.liveValue.pngData,
        lookupYes24: { try await BookCoverPipeline.yes24Cover.url(for: $0) }
    )
}

extension DependencyValues {
    var recommendationCacheClient: RecommendationCacheClient {
        get { self[RecommendationCacheClient.self] }
        set { self[RecommendationCacheClient.self] = newValue }
    }
}
