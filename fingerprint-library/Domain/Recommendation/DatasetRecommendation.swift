//
//  DatasetRecommendation.swift
//  fingerprint-library
//
//  ✅ 이슈 #237: 하드데이터 기반 추천 규칙. 네트워크 없이 테스트할 수 있도록 순수 함수로 둔다.
//

import Foundation

nonisolated enum DatasetRecommendation {
    static let displayCount = 6
    static let maxHistorySources = 3
    static let fallbackListCount = 20
    static let coverCheckSpareCount = 4
    // 6선 표지 확인에 실패한 책을 대신할 여분 후보 수

    static func coveredCandidates(from pool: [Book]) -> [Book] {
        pool.filter { $0.imageURL != nil }
    }
    // 6선 후보는 표지 URL이 있는 책만 쓴다. 학과별 추천·전체 보기에는 쓰지 않는다.

    static func randomPicks<G: RandomNumberGenerator>(
        from pool: [Book], count: Int = displayCount, using generator: inout G
    ) -> [Book] {
        Array(pool.shuffled(using: &generator).prefix(max(count, 0)))
    }

    static func personalSources<G: RandomNumberGenerator>(
        recent: [Book], pool: [Book], count: Int = displayCount, using generator: inout G
    ) -> (history: [Book], pool: [Book]) {
        let history = Array(recent.filter(hasISBN).prefix(min(maxHistorySources, count)))
        let historyISBNs = Set(history.compactMap { BookISBN.isbn13(from: $0.isbn) })
        let candidates = pool.filter { book in
            guard let isbn = BookISBN.isbn13(from: book.isbn) else { return false }
            return !historyISBNs.contains(isbn)
        }
        let fromPool = randomPicks(from: candidates, count: count - history.count, using: &generator)
        return (history, fromPool)
    }

    static func assemble(
        candidatesPerSource: [[Book]], fallback: [Book], count: Int = displayCount,
        excluding excludedKeys: Set<String> = []
    ) -> [Book] {
        var result: [Book] = []
        var usedKeys = excludedKeys

        func insert(_ book: Book) -> Bool {
            let keys = identityKeys(of: book)
            guard usedKeys.isDisjoint(with: keys) else { return false }
            usedKeys.formUnion(keys)
            result.append(book)
            return true
        }

        for candidates in candidatesPerSource {
            guard result.count < count else { break }
            for candidate in candidates {
                if insert(candidate) { break }
            }
        }
        for book in fallback {
            guard result.count < count else { break }
            _ = insert(book)
        }
        return result
    }

    static func identityKeys(of book: Book) -> Set<String> {
        var keys: Set<String> = ["id:\(book.id)"]
        if let isbn = BookISBN.isbn13(from: book.isbn) { keys.insert("isbn:\(isbn)") }
        return keys
    }

    private static func hasISBN(_ book: Book) -> Bool {
        BookISBN.isbn13(from: book.isbn) != nil
    }
}
