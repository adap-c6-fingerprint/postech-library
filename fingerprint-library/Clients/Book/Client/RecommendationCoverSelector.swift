import Foundation

/// 조회 수단과 분리한 표지 선정 정책. 응답 완료 순서와 관계없이 후보 순서를 유지한다.
nonisolated enum RecommendationCoverSelector {
    nonisolated enum Policy: Sendable {
        case preferData4Library
        case preserveRanking
    }

    nonisolated struct Candidate: Sendable {
        let recordID: String
        let primoCoverURL: URL?
        let isbn13: String?

        init(_ candidate: ColdStartCandidate) {
            recordID = candidate.recordID
            primoCoverURL = candidate.primoCoverURL
            isbn13 = candidate.isbn13
        }

        init(_ candidate: PersonalizedCandidate) {
            recordID = candidate.recordID
            primoCoverURL = candidate.primoCoverURL
            isbn13 = candidate.isbn13
        }
    }

    static func select(
        _ candidates: [Candidate],
        policy: Policy,
        limit: Int,
        batchSize: Int,
        resolver: RecommendationCoverResolver
    ) async -> [RecommendedBook] {
        precondition(batchSize > 0)
        guard limit > 0 else { return [] }

        switch policy {
        case .preferData4Library:
            var result = await firstCovers(
                in: candidates.filter { $0.isbn13 != nil }, limit: limit, batchSize: batchSize
            ) { candidate in
                guard let isbn13 = candidate.isbn13 else { return nil }
                return await resolver.data4LibraryLookup(isbn13)
            }
            guard result.count < limit else { return result }

            let chosen = Set(result.map(\.recordID))
            let fallback = candidates.filter { $0.primoCoverURL != nil && !chosen.contains($0.recordID) }
            result += await firstCovers(in: fallback, limit: limit - result.count, batchSize: batchSize) {
                guard let url = $0.primoCoverURL else { return nil }
                return await resolver.isRealImage(url) ? url : nil
            }
            return result

        case .preserveRanking:
            return await firstCovers(in: candidates, limit: limit, batchSize: batchSize) { candidate in
                if let isbn13 = candidate.isbn13,
                   let url = await resolver.data4LibraryLookup(isbn13) { return url }
                guard let url = candidate.primoCoverURL else { return nil }
                return await resolver.isRealImage(url) ? url : nil
            }
        }
    }

    private static func firstCovers(
        in candidates: [Candidate],
        limit: Int,
        batchSize: Int,
        check: @escaping @Sendable (Candidate) async -> URL?
    ) async -> [RecommendedBook] {
        var result: [RecommendedBook] = []
        var start = 0
        while start < candidates.count, result.count < limit {
            let end = min(start + batchSize, candidates.count)
            let batch = Array(candidates[start..<end])
            let covers = await withTaskGroup(of: (Int, URL?).self) { group in
                for (index, candidate) in batch.enumerated() {
                    group.addTask { (index, await check(candidate)) }
                }
                var found: [Int: URL] = [:]
                for await (index, url) in group {
                    if let url { found[index] = url }
                }
                return found
            }
            result += batch.indices.compactMap { index in
                covers[index].map { RecommendedBook(recordID: batch[index].recordID, coverImageURL: $0) }
            }
            start = end
        }
        return Array(result.prefix(limit))
    }
}
