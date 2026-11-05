import ComposableArchitecture
import Foundation
import Synchronization
import Testing
@testable import fingerprint_library

@MainActor
struct AnalyticsFeatureTests {
    @Test("캐시 검색도 시작·종료를 기록하되 원문은 보내지 않는다")
    func cachedSearchAndStaleReply() async {
        let events = Mutex<[AnalyticsEvent]>([])
        let requests = Mutex<[BookSearchRequest]>([])
        let store = TestStore(initialState: BookSearchFeature.State(query: "원문은 수집 금지", category: .journal)) {
            BookSearchFeature()
        } withDependencies: {
            $0.analyticsClient.record = { event in events.withLock { $0.append(event) } }
            $0.bookSearchClient.cached = { request in
                requests.withLock { $0.append(request) }
                return []
            }
            $0.searchHistoryClient.save = { _ in }
        }
        await store.send(.searchButtonTapped) {
            $0.searchGeneration = 1
            $0.hasSearched = true
            $0.recentQueries = ["원문은 수집 금지"]
        }
        let captured = events.withLock { $0 }
        #expect(captured.map(\.code) == [.searchSubmitted, .searchCompleted])
        #expect(captured[0].fields[.operationID] == captured[1].fields[.operationID])
        #expect(captured[1].fields[.cacheHit] == .flag(true))
        #expect(!String(describing: captured).contains("원문은 수집 금지"))
        #expect(requests.withLock { $0.map(\.category) } == [.all])
        await store.send(.categoryChanged(.monograph)) { $0.category = .monograph }
        // dev의 로컬 필터 전환은 새 검색·취소 이벤트를 만들지 않는다.
        #expect(events.withLock { $0.count } == 2)
        #expect(requests.withLock { $0.count } == 1)
        await store.send(.searchFailed(generation: 0, message: "원문 포함 오류"))
        #expect(events.withLock { $0.count } == 2)
    }

    @Test("장바구니 중복 담기는 성공으로 세지 않는다")
    func duplicateBasketAddition() async {
        let events = Mutex<[AnalyticsEvent]>([])
        let results = Mutex([BookBasketClient.AddResult.added, .alreadyAdded])
        let book = Book(id: "primo:alma123", isbn: nil, controlNumber: nil,
                        title: "책", author: "저자", publisher: nil, publicationYear: nil,
                        description: nil, imageURL: nil)
        let store = TestStore(initialState: BookDetailFeature.State(book: book)) {
            BookDetailFeature()
        } withDependencies: {
            $0.analyticsClient.record = { event in events.withLock { $0.append(event) } }
            $0.bookBasketClient.add = { _, _ in results.withLock { $0.removeFirst() } }
        }
        await store.send(.addToBasketButtonTapped) { $0.basketNotice = .added }
        await store.send(.addToBasketButtonTapped) { $0.basketNotice = .alreadyAdded }
        #expect(events.withLock { $0.map(\.code) } == [.basketBookAdded])
    }
}
