import Foundation
import Synchronization
import Testing
@testable import fingerprint_library

private final class CallCounter: Sendable {
    private let count = Mutex(0)
    var value: Int { count.withLock { $0 } }
    func increment() { count.withLock { $0 += 1 } }
}

@MainActor
struct DepartmentPopularBooksClientTests {
    private let path = RecommendationDataset.AffiliationPath(parent: "공과대학", group: "학과", name: "화학과")

    private func makeClient(relatedCalls: CallCounter) -> DepartmentPopularBooksClient {
        let books = (1...12).map(makeBook)
        let dataset = RecommendationDataset(
            books: Dictionary(uniqueKeysWithValues: books.map { ($0.id, $0) }),
            affiliations: [(path, books.map(\.id))],
            preferences: []
        )
        let related = HeldRelatedBooksClient(candidates: { _, _ in
            relatedCalls.increment()
            return []
        })
        return .dataset(dataset: .init(load: { dataset }), related: related)
    }

    @Test func 첫_목록은_연관도서_조회를_기다리지_않는다() async throws {
        let relatedCalls = CallCounter()
        let client = makeClient(relatedCalls: relatedCalls)

        let books = try await client.fetch(path.key, DatasetRecommendation.displayCount)

        #expect(books.count == DatasetRecommendation.displayCount)
        #expect(relatedCalls.value == 0)
    }

    @Test func 다음_묶음은_연관도서를_조회하고_표시중인_책을_제외한다() async throws {
        let relatedCalls = CallCounter()
        let client = makeClient(relatedCalls: relatedCalls)
        let displayed = try await client.fetch(path.key, DatasetRecommendation.displayCount)
        let excludedKeys = Set(displayed.flatMap(DatasetRecommendation.identityKeys(of:)))

        let next = try await client.prepareReplacement(
            path.key, DatasetRecommendation.displayCount, excludedKeys
        )

        #expect(next.count == DatasetRecommendation.displayCount)
        #expect(Set(next.map { $0.id }).isDisjoint(with: displayed.map { $0.id }))
        #expect(relatedCalls.value == DatasetRecommendation.displayCount)
    }
}
