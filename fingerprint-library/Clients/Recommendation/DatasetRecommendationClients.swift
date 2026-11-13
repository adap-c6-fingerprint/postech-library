//
//  DatasetRecommendationClients.swift
//  fingerprint-library
//
//  ✅ 이슈 #237: 홈 추천 두 영역을 하드데이터 기반으로 바꾸는 구현.
//  - 개인별 추천(당신을 위한 추천): 선택한 선호 분류의 목록 + 최근 조회 도서의 연관도서
//  - 학과별 추천(소속 추천 도서): 선택한 소속의 목록 + 연관도서
//  기존 Foundation Model·콜드스타트 추천은 호출만 끊고 코드는 남긴다. (Q9)
//

import ComposableArchitecture
import Foundation

extension BookRecommendationClient {
    nonisolated static func fetchFromDataset(
        count: Int,
        replacing displayedBooks: [Book],
        dataset: RecommendationDatasetClient,
        recentlyViewed: RecentlyViewedBooksClient,
        related: HeldRelatedBooksClient
    ) async throws -> [Book] {
        guard count > 0 else { return [] }
        let isCarouselRefresh = !displayedBooks.isEmpty
        let recent = recentlyViewed.load()
        let anchors = recent + Array(displayedBooks.reversed())
        let pool = try await personalPool(dataset: dataset, matching: isCarouselRefresh ? anchors : nil)
        let excludedKeys = Set(displayedBooks.flatMap { DatasetRecommendation.identityKeys(of: $0) })
        var generator = SystemRandomNumberGenerator()
        let fallback = pool.shuffled(using: &generator)
        let history = isCarouselRefresh
            ? recent + displayedBooks.reversed().filter { book in !recent.contains { $0.id == book.id } }
            : recent
        if isCarouselRefresh {
            let matching = DatasetRecommendation.assemble(
                candidatesPerSource: [], fallback: fallback, count: count, excluding: excludedKeys
            )
            if matching.count == count { return matching }
        } else if history.isEmpty {
            return Array(fallback.prefix(count))
        }

        let sources = DatasetRecommendation.personalSources(
            recent: history, pool: pool, count: count, using: &generator
        )
        return await RelatedRecommendationAssembler.assemble(
            sources: sources.history + sources.pool, fallback: fallback,
            count: count, related: related, excluding: excludedKeys,
            includesRemainingRelatedBooks: isCarouselRefresh
        )
    }

    nonisolated static func initialDatasetPicks(
        dataset: RecommendationDatasetClient, count: Int
    ) async -> [Book] {
        guard let pool = try? await personalPool(dataset: dataset) else { return [] }
        var generator = SystemRandomNumberGenerator()
        return DatasetRecommendation.randomPicks(from: pool, count: count, using: &generator)
    }

    private nonisolated static func personalPool(
        dataset: RecommendationDatasetClient, matching anchors: [Book]? = nil
    ) async throws -> [Book] {
        @Shared(.userProfile) var userProfile: UserProfile?
        let preferences = userProfile?.interests ?? []
        let data = try await dataset.load()
        if !preferences.isEmpty { return data.books(forPreferences: preferences) }
        if let anchors { return data.books(inSamePreferencesAs: anchors) }
        return data.allBooks
    }
}

extension DepartmentPopularBooksClient {
    nonisolated static func dataset(
        dataset: RecommendationDatasetClient, related: HeldRelatedBooksClient
    ) -> Self {
        let fetchAll: @Sendable ([String]) async throws -> [Book] = { affiliationKey in
            let data = try await dataset.load()
            guard let path = RecommendationDataset.AffiliationPath(key: affiliationKey) else {
                var generator = SystemRandomNumberGenerator()
                return DatasetRecommendation.randomPicks(
                    from: data.allBooks, count: DatasetRecommendation.fallbackListCount, using: &generator
                )
            }
            return data.books(forAffiliation: path)
        }
        return Self(fetch: { affiliationKey, count, isInitial in
            guard count > 0 else { return [] }
            let pool = try await fetchAll(affiliationKey)
            var generator = SystemRandomNumberGenerator()
            let sources = DatasetRecommendation.randomPicks(from: pool, count: count, using: &generator)
            guard !isInitial else { return sources }
            let fallback = pool.shuffled(using: &generator)
            return await RelatedRecommendationAssembler.assemble(
                sources: sources, fallback: fallback, count: count, related: related
            )
        }, fetchAll: fetchAll)
    }
}
