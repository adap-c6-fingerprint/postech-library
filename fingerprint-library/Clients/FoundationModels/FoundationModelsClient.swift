//
//  FoundationModelsClient.swift
//  2026-C6-M06-Fingerprint-library
//
//  Created by Youngmin Cho on 10/15/26.
//

import Foundation
import ComposableArchitecture
import FoundationModels

nonisolated struct FoundationModelsClient: Sendable {
    var isAvailable: @Sendable () -> Bool
    var extractKeywords: @Sendable (_ prompt: String) async throws -> [String]
    var rankBooks: @Sendable (_ prompt: String) async throws -> [Int]
}

extension FoundationModelsClient: DependencyKey {
    static let liveValue = Self(
        isAvailable: {
            SystemLanguageModel.default.availability == .available
        },
        extractKeywords: { prompt in
            let session = LanguageModelSession(instructions: PersonalizedRecommendation.keywordInstructions)
            return try await session.respond(to: prompt, generating: InterestKeywords.self).content.keywords
        },
        rankBooks: { prompt in
            let session = LanguageModelSession(instructions: PersonalizedRecommendation.rankingInstructions)
            return try await session.respond(to: prompt, generating: BookRanking.self).content.order
        }
    )
    static let testValue = Self(
        isAvailable: { false },
        extractKeywords: { _ in [] },
        rankBooks: { _ in [] }
    )
}

nonisolated extension DependencyValues {
    nonisolated var foundationModelsClient: FoundationModelsClient {
        get { self[FoundationModelsClient.self] }
        set { self[FoundationModelsClient.self] = newValue }
    }
}

@Generable
nonisolated struct InterestKeywords {
    @Guide(description: "사용자 관심 주제 키워드. 한두 단어 명사.", .count(PersonalizedRecommendation.keywordCount))
    var keywords: [String]
}

@Generable
nonisolated struct BookRanking {
    @Guide(
        description: "추천 순서대로 나열한 책 번호",
        .maximumCount(PersonalizedRecommendation.primoFetchCount),
        .element(.range(1...PersonalizedRecommendation.primoFetchCount))
    )
    var order: [Int]
}
