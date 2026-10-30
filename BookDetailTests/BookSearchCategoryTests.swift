import ComposableArchitecture
import Foundation
import Synchronization
import Testing
@testable import fingerprint_library

@MainActor
struct BookSearchRequestTests {
    @Test("자료 유형에 맞는 Primo 필터를 보내고 검색어를 URL 인코딩한다", arguments: [
        (BookSearchCategory.all, ["books", "printed_book", "journals"]),
        (.monograph, ["books", "printed_book"]),
        (.journal, ["journals"])
    ])
    func filtersServerRequest(sample: (BookSearchCategory, [String])) throws {
        let request = BookSearchRequest(query: " 과학 & Nature\n", category: sample.0)
        let url = try BookClient.searchURL(for: request)
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let items = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value) })
        #expect(items["q"] == "any,contains,과학 & Nature")
        let facets = try #require(items["multiFacets"] ?? nil)
        #expect(Set(facets.components(separatedBy: "|,|")) == Set(sample.1.map { "facet_rtype,include,\($0)" }))
        #expect(items["scope"] == "MyInstitution")
        #expect(items["tab"] == "LibraryCatalog")
        #expect(items["apikey"] == nil)
    }

    @Test("같은 검색어의 전체·단행본·학술지 캐시와 무효화를 구분한다")
    func cacheSeparatesCategories() {
        let cache = BookSearchResultCache()
        let all = BookSearchRequest(query: " Nature ", category: .all)
        let monograph = BookSearchRequest(query: "Nature", category: .monograph)
        let journal = BookSearchRequest(query: "Nature", category: .journal)
        cache.save([categoryBook("all")], for: all)
        cache.save([categoryBook("book")], for: monograph)
        cache.save([categoryBook("journal")], for: journal)
        #expect(cache.load(.init(query: "Nature\n", category: .all))?.first?.id == "all")
        #expect(cache.load(monograph)?.first?.id == "book")
        #expect(cache.load(journal)?.first?.id == "journal")
        cache.remove(journal)
        #expect(cache.load(journal) == nil)
        #expect(cache.load(all)?.first?.id == "all")
        #expect(cache.load(monograph)?.first?.id == "book")
    }
}

@MainActor
struct BookSearchCategoryTests {
    @Test("검색 전에는 분류만 선택하고 제출할 때 선택한 유형으로 검색한다")
    func selectsBeforeSearching() async {
        let calls = Mutex<[BookSearchRequest]>([])
        let store = TestStore(initialState: BookSearchFeature.State(query: "Nature")) {
            BookSearchFeature()
        } withDependencies: {
            $0.searchHistoryClient.save = { _ in }
            $0.bookClient.search = { request in
                calls.withLock { $0.append(request) }
                return []
            }
            $0.bookSearchClient = .live(bookClient: $0.bookClient, cache: BookSearchResultCache())
        }
        await store.send(.categoryChanged(.journal)) { $0.category = .journal }
        #expect(calls.withLock { $0.isEmpty })
        await store.send(.searchButtonTapped) {
            $0.searchGeneration = 1
            $0.hasSearched = true
            $0.isLoading = true
            $0.recentQueries = ["Nature"]
        }
        await store.receive(\.searchSucceeded) { $0.isLoading = false }
        #expect(calls.withLock { $0 } == [.init(query: "Nature", category: .journal)])
    }

    @Test("검색 후 분류를 바꾸면 재검색하고 돌아온 분류의 캐시를 재사용한다")
    func searchesAndReusesCategoryCache() async {
        let calls = Mutex<[BookSearchCategory]>([])
        let historyWrites = Mutex(0)
        let cache = BookSearchResultCache()
        let allBook = categoryBook("all"), journalBook = categoryBook("journal")
        let store = TestStore(initialState: BookSearchFeature.State(query: "Nature")) {
            BookSearchFeature()
        } withDependencies: {
            $0.searchHistoryClient.save = { _ in historyWrites.withLock { $0 += 1 } }
            $0.bookClient.search = { request in
                calls.withLock { $0.append(request.category) }
                return request.category == .all ? [allBook] : [journalBook]
            }
            $0.bookSearchClient = .live(bookClient: $0.bookClient, cache: cache)
        }
        await store.send(.searchButtonTapped) {
            $0.searchGeneration = 1
            $0.hasSearched = true
            $0.isLoading = true
            $0.recentQueries = ["Nature"]
        }
        await store.receive(\.searchSucceeded) {
            $0.isLoading = false
            $0.books = [allBook]
        }
        await store.send(.categoryChanged(.journal)) {
            $0.category = .journal
            $0.searchGeneration = 2
            $0.isLoading = true
            $0.books = []
        }
        await store.receive(\.searchSucceeded) {
            $0.isLoading = false
            $0.books = [journalBook]
        }
        await store.send(.categoryChanged(.all)) {
            $0.category = .all
            $0.searchGeneration = 3
            $0.books = [allBook]
        }
        await store.send(.categoryChanged(.all))
        #expect(calls.withLock { $0 } == [.all, .journal])
        #expect(historyWrites.withLock { $0 } == 1)
        await store.finish()
    }

