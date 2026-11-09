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
    /// 개인별 추천.
    /// - 조회 이력 없음: 하드데이터 20권에서 랜덤 6권
    /// - 조회 이력 있음: 최근 조회 최대 3권 + 하드데이터 랜덤으로 원본 6권 → 원본마다 연관도서 1권
    nonisolated static func dataset(
        dataset: RecommendationDatasetClient,
        recentlyViewed: RecentlyViewedBooksClient,
        related: HeldRelatedBooksClient
    ) -> Self {
        Self(fetch: { count in
            guard count > 0 else { return [] }
            let pool = try await personalPool(dataset: dataset)
            var generator = SystemRandomNumberGenerator()
            let recent = recentlyViewed.load()
            guard !recent.isEmpty else {
                return DatasetRecommendation.randomPicks(from: pool, count: count, using: &generator)
            }
            let sources = DatasetRecommendation.personalSources(
                recent: recent, pool: pool, count: count, using: &generator
            )
            let fallback = pool.shuffled(using: &generator)
            return await RelatedRecommendationAssembler.assemble(
                sources: sources.history + sources.pool, fallback: fallback, count: count, related: related
            )
        })
    }

    /// 온보딩 직후처럼 저장된 추천이 없을 때 네트워크 없이 바로 보여줄 랜덤 6권.
    nonisolated static func initialDatasetPicks(
        dataset: RecommendationDatasetClient, count: Int
    ) async -> [Book] {
        guard let pool = try? await personalPool(dataset: dataset) else { return [] }
        var generator = SystemRandomNumberGenerator()
        return DatasetRecommendation.randomPicks(from: pool, count: count, using: &generator)
    }

    /// 프로필에 저장한 선호 분류 목록을 합친 하드데이터. (Q3: recordID로 중복 제거)
    /// 관심 분야가 없으면(온보딩 건너뛰기) 하드데이터 전체.
    private nonisolated static func personalPool(dataset: RecommendationDatasetClient) async throws -> [Book] {
        let data = try await dataset.load()
        @Shared(.userProfile) var userProfile: UserProfile?
        // 앱 전체가 함께 쓰는 프로필에서 관심 분야를 읽는다. 마이페이지에서 바꾼 값이 다음 추천부터 바로 쓰인다.
        let preferences = userProfile?.interests ?? []
        guard !preferences.isEmpty else { return data.allBooks }
        // 온보딩을 건너뛰어 관심 분야가 없으면 하드데이터 전체를 후보로 쓴다. (이슈 #396)
        return data.books(forPreferences: preferences)
    }
}

extension DepartmentPopularBooksClient {
    /// 소속별 전체 목록과 홈 미리보기를 제공한다. 아래 규칙은 홈 미리보기에 적용된다.
    /// - 최초 접속(온보딩 직후 첫 표시): 소속 목록 20권에서 랜덤 6권 (Q4)
    /// - 이후 접속: 소속 목록에서 랜덤 6권 → 원본마다 연관도서 1권
    nonisolated static func dataset(
        dataset: RecommendationDatasetClient, related: HeldRelatedBooksClient
    ) -> Self {
        let fetchAll: @Sendable ([String]) async throws -> [Book] = { affiliationKey in
            guard let path = RecommendationDataset.AffiliationPath(key: affiliationKey) else {
                throw DepartmentPopularBooksError.missingAffiliation
            }
            return try await dataset.load().books(forAffiliation: path)
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

nonisolated enum DepartmentPopularBooksError: LocalizedError, Equatable {
    case missingAffiliation

    var errorDescription: String? {
        switch self {
        case .missingAffiliation: "소속 정보가 없어요. 온보딩에서 소속을 다시 골라주세요."
        }
    }
}
