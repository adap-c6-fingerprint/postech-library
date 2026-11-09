//
//  DatasetRecommendation.swift
//  fingerprint-library
//
//  ✅ 이슈 #237: 하드데이터 기반 추천 규칙. 네트워크 없이 테스트할 수 있도록 순수 함수로 둔다.
//

import Foundation

nonisolated enum DatasetRecommendation {
    /// 개인별·학과별 추천 모두 한 번에 6권을 표시한다.
    static let displayCount = 6
    /// 개인별 추천에서 최근 조회 도서를 원본으로 쓰는 최대 권수.
    static let maxHistorySources = 3
    /// 소속이 없을 때(온보딩 건너뛰기) 하드데이터 전체에서 뽑는 학과별 추천 목록 권수. 소속 목록 한 개와 같은 20권이다.
    static let fallbackListCount = 20

    /// 최초 접속: 20권 중 랜덤 count권.
    static func randomPicks<G: RandomNumberGenerator>(
        from pool: [Book], count: Int = displayCount, using generator: inout G
    ) -> [Book] {
        Array(pool.shuffled(using: &generator).prefix(max(count, 0)))
    }

    /// 개인별 '이후 접속'의 원본 책. 최근 조회 n권(최대 3)과 하드데이터 랜덤 (count - n)권.
    /// ISBN이 없는 조회 도서는 연관도서를 찾을 수 없으므로 건너뛰고 다음 조회 도서를 쓴다.
    static func personalSources<G: RandomNumberGenerator>(
        recent: [Book], pool: [Book], count: Int = displayCount, using generator: inout G
    ) -> (history: [Book], pool: [Book]) {
        let history = Array(recent.filter(hasISBN).prefix(min(maxHistorySources, count)))
        let historyISBNs = Set(history.compactMap { BookISBN.isbn13(from: $0.isbn) })
        // 조회한 책이 하드데이터에도 있으면 같은 원본을 두 번 쓰지 않는다.
        let candidates = pool.filter { book in
            guard let isbn = BookISBN.isbn13(from: book.isbn) else { return false }
            return !historyISBNs.contains(isbn)
        }
        let fromPool = randomPicks(from: candidates, count: count - history.count, using: &generator)
        return (history, fromPool)
    }

    /// 원본 책마다 받은 '포스텍 소장 연관도서 후보'에서 1권씩 고른다.
    /// 앞 원본이 고른 책과 겹치면 같은 원본의 다음 후보로 넘어간다. (Q2)
    /// 채우지 못한 자리는 fallback(하드데이터에서 아직 안 쓴 책)으로 채워 count권을 맞춘다. (Q6)
    static func assemble(
        candidatesPerSource: [[Book]], fallback: [Book], count: Int = displayCount
    ) -> [Book] {
        var result: [Book] = []
        var usedKeys = Set<String>()

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

    /// id와 ISBN 중 하나라도 같으면 같은 책으로 본다.
    static func identityKeys(of book: Book) -> Set<String> {
        var keys: Set<String> = ["id:\(book.id)"]
        if let isbn = BookISBN.isbn13(from: book.isbn) { keys.insert("isbn:\(isbn)") }
        return keys
    }

    private static func hasISBN(_ book: Book) -> Bool {
        BookISBN.isbn13(from: book.isbn) != nil
    }
}
