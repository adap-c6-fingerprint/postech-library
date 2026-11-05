import ComposableArchitecture
import Foundation
import Synchronization
import Testing
@testable import fingerprint_library

@MainActor
struct BookSearchCacheFeatureTests {
    private let swift = Book(
        id: "swift", isbn: nil, controlNumber: "swift", title: "스위프트",
        author: "저자", publisher: nil, publicationYear: nil,
        description: nil, imageURL: nil
    )
    private let science = Book(
        id: "science", isbn: nil, controlNumber: "science", title: "과학",
        author: "저자", publisher: nil, publicationYear: nil,
        description: nil, imageURL: nil
    )

    @Test("같은 검색어와 다른 검색어를 거친 재검색은 결과를 즉시 재사용한다")
    func reusesResultsAcrossQueries() async {
        let cache = BookSearchResultCache()
        let calls = Mutex(0)
        let swift = swift, science = science
        let store = TestStore(initialState: BookSearchFeature.State(query: "스위프트")) {
            BookSearchFeature()
        } withDependencies: {
            $0.searchHistoryClient.save = { _ in }
            $0.bookClient.search = { request in
                let query = request.query
                calls.withLock { $0 += 1 }
                return query == "스위프트" ? [swift] : [science]
            }
            $0.bookSearchClient = .live(bookClient: $0.bookClient, cache: cache)
        }
        await store.send(.searchButtonTapped) {
            $0.searchGeneration += 1
            $0.isLoading = true
            $0.hasSearched = true
            $0.recentQueries = ["스위프트"]
        }
        await store.receive(\.searchSucceeded) {
            $0.isLoading = false
            $0.books = [swift]
        }
        await store.send(.queryChanged(" 스위프트\n")) { $0.query = " 스위프트\n" }
        await store.send(.searchButtonTapped) {
            $0.searchGeneration += 1
        }
        #expect(calls.withLock { $0 } == 1)

        await store.send(.queryChanged("과학")) {
            $0.query = "과학"
            $0.searchGeneration += 1
            $0.books = []
            $0.hasSearched = false
        }
        await store.send(.searchButtonTapped) {
            $0.searchGeneration += 1
            $0.isLoading = true
            $0.hasSearched = true
            $0.recentQueries = ["과학", "스위프트"]
        }
        await store.receive(\.searchSucceeded) {
            $0.isLoading = false
            $0.books = [science]
        }
        await store.send(.queryChanged("스위프트")) {
            $0.query = "스위프트"
            $0.searchGeneration += 1
            $0.books = []
            $0.hasSearched = false
        }
        await store.send(.searchButtonTapped) {
            $0.searchGeneration += 1
            $0.books = [swift]
            $0.hasSearched = true
            $0.recentQueries = ["스위프트", "과학"]
        }
        #expect(calls.withLock { $0 } == 2)
    }

    @Test("새 검색어를 입력하는 동안 이전 결과를 숨기고 제출할 때만 전체를 조회한다")
    func hidesPreviousResultsUntilSubmission() async {
        let calls = Mutex<[BookSearchRequest]>([])
        let swift = swift, science = science
        let store = TestStore(initialState: BookSearchFeature.State(
            query: "스위프트", recentBooks: [swift], books: [swift], hasSearched: true
        )) {
            BookSearchFeature()
        } withDependencies: {
            $0.bookSearchClient.cached = { request in
                calls.withLock { $0.append(request) }
                return [science]
            }
        }
        await store.send(.queryChanged("과")) {
            $0.query = "과"
            $0.searchGeneration = 1
            $0.books = []
            $0.hasSearched = false
        }
        await store.send(.queryChanged("과학")) { $0.query = "과학" }
        await store.send(.categoryChanged(.journal)) { $0.category = .journal }
        #expect(calls.withLock { $0.isEmpty })
        #expect(store.state.recentBooks == [swift])
        #expect(store.state.recentQueries.isEmpty)
        await store.send(.searchButtonTapped) {
            $0.searchGeneration = 2
            $0.hasSearched = true
            $0.books = [science]
            $0.recentQueries = ["과학"]
        }
        #expect(calls.withLock { $0 } == [.init(query: "과학", category: .all)])
        #expect(store.state.visibleBooks.isEmpty)
        #expect(store.state.recentBooks == [swift])
        await store.finish()
    }

    @Test("만료된 검색 결과는 API를 다시 호출한다")
    func reloadsExpiredResult() async {
        let now = Mutex(Date(timeIntervalSince1970: 100))
        let cache = BookSearchResultCache(now: { now.withLock { $0 } })
        cache.save([], for: .init(query: "스위프트", category: .all))
        now.withLock { $0 = $0.addingTimeInterval(60) }
        let calls = Mutex(0)
        let store = TestStore(initialState: BookSearchFeature.State(query: "스위프트")) {
            BookSearchFeature()
        } withDependencies: {
            $0.searchHistoryClient.save = { _ in }
            $0.bookClient.search = { _ in
                calls.withLock { $0 += 1 }
                return []
            }
            $0.bookSearchClient = .live(bookClient: $0.bookClient, cache: cache)
        }
        await store.send(.searchButtonTapped) {
            $0.searchGeneration += 1
            $0.isLoading = true
            $0.hasSearched = true
            $0.recentQueries = ["스위프트"]
        }
        await store.receive(\.searchSucceeded) { $0.isLoading = false }
        #expect(calls.withLock { $0 } == 1)
    }

