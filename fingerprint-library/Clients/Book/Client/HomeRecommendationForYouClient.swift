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

// 홈 화면 '당신을 위한 추천 6선' 아크릴판 도서 클라이언트
nonisolated struct HomeRecommendationForYouClient: Sendable {
    var restore: @Sendable (_ displayedCovers: [URL]) async -> CachedRecommendations?
    // 저장해 둔 추천을 현재 표지 주소 목록(displayedCovers)으로 꺼냄(restore)
    var refresh: @Sendable (_ count: Int, _ displayedCovers: [URL]) async throws -> CachedRecommendations
    var prepareReplacement: @Sendable (_ count: Int, _ replacing: [Book]) async throws -> [Book]
    var saveReplacement: @Sendable (_ books: [Book], _ displayedCovers: [URL]) async throws -> CachedRecommendations
    
    static func live (
        recommendation: @escaping @Sendable (_ count: Int, _ replacing: [Book]) async throws -> [Book],
        cache: RecommendationCacheClient,
        initial: (@Sendable () async -> [Book])? = nil
        // ✅ 저장본이 없을 때(온보딩 직후) 네트워크 없이 바로 보여줄 목록. nil이면 기존처럼 refresh를 기다린다.
    ) -> Self {
        // 추천 클라이언트, 추천 캐시 클라이언트를 바깥에서 받아옴
        Self(
            restore: { covers in
            await cache.retainDisplayedCovers(covers)
                // 저장본이 손상되어도 캐시가 없는 경우와 같은 최초 조회 경로로 복구
            if let cached = try? await cache.restore() { return cached }
            // ✅ 저장본이 없으면 하드데이터 목록을 바로 돌려준다. 표지는 원격 URL 그대로 표시한다.
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
            // 스크롤로 교체할 때는 책부터 표시하고 각 표지는 기존 카드 로딩에 맡긴다.
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
    // ✅ 이슈 #237: Foundation Model·콜드스타트 추천(BookRecommendationClient.liveValue) 대신 하드데이터 추천을 쓴다. (Q9)
    static let testValue = Self.live(recommendation: { _, _ in [] }, cache: .testValue)
}

extension DependencyValues {
    var homeRecommendationForYouClient: HomeRecommendationForYouClient {
        get { self[HomeRecommendationForYouClient.self] }
        set { self[HomeRecommendationForYouClient.self] = newValue }
    }
}
