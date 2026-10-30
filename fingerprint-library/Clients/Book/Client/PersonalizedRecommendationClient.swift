//
//  PersonalizedRecommendationClient.swift
//  fingerprint-library
//

import Foundation
import ComposableArchitecture

nonisolated struct PersonalizedRecommendationClient: Sendable {
// 찜·검색 기록 기반 추천 도서를 가져오는 창구.
    var fetch: @Sendable (_ input: PersonalizedRecommendationInput) async throws -> [RecommendedBook]
    // 사용자 데이터를 넣으면 추천 도서(최대 6권)를 돌려준다.
}

extension PersonalizedRecommendationClient: DependencyKey {
    static let liveValue = Self(fetch: { input in
        guard let primoKey = await AppConfiguration.primoAPIKey else {
            throw RecommendationClientError.missingPrimoAPIKey
        }
        guard let data4LibraryKey = await AppConfiguration.data4LibraryAPIKey else {
            throw RecommendationClientError.missingData4LibraryAPIKey
        }
        @Dependency(\.foundationModelsClient) var model
        @Dependency(\.httpClient) var httpClient
        let primo = PrimoAPIClient(httpClient: httpClient, apiKey: primoKey)
        return try await PersonalizedRecommendationService.recommend(
            input,
            dependencies: .init(
                model: model,
                searchPrimo: { query, limit in
                    try await primo.searchData(query: query, resourceTypes: ["printed_book"], limit: limit)
                },
                covers: .live(
                    httpClient: httpClient, data4LibraryAPIKey: data4LibraryKey,
                    minimumImageBytes: ColdStartRecommendation.minimumCoverBytes
                )
            )
        )
    })
    // 실제 앱: 기기 내 모델, 포스텍 API, 정보나루 API를 쓴다.
    static let testValue = Self(fetch: { _ in [] })
    // 테스트: 항상 빈 결과.
}

extension DependencyValues {
    var personalizedRecommendationClient: PersonalizedRecommendationClient {
        get { self[PersonalizedRecommendationClient.self] }
        set { self[PersonalizedRecommendationClient.self] = newValue }
    }
}

nonisolated enum PersonalizedRecommendationError: Error, Equatable {
    case noKeywords
    // 찜·검색 기록에서 검색 키워드를 하나도 만들지 못함.
}

nonisolated enum PersonalizedRecommendationService {

    nonisolated struct Dependencies: Sendable {
    // 바깥 시스템 호출 묶음. 테스트에서 가짜로 바꿔 끼운다.
        var model: FoundationModelsClient
        var searchPrimo: @Sendable (_ query: String, _ limit: Int) async throws -> Data
        var covers: RecommendationCoverResolver
    }

    static func recommend(
        _ input: PersonalizedRecommendationInput,
        dependencies: Dependencies
    ) async throws -> [RecommendedBook] {
    // 전체 흐름을 실행한다.
        let mmsIDs = PersonalizedRecommendation.favoriteMMSIDs(input.favoriteKeys)
        var favoriteTitles = PersonalizedRecommendation.favoriteMetadataTitles(input.favoriteKeys)
        if !mmsIDs.isEmpty {
            let data = try? await dependencies.searchPrimo(
                PersonalizedRecommendation.primoRecordQuery(mmsIDs), mmsIDs.count
            )
            favoriteTitles += data.flatMap { try? PrimoRecommendationMapper.titles(from: $0) } ?? []
        }
        // ① 찜 목록은 책 ID만 저장돼 있어서, 포스텍 API로 제목을 한 번에 조회한다.
        // 조회에 실패해도 최근 검색어만으로 계속 진행한다.

        let keywords = await keywords(
            favoriteTitles: favoriteTitles,
            recentQueries: input.recentQueries,
            model: dependencies.model
        )
        guard !keywords.isEmpty else { throw PersonalizedRecommendationError.noKeywords }
        // ② 모델이 관심사 키워드 5개를 뽑는다.

        let candidates = try PrimoRecommendationMapper.personalizedCandidates(from:
            try await dependencies.searchPrimo(
                PersonalizedRecommendation.primoKeywordQuery(keywords),
                PersonalizedRecommendation.primoFetchCount
            )
        )
        // ③ 키워드를 OR로 묶어 포스텍에서 50권을 받는다.

        let interestCodes = ColdStartRecommendation.normalizedCodes(input.interests)
        let modelOrder = await ranking(
            candidates,
            keywords: keywords,
            interestCodes: interestCodes,
            model: dependencies.model
        )
        let ranked = PersonalizedRecommendation.prioritized(
            candidates,
            ranking: PersonalizedRecommendation.mergedRanking(modelOrder: modelOrder, count: candidates.count),
            interestCodes: interestCodes
        )
        // ④ 모델이 관련도 순으로 정렬하고, 관심 분류에 속한 책을 앞으로 모은다.

        return await RecommendationCoverSelector.select(
            ranked.map(RecommendationCoverSelector.Candidate.init),
            policy: .preserveRanking,
            limit: ColdStartRecommendation.resultCount,
            batchSize: ColdStartRecommendation.coverBatchSize,
            resolver: dependencies.covers
        )
        // ⑤ 우선순위 순서대로 표지를 확인해 표지 있는 상위 6권을 돌려준다.
    }

    // MARK: - 모델 호출

    private static func keywords(
        favoriteTitles: [String],
        recentQueries: [String],
        model: FoundationModelsClient
    ) async -> [String] {
    // 모델로 키워드를 뽑는다. 모델을 못 쓰거나 실패하면 검색어·제목을 그대로 키워드로 쓴다.
        let fallback = PersonalizedRecommendation.fallbackKeywords(
            favoriteTitles: favoriteTitles,
            recentQueries: recentQueries
        )
        guard model.isAvailable() else { return fallback }
        let prompt = PersonalizedRecommendation.keywordPrompt(
            favoriteTitles: favoriteTitles,
            recentQueries: recentQueries
        )
        guard let raw = try? await model.extractKeywords(prompt) else { return fallback }
        let keywords = PersonalizedRecommendation.normalizedKeywords(raw)
        return keywords.isEmpty ? fallback : keywords
    }

    private static func ranking(
        _ candidates: [PersonalizedCandidate],
        keywords: [String],
        interestCodes: [String],
        model: FoundationModelsClient
    ) async -> [Int] {
    // 모델로 순서를 정한다. 모델을 못 쓰거나 실패하면 빈 배열 → 포스텍 검색 순서를 그대로 쓴다.
        guard model.isAvailable(), !candidates.isEmpty else { return [] }
        let prompt = PersonalizedRecommendation.rankingPrompt(
            candidates,
            keywords: keywords,
            interestCodes: interestCodes
        )
        return (try? await model.rankBooks(prompt)) ?? []
    }

}