    @Test("실패한 새로고침의 이전 캐시를 재사용하지 않고 다음 제출에서 재시도한다")
    func refreshInvalidatesAndFailureIsNotCached() async {
        let cache = BookSearchResultCache()
        cache.save([swift], for: .init(query: "스위프트", category: .all))
        let calls = Mutex(0)
        let error = URLError(.notConnectedToInternet)
        let message = error.localizedDescription
        let store = TestStore(initialState: BookSearchFeature.State(
            query: "스위프트", books: [swift], hasSearched: true
        )) {
            BookSearchFeature()
        } withDependencies: {
            $0.searchHistoryClient.save = { _ in }
            $0.bookClient.search = { _ in
                let count = calls.withLock { $0 += 1; return $0 }
                if count == 1 { throw error }
                return []
            }
            $0.bookSearchClient = .live(bookClient: $0.bookClient, cache: cache)
        }
        await store.send(.refreshButtonTapped) {
            $0.searchGeneration += 1
            $0.isLoading = true
            $0.recentQueries = ["스위프트"]
        }
        await store.receive(\.searchFailed) {
            $0.isLoading = false
            $0.errorMessage = message
        }
        #expect(cache.load(.init(query: "스위프트", category: .all)) == nil)
        await store.send(.searchButtonTapped) {
            $0.searchGeneration += 1
            $0.isLoading = true
            $0.errorMessage = nil
            $0.books = []
        }
        await store.receive(\.searchSucceeded) { $0.isLoading = false }
        #expect(calls.withLock { $0 } == 2)
        #expect(cache.load(.init(query: "스위프트", category: .all)) == [])
    }

    @Test("검색 중 새 입력을 시작하면 이전 요청을 취소하고 늦은 결과를 표시·저장하지 않는다")
    func cancelsSubmittedQueryWhenEditingStarts() async {
        let cache = BookSearchResultCache()
        let gate = AsyncStream<Void>.makeStream()
        let swift = swift
        let store = TestStore(initialState: BookSearchFeature.State(query: "스위프트")) {
            BookSearchFeature()
        } withDependencies: {
            $0.searchHistoryClient.save = { _ in }
            $0.bookClient.search = { _ in
                for await _ in gate.stream { break }
                return [swift]
            }
            $0.bookSearchClient = .live(bookClient: $0.bookClient, cache: cache)
        }
        await store.send(.searchButtonTapped) {
            $0.searchGeneration += 1
            $0.isLoading = true
            $0.hasSearched = true
            $0.recentQueries = ["스위프트"]
        }
        await store.send(.queryChanged("과학")) {
            $0.query = "과학"
            $0.searchGeneration += 1
            $0.isLoading = false
            $0.hasSearched = false
        }
        gate.continuation.yield()
        gate.continuation.finish()
        await store.finish()
        // 취소 전에 이미 전송된 응답도 새 입력의 결과로 표시하지 않는다.
        await store.send(.searchSucceeded(generation: 1, books: [swift]))
        await store.send(.searchFailed(generation: 1, message: "이전 오류"))
        #expect(store.state.books.isEmpty)
        #expect(!store.state.hasSearched)
        #expect(store.state.recentQueries == ["스위프트"])
        #expect(cache.load(.init(query: "스위프트", category: .all)) == nil)
        #expect(cache.load(.init(query: "과학", category: .all)) == nil)
    }

    @Test("취소한 검색의 늦은 성공 결과는 캐시하지 않는다")
    func doesNotCacheCancelledSearch() async {
        let cache = BookSearchResultCache()
        let gate = AsyncStream<Void>.makeStream()
        let swift = swift
        let store = TestStore(initialState: BookSearchFeature.State(query: "스위프트")) {
            BookSearchFeature()
        } withDependencies: {
            $0.searchHistoryClient.save = { _ in }
            $0.bookClient.search = { _ in
                for await _ in gate.stream { break }
                return [swift]
            }
            $0.bookSearchClient = .live(bookClient: $0.bookClient, cache: cache)
        }
        await store.send(.searchButtonTapped) {
            $0.searchGeneration += 1
            $0.isLoading = true
            $0.hasSearched = true
            $0.recentQueries = ["스위프트"]
        }
        await store.send(.searchCancelled) {
            $0.searchGeneration += 1
            $0.query = ""
            $0.isLoading = false
            $0.hasSearched = false
        }
        await store.finish()
        gate.continuation.finish()
        #expect(cache.load(.init(query: "스위프트", category: .all)) == nil)
    }
}
