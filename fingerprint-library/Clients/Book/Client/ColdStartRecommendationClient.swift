import Foundation
import ComposableArchitecture

nonisolated struct ColdStartRecommendationClient: Sendable {
    var fetch: @Sendable (_ interests: [String]) async throws -> [RecommendedBook]
}

extension ColdStartRecommendationClient: DependencyKey {
    static let liveValue = Self(fetch: { interests in
        guard !ColdStartRecommendation.normalizedCodes(interests).isEmpty else {
            throw RecommendationClientError.noInterests
        }
        @Dependency(\.httpClient) var httpClient
        let primo = PrimoAPIClient(relay: .init(httpClient: httpClient))
        return try await ColdStartRecommendationService.recommend(
            interests: interests,
            dependencies: .init(
                searchPrimo: { query, offset in
                    try await primo.searchData(
                        query: query, resourceTypes: ["printed_book"], offset: offset,
                        limit: ColdStartRecommendation.primoFetchCount
                    )
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

extension DependencyValues {
    var coldStartRecommendationClient: ColdStartRecommendationClient {
        get { self[ColdStartRecommendationClient.self] }
        set { self[ColdStartRecommendationClient.self] = newValue }
    }
}

/// 첫 추천의 페이지 선택·후보 누적·표지 선정 순서만 조정한다.
nonisolated enum ColdStartRecommendationService {
    nonisolated struct Dependencies: Sendable {
        var searchPrimo: @Sendable (_ query: String, _ offset: Int) async throws -> Data
        var covers: RecommendationCoverResolver
        var chooseOffset: @Sendable (_ total: Int) -> Int = { total in
            var generator = SystemRandomNumberGenerator()
            return ColdStartRecommendation.randomOffset(total: total, using: &generator)
        }
    }

    static func recommend(interests: [String], dependencies: Dependencies) async throws -> [RecommendedBook] {
        let codes = ColdStartRecommendation.normalizedCodes(interests)
        guard !codes.isEmpty else { throw RecommendationClientError.noInterests }
        let query = ColdStartRecommendation.primoQuery(for: codes)
        let firstData = try await dependencies.searchPrimo(query, 0)
        let first = try PrimoRecommendationMapper.coldStartPage(from: firstData, codes: codes)
        var result: [RecommendedBook] = []
        var usedRecordIDs = Set<String>()

        for _ in 0...ColdStartRecommendation.extraPageLimit {
            let offset = dependencies.chooseOffset(first.total)
            let page: PrimoCandidatePage
            if offset == 0 {
                page = first
            } else {
                let data = try await dependencies.searchPrimo(query, offset)
                page = try PrimoRecommendationMapper.coldStartPage(from: data, codes: codes)
            }
            let fresh = page.candidates.filter { usedRecordIDs.insert($0.recordID).inserted }.shuffled()
            result += await RecommendationCoverSelector.select(
                fresh.map(RecommendationCoverSelector.Candidate.init),
                policy: .preferData4Library,
                limit: ColdStartRecommendation.resultCount - result.count,
                batchSize: ColdStartRecommendation.coverBatchSize,
                resolver: dependencies.covers
            )
            if result.count >= ColdStartRecommendation.resultCount
                || first.total <= ColdStartRecommendation.primoFetchCount { break }
        }
        return result
    }
}