    @Test("검색 중 분류 변경은 이전 요청을 취소하고 새 분류 결과만 표시·저장한다")
    func replacesInFlightSearch() async {
        let gate = AsyncStream<Void>.makeStream()
        let cache = BookSearchResultCache()
        let oldBook = categoryBook("old"), journalBook = categoryBook("journal")
        let store = TestStore(initialState: BookSearchFeature.State(query: "Nature")) {
            BookSearchFeature()
        } withDependencies: {
            $0.searchHistoryClient.save = { _ in }
            $0.bookClient.search = { request in
                if request.category == .all {
                    for await _ in gate.stream { break }
                    return [oldBook]
                }
                return [journalBook]
            }
            $0.bookSearchClient = .live(bookClient: $0.bookClient, cache: cache)
        }
        await store.send(.searchButtonTapped) {
            $0.searchGeneration = 1
            $0.hasSearched = true
            $0.isLoading = true
            $0.recentQueries = ["Nature"]
        }
        await store.send(.categoryChanged(.journal)) {
            $0.category = .journal
            $0.searchGeneration = 2
        }
        await store.receive(\.searchSucceeded) {
            $0.isLoading = false
            $0.books = [journalBook]
        }
        gate.continuation.finish()
        await store.finish()
        #expect(cache.load(.init(query: "Nature", category: .all)) == nil)
        #expect(cache.load(.init(query: "Nature", category: .journal)) == [journalBook])
        // 취소 직전 이미 큐에 들어간 성공·실패도 최신 결과를 덮지 않는다.
        await store.send(.searchSucceeded(generation: 1, books: [oldBook]))
        await store.send(.searchFailed(generation: 1, message: "이전 오류"))
    }

    @Test("조회 중 캐시가 있는 분류로 바꾸면 즉시 표시하고 이전 요청을 취소한다")
    func switchesToCachedCategoryDuringSearch() async {
        let cache = BookSearchResultCache()
        let journalBook = categoryBook("journal")
        cache.save([journalBook], for: .init(query: "Nature", category: .journal))
        let store = TestStore(initialState: BookSearchFeature.State(query: "Nature")) {
            BookSearchFeature()
        } withDependencies: {
            $0.searchHistoryClient.save = { _ in }
            $0.bookClient.search = { _ in
                try await Task.sleep(for: .seconds(60))
                return []
            }
            $0.bookSearchClient = .live(bookClient: $0.bookClient, cache: cache)
        }
        await store.send(.searchButtonTapped) {
            $0.searchGeneration = 1
            $0.hasSearched = true
            $0.isLoading = true
            $0.recentQueries = ["Nature"]
        }
        await store.send(.categoryChanged(.journal)) {
            $0.category = .journal
            $0.searchGeneration = 2
            $0.isLoading = false
            $0.books = [journalBook]
        }
        await store.finish()
    }

    @Test("같은 분류로 돌아와도 이전 세대의 성공·실패 응답은 무시한다")
    func rejectsOlderGenerationForSameCategory() async {
        let store = TestStore(initialState: BookSearchFeature.State(
            query: "Nature", category: .all, searchGeneration: 3,
            isLoading: true, hasSearched: true
        )) { BookSearchFeature() }
        await store.send(.searchSucceeded(generation: 1, books: [categoryBook("old")]))
        await store.send(.searchFailed(generation: 1, message: "이전 오류"))
        await store.send(.searchSucceeded(generation: 3, books: [])) {
            $0.isLoading = false
        }
    }

    @Test("검색어를 지운 뒤 분류를 바꾸면 통신 없이 검색 상태를 정리한다")
    func emptyQueryDoesNotSearch() async {
        let store = TestStore(initialState: BookSearchFeature.State(
            query: " \n", books: [categoryBook("old")], errorMessage: "이전 오류",
            hasSearched: true
        )) { BookSearchFeature() }
        await store.send(.categoryChanged(.journal)) {
            $0.category = .journal
            $0.searchGeneration = 1
            $0.books = []
            $0.errorMessage = nil
            $0.hasSearched = false
        }
        await store.finish()
    }
}

private nonisolated func categoryBook(_ id: String) -> Book {
    Book(id: id, isbn: nil, controlNumber: id, title: id, author: "저자",
         publisher: nil, publicationYear: nil, description: nil, imageURL: nil)
}
