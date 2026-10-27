//
//  FoundationModelsClient.swift
//  2026-C6-M06-Fingerprint-library
//
//  Created by Youngmin Cho on 10/15/26.
//

import Foundation
import ComposableArchitecture
import FoundationModels
// FoundationModels: 기기 안에서 도는 Apple 언어 모델. 네트워크 없이 동작한다.

nonisolated struct FoundationModelsClient: Sendable {
// 추천에 쓰는 기기 내 언어 모델 창구.
    var isAvailable: @Sendable () -> Bool
    // 모델을 지금 쓸 수 있는지. 미지원 기기·Apple Intelligence 꺼짐·모델 내려받는 중이면 false.
    var extractKeywords: @Sendable (_ prompt: String) async throws -> [String]
    // 사용자 데이터 문장을 넣으면 관심사 키워드를 돌려준다.
    var rankBooks: @Sendable (_ prompt: String) async throws -> [Int]
    // 번호 붙은 책 목록을 넣으면 추천 순서대로 번호(1부터)를 돌려준다.
}

extension FoundationModelsClient: DependencyKey {
    static let liveValue = Self(
        isAvailable: {
            SystemLanguageModel.default.availability == .available
        },
        extractKeywords: { prompt in
            let session = LanguageModelSession(instructions: PersonalizedRecommendation.keywordInstructions)
            // 요청마다 새 대화를 연다. 이전 요청 내용이 다음 판단에 섞이지 않게.
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

extension DependencyValues {
    var foundationModelsClient: FoundationModelsClient {
        get { self[FoundationModelsClient.self] }
        set { self[FoundationModelsClient.self] = newValue }
    }
}

@Generable
// 모델이 이 구조 그대로 답하게 한다. 자유 문장을 해석할 필요가 없다.
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
