import Foundation
import Synchronization
import Testing
@testable import fingerprint_library

struct BookSearchResultCacheTests {
    @Test("공백을 정리한 같은 검색어를 재사용하고 다른 검색어는 구분한다")
    func normalizesWhitespace() {
        let cache = BookSearchResultCache()
        cache.save([], for: .init(query: " 스위프트\n", category: .all))
        #expect(cache.load(.init(query: "스위프트", category: .all)) == [])
        #expect(cache.load(.init(query: "과학", category: .all)) == nil)
    }

    @Test("성공 시각으로부터 60초가 지나면 다시 조회해야 한다")
    func expiresFromSaveTime() {
        let date = Mutex(Date(timeIntervalSince1970: 100))
        let cache = BookSearchResultCache(now: { date.withLock { $0 } })
        cache.save([], for: .init(query: "스위프트", category: .all))
        date.withLock { $0 = $0.addingTimeInterval(59) }
        #expect(cache.load(.init(query: "스위프트", category: .all)) == [])
        date.withLock { $0 = $0.addingTimeInterval(1) }
        #expect(cache.load(.init(query: "스위프트", category: .all)) == nil)
    }

    @Test("용량이 차면 가장 오래 사용하지 않은 결과를 제거한다")
    func evictsLeastRecentlyUsed() {
        let cache = BookSearchResultCache(capacity: 2)
        cache.save([], for: .init(query: "A", category: .all))
        cache.save([], for: .init(query: "B", category: .all))
        #expect(cache.load(.init(query: "A", category: .all)) == [])
        cache.save([], for: .init(query: "C", category: .all))
        #expect(cache.load(.init(query: "A", category: .all)) == [])
        #expect(cache.load(.init(query: "B", category: .all)) == nil)
        #expect(cache.load(.init(query: "C", category: .all)) == [])
    }

    @Test("명시적 새로고침은 해당 검색어만 무효화한다")
    func removesOnlyRequestedQuery() {
        let cache = BookSearchResultCache()
        cache.save([], for: .init(query: "스위프트", category: .all))
        cache.save([], for: .init(query: "과학", category: .all))
        cache.remove(.init(query: " 스위프트 ", category: .all))
        #expect(cache.load(.init(query: "스위프트", category: .all)) == nil)
        #expect(cache.load(.init(query: "과학", category: .all)) == [])
    }
}
