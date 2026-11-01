import Foundation
import Testing
@testable import fingerprint_library

// ✅ 이슈 #237: 하드데이터 추천 규칙(4절)을 네트워크 없이 검증한다.
@MainActor
struct DatasetRecommendationTests {
    /// 테스트마다 같은 결과가 나오도록 고정한 난수 생성기.
    struct SeededGenerator: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return state
        }
    }

    // 체크섬이 맞는 ISBN-13을 만든다.
    static func isbn(_ number: Int) -> String {
        let prefix = "978" + String(format: "%09d", number)
        let sum = prefix.enumerated().reduce(0) {
            $0 + ($1.element.wholeNumberValue ?? 0) * ($1.offset.isMultiple(of: 2) ? 1 : 3)
        }
        return prefix + String((10 - sum % 10) % 10)
    }

    static func book(_ id: String, isbn: String?) -> Book {
        Book(
            id: id, isbn: isbn, controlNumber: id, title: id, author: "저자",
            publisher: nil, publicationYear: nil, description: nil, imageURL: nil
        )
    }

    static let pool = (1...20).map { book("primo:alma\($0)", isbn: isbn($0)) }

    @Test("최초 접속은 20권 중 중복 없이 6권을 고른다")
    func initialPicks() {
        var generator = SeededGenerator(state: 1)
        let picks = DatasetRecommendation.randomPicks(from: Self.pool, using: &generator)
        #expect(picks.count == 6)
        #expect(Set(picks.map(\.id)).count == 6)
        #expect(picks.allSatisfy { Self.pool.contains($0) })
    }

    @Test("최근 조회 권수에 따라 조회 도서와 하드데이터 원본 수가 정해진다", arguments: [
        (1, 1, 5), (2, 2, 4), (3, 3, 3), (5, 3, 3)
    ])
    func personalSourceCounts(recentCount: Int, fromHistory: Int, fromPool: Int) {
        var generator = SeededGenerator(state: 2)
        let recent = (100..<(100 + recentCount)).map { Self.book("recent\($0)", isbn: Self.isbn($0)) }
        let sources = DatasetRecommendation.personalSources(recent: recent, pool: Self.pool, using: &generator)
        #expect(sources.history.count == fromHistory)
        #expect(sources.pool.count == fromPool)
        // 최근에 본 책부터 쓴다.
        #expect(sources.history == Array(recent.prefix(fromHistory)))
    }

    @Test("ISBN이 없는 조회 도서는 건너뛰고 다음 조회 도서를 쓴다")
    func skipsRecentWithoutISBN() {
        var generator = SeededGenerator(state: 3)
        let noISBN = Self.book("noISBN", isbn: nil)
        let withISBN = Self.book("withISBN", isbn: Self.isbn(200))
        let sources = DatasetRecommendation.personalSources(
            recent: [noISBN, withISBN], pool: Self.pool, using: &generator
        )
        #expect(sources.history == [withISBN])
        #expect(sources.pool.count == 5)
    }

    @Test("조회한 책이 하드데이터에도 있으면 같은 원본을 두 번 쓰지 않는다")
    func doesNotReuseViewedBookAsPoolSource() {
        var generator = SeededGenerator(state: 4)
        let viewed = Self.pool[0]
        let sources = DatasetRecommendation.personalSources(
            recent: [viewed], pool: Self.pool, using: &generator
        )
        #expect(!sources.pool.contains(viewed))
    }

    @Test("원본마다 1권씩 고르고, 겹치면 같은 원본의 다음 후보로 넘어간다")
    func assemblesWithoutDuplicates() {
        let a = Self.book("primo:almaA", isbn: Self.isbn(301))
        let b = Self.book("primo:almaB", isbn: Self.isbn(302))
        let c = Self.book("primo:almaC", isbn: Self.isbn(303))
        let result = DatasetRecommendation.assemble(
            candidatesPerSource: [[a, b], [a, c], [b]], fallback: [], count: 3
        )
        #expect(result == [a, c, b])
    }

    @Test("연관도서를 채우지 못한 자리는 하드데이터로 채워 6권을 맞춘다 (Q6)")
    func fillsWithFallback() {
        let a = Self.book("primo:almaA", isbn: Self.isbn(301))
        let result = DatasetRecommendation.assemble(
            candidatesPerSource: [[a], [], [], [], [], []], fallback: Self.pool, count: 6
        )
        #expect(result.count == 6)
        #expect(result.first == a)
        #expect(Array(result.dropFirst()) == Array(Self.pool.prefix(5)))
    }

    @Test("id가 달라도 ISBN이 같으면 같은 책으로 보고 한 번만 넣는다")
    func deduplicatesByISBN() {
        let first = Self.book("primo:alma1", isbn: Self.isbn(1))
        let sameISBN = Self.book("isbn:other", isbn: Self.isbn(1))
        let result = DatasetRecommendation.assemble(
            candidatesPerSource: [[first], [sameISBN]], fallback: [], count: 2
        )
        #expect(result == [first])
    }

    @Test("원본 책들의 후보를 동시에 받아 원본 순서대로 조립한다")
    func assemblerKeepsSourceOrder() async {
        let sources = Array(Self.pool.prefix(3))
        let related = HeldRelatedBooksClient(candidates: { source, _ in
            [Book(
                id: "related-\(source.id)", isbn: nil, controlNumber: nil, title: "연관", author: "저자",
                publisher: nil, publicationYear: nil, description: nil, imageURL: nil
            )]
        })
        let result = await RelatedRecommendationAssembler.assemble(
            sources: sources, fallback: [], count: 3, related: related
        )
        #expect(result.map(\.id) == sources.map { "related-\($0.id)" })
    }
}
