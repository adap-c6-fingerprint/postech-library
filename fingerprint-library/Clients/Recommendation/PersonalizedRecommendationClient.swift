//
//  PersonalizedRecommendationClient.swift
//  fingerprint-library
//

import Foundation
import ComposableArchitecture

nonisolated struct PersonalizedRecommendationClient: Sendable {
    var fetch: @Sendable (_ input: PersonalizedRecommendationInput) async throws -> [RecommendedBook]
}

extension PersonalizedRecommendationClient: DependencyKey {
    static let liveValue = Self(fetch: { input in
        @Dependency(\.foundationModelsClient) var model
        @Dependency(\.httpClient) var httpClient
        let primo = PrimoAPIClient(relay: .init(httpClient: httpClient))
        return try await PersonalizedRecommendationService.recommend(
            input,
            dependencies: .init(
                model: model,
                searchPrimo: { query, limit in
                    try await primo.searchData(query: query, resourceTypes: ["printed_book"], limit: limit)
                },
                covers: .live(
                    httpClient: httpClient,
                    minimumImageBytes: ColdStartRecommendation.minimumCoverBytes
                )
            )
        )
    })
    static let testValue = Self(fetch: { _ in [] })
}

nonisolated extension DependencyValues {
    var personalizedRecommendationClient: PersonalizedRecommendationClient {
        get { self[PersonalizedRecommendationClient.self] }
        set { self[PersonalizedRecommendationClient.self] = newValue }
    }
}

nonisolated enum PersonalizedRecommendationError: Error, Equatable {
    case noKeywords
}

nonisolated enum PersonalizedRecommendationService {

    nonisolated struct Dependencies: Sendable {
        var model: FoundationModelsClient
        var searchPrimo: @Sendable (_ query: String, _ limit: Int) async throws -> Data
        var covers: RecommendationCoverResolver
    }

    static func recommend(
        _ input: PersonalizedRecommendationInput,
        dependencies: Dependencies
    ) async throws -> [RecommendedBook] {
        let mmsIDs = PersonalizedRecommendation.favoriteMMSIDs(input.favoriteKeys)
        var favoriteTitles = PersonalizedRecommendation.favoriteMetadataTitles(input.favoriteKeys)
        if !mmsIDs.isEmpty {
            let data = try? await dependencies.searchPrimo(
                PersonalizedRecommendation.primoRecordQuery(mmsIDs), mmsIDs.count
            )
            favoriteTitles += data.flatMap { try? PrimoRecommendationMapper.titles(from: $0) } ?? []
        }

        let keywords = await keywords(
            favoriteTitles: favoriteTitles,
            recentQueries: input.recentQueries,
            model: dependencies.model
        )
        guard !keywords.isEmpty else { throw PersonalizedRecommendationError.noKeywords }

        let candidates = try PrimoRecommendationMapper.personalizedCandidates(from:
            try await dependencies.searchPrimo(
                PersonalizedRecommendation.primoKeywordQuery(keywords),
                PersonalizedRecommendation.primoFetchCount
            )
        )

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

        return await RecommendationCoverSelector.select(
            ranked.map(RecommendationCoverSelector.Candidate.init),
            policy: .preserveRanking,
            limit: ColdStartRecommendation.resultCount,
            batchSize: ColdStartRecommendation.coverBatchSize,
            resolver: dependencies.covers
        )
    }

    private static func keywords(
        favoriteTitles: [String],
        recentQueries: [String],
        model: FoundationModelsClient
    ) async -> [String] {
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
        guard model.isAvailable(), !candidates.isEmpty else { return [] }
        let prompt = PersonalizedRecommendation.rankingPrompt(
            candidates,
            keywords: keywords,
            interestCodes: interestCodes
        )
        return (try? await model.rankBooks(prompt)) ?? []
    }

}
