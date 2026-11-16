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

nonisolated struct HomeRecommendationForYouClient: Sendable {
    var restore: @Sendable (_ displayedCovers: [URL]) async -> CachedRecommendations?
    var refresh: @Sendable (_ count: Int, _ displayedCovers: [URL])
        -> AsyncThrowingStream<RecommendationPreparationEvent, Error>
    var prepareReplacement: @Sendable (_ count: Int, _ replacing: [Book]) async throws -> [Book]
    var saveReplacement: @Sendable (_ books: [Book], _ displayedCovers: [URL]) async throws -> CachedRecommendations

    static func live (
        recommendation: @escaping @Sendable (_ count: Int, _ replacing: [Book]) async throws -> [Book],
        cache: RecommendationCacheClient,
        initial: (@Sendable () async -> [Book])? = nil,
        offlinePicks: @escaping @Sendable (_ count: Int) async -> [Book] = { _ in [] }
    ) -> Self {
        Self(
            restore: { covers in
            await cache.retainDisplayedCovers(covers)
            if let cached = try? await cache.restore() { return cached }
            guard let initial else { return nil }
            let books = await initial()
            guard !books.isEmpty else { return nil }
            return CachedRecommendations(books: books, savedAt: .distantPast, coverFiles: [:])
        },
        refresh: { count, displayedCovers in
            AsyncThrowingStream { continuation in
                let task = Task {
                    do {
                        let candidates = try await recommendation(count + DatasetRecommendation.coverCheckSpareCount, [])
                        try Task.checkCancellation()
                        guard !candidates.isEmpty else { throw HomeRecommendationForYouError.empty }
                        await cache.retainDisplayedCovers(displayedCovers)
                        var prepared: [Book] = []
                        do {
                            for try await event in cache.prepareStream(candidates, count) {
                                if case let .book(book, _) = event { prepared.append(book) }
                                continuation.yield(event)
                            }
                        } catch RecommendationPreparationError.offline {
                            let picks = await offlinePicks(count + prepared.count)
                            let excludedKeys = Set(prepared.flatMap { DatasetRecommendation.identityKeys(of: $0) })
                            let fallback = DatasetRecommendation.assemble(
                                candidatesPerSource: [], fallback: picks,
                                count: count - prepared.count, excluding: excludedKeys
                            )
                            try Task.checkCancellation()
                            continuation.yield(.offline(fallback: fallback))
                        } catch RecommendationPreparationError.noCoveredBooks {
                            throw HomeRecommendationForYouError.empty
                        }
                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }
                continuation.onTermination = { _ in task.cancel() }
            }
        },
        // 표지 확인된 책부터 내보낸다. 오프라인이면 하드데이터 책으로 남은 칸을 채우고 스냅샷은 저장하지 않는다.
        prepareReplacement: { count, replacing in
            let candidates = try await recommendation(count + DatasetRecommendation.coverCheckSpareCount, replacing)
            try Task.checkCancellation()
            let books = try await cache.verifyCovers(candidates, count)
            try Task.checkCancellation()
            guard books.count == count else {
                throw HomeRecommendationForYouError.insufficientReplacements
            }
            return books
        },
        saveReplacement: { books, displayedCovers in
            try Task.checkCancellation()
            await cache.retainDisplayedCovers(displayedCovers)
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
        },
        offlinePicks: { count in
            await BookRecommendationClient.initialDatasetPicks(dataset: .liveValue, count: count)
        }
    )
    static let testValue = Self.live(recommendation: { _, _ in [] }, cache: .testValue)
}

nonisolated extension DependencyValues {
    var homeRecommendationForYouClient: HomeRecommendationForYouClient {
        get { self[HomeRecommendationForYouClient.self] }
        set { self[HomeRecommendationForYouClient.self] = newValue }
    }
}
