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
struct BookSearchFilteringTests {
    @Test("자료 유형 별칭을 구분하고 미제공·미지원 유형은 전체에만 표시한다", arguments: [
        ("book", BookSearchCategory.monograph), ("books", .monograph), ("printed_book", .monograph),
        (" BOOK ", .monograph), ("journal", .journal), ("journals", .journal),
        (nil, nil), ("", nil), ("article", nil)
    ] as [(String?, BookSearchCategory?)])
    func includesResourceType(sample: (String?, BookSearchCategory?)) {
        let book = categoryBook("result", type: sample.0)
        #expect(BookSearchCategory.all.includes(book))
        #expect(BookSearchCategory.monograph.includes(book) == (sample.1 == .monograph))
        #expect(BookSearchCategory.journal.includes(book) == (sample.1 == .journal))
    }
}

@MainActor
struct BookSearchCategoryTests {
    @Test("검색 전에 선택한 탭과 관계없이 전체를 한 번 검색하고 선택한 유형만 표시한다")
    func selectsBeforeSearching() async {
        let calls = Mutex<[BookSearchRequest]>([])
        let books = [categoryBook("book", type: "book"), categoryBook("journal", type: "journal")]
        let store = TestStore(initialState: BookSearchFeature.State(query: "Nature")) {
            BookSearchFeature()
        } withDependencies: {
            $0.searchHistoryClient.save = { _ in }
            $0.bookClient.search = { request in
                calls.withLock { $0.append(request) }
                return books
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
        await store.receive(\.searchSucceeded) {
            $0.isLoading = false
            $0.books = books
        }
        #expect(calls.withLock { $0 } == [.init(query: "Nature", category: .all)])
        #expect(store.state.visibleBooks == [books[1]])
    }

    @Test("검색 후 캐시가 만료돼도 탭 전환은 원본을 필터링하며 추가 조회·기록·로딩이 없다")
    func filtersWithoutSearchingAfterCacheExpires() async {
        let now = Mutex(Date(timeIntervalSince1970: 100))
        let calls = Mutex<[BookSearchCategory]>([])
        let cacheReads = Mutex(0)
        let historyWrites = Mutex(0)
        let cache = BookSearchResultCache(now: { now.withLock { $0 } })
        let books = [categoryBook("book", type: "printed_book"),
                     categoryBook("journal", type: "journals"), categoryBook("unknown")]
        let store = TestStore(initialState: BookSearchFeature.State(query: "Nature")) {
            BookSearchFeature()
        } withDependencies: {
            $0.searchHistoryClient.save = { _ in historyWrites.withLock { $0 += 1 } }
            $0.bookClient.search = { request in
                calls.withLock { $0.append(request.category) }
                return books
            }
            $0.bookSearchClient = .live(bookClient: $0.bookClient, cache: cache)
            $0.bookSearchClient.cached = { request in
                cacheReads.withLock { $0 += 1 }
                return cache.load(request)
            }
        }
        await store.send(.searchButtonTapped) {
            $0.searchGeneration = 1
            $0.hasSearched = true
            $0.isLoading = true
            $0.recentQueries = ["Nature"]
        }
        await store.receive(\.searchSucceeded) {
            $0.isLoading = false
            $0.books = books
        }
        now.withLock { $0 = $0.addingTimeInterval(60) }
        await store.send(.categoryChanged(.monograph)) { $0.category = .monograph }
        #expect(store.state.visibleBooks == [books[0]])
        await store.send(.categoryChanged(.journal)) { $0.category = .journal }
        #expect(store.state.visibleBooks == [books[1]])
        await store.send(.categoryChanged(.all)) { $0.category = .all }
        #expect(store.state.visibleBooks == books)
        await store.send(.categoryChanged(.all))
        #expect(calls.withLock { $0 } == [.all])
        #expect(cacheReads.withLock { $0 } == 1)
        #expect(historyWrites.withLock { $0 } == 1)
        await store.finish()
    }

    @Test("검색 중 탭을 바꿔도 기존 요청을 유지하고 완료 시 현재 탭으로 필터링한다")
    func filtersInFlightSearchWithoutReplacingIt() async {
        let gate = AsyncStream<Void>.makeStream()
        let calls = Mutex<[BookSearchCategory]>([])
        let cache = BookSearchResultCache()
        let books = [categoryBook("book", type: "book"), categoryBook("journal", type: "journal")]
        let store = TestStore(initialState: BookSearchFeature.State(query: "Nature")) {
            BookSearchFeature()
        } withDependencies: {
            $0.searchHistoryClient.save = { _ in }
            $0.bookClient.search = { request in
                calls.withLock { $0.append(request.category) }
                for await _ in gate.stream { break }
                return books
            }
            $0.bookSearchClient = .live(bookClient: $0.bookClient, cache: cache)
        }
        await store.send(.searchButtonTapped) {
            $0.searchGeneration = 1
            $0.hasSearched = true
            $0.isLoading = true
            $0.recentQueries = ["Nature"]
        }
        await store.send(.categoryChanged(.monograph)) { $0.category = .monograph }
        await store.send(.categoryChanged(.journal)) { $0.category = .journal }
        gate.continuation.yield()
        gate.continuation.finish()
        await store.receive(\.searchSucceeded) {
            $0.isLoading = false
            $0.books = books
        }
        #expect(store.state.visibleBooks == [books[1]])
        #expect(calls.withLock { $0 } == [.all])
        #expect(cache.load(.init(query: "Nature", category: .all)) == books)
        #expect(cache.load(.init(query: "Nature", category: .journal)) == nil)
        await store.finish()
    }

    @Test("선택된 탭에서도 전체 캐시를 즉시 재사용한다")
    func reusesAllCategoryCache() async {
        let cache = BookSearchResultCache()
        let books = [categoryBook("book", type: "book"), categoryBook("journal", type: "journal")]
        cache.save(books, for: .init(query: "Nature", category: .all))
        let store = TestStore(initialState: BookSearchFeature.State(query: "Nature", category: .journal)) {
            BookSearchFeature()
        } withDependencies: {
            $0.searchHistoryClient.save = { _ in }
            $0.bookSearchClient.cached = { cache.load($0) }
            $0.bookSearchClient.search = { _, _ in
                Issue.record("전체 캐시가 있으면 서버에 요청하지 않아야 한다")
                return []
            }
        }
        await store.send(.searchButtonTapped) {
            $0.searchGeneration = 1
            $0.hasSearched = true
            $0.recentQueries = ["Nature"]
            $0.books = books
        }
        #expect(store.state.visibleBooks == [books[1]])
        await store.finish()
    }

    @Test("선택한 유형의 결과가 없어도 원본은 보존하고 전체 탭으로 돌아올 수 있다")
    func preservesSourceWhenFilterIsEmpty() async {
        let books = [categoryBook("book", type: "book"), categoryBook("unknown")]
        let store = TestStore(initialState: BookSearchFeature.State(
            query: "Nature", books: books, hasSearched: true
        )) { BookSearchFeature() }
        await store.send(.categoryChanged(.journal)) { $0.category = .journal }
        #expect(store.state.visibleBooks.isEmpty)
        #expect(store.state.books == books)
        await store.send(.categoryChanged(.all)) { $0.category = .all }
        #expect(store.state.visibleBooks == books)
        await store.finish()
    }

    @Test("검색 실패 후 탭 전환은 오류를 유지하고 재요청하지 않는다")
    func preservesFailureUntilExplicitSearch() async {
        let store = TestStore(initialState: BookSearchFeature.State(
            query: "Nature", errorMessage: "네트워크 오류", hasSearched: true
        )) { BookSearchFeature() }
        await store.send(.categoryChanged(.journal)) { $0.category = .journal }
        #expect(store.state.errorMessage == "네트워크 오류")
        await store.finish()
    }

    @Test("필터 중 새로고침은 전체를 갱신하고 완료 시 최신 탭을 적용한다")
    func refreshesAllResultsWhileFiltering() async {
        let calls = Mutex<[BookSearchRequest]>([])
        let gate = AsyncStream<Void>.makeStream()
        let oldBooks = [categoryBook("old", type: "journal")]
        let books = [categoryBook("book", type: "book"), categoryBook("journal", type: "journal")]
        let cache = BookSearchResultCache()
        cache.save(oldBooks, for: .init(query: "Nature", category: .all))
        let store = TestStore(initialState: BookSearchFeature.State(
            query: "Nature", category: .journal, books: oldBooks, hasSearched: true
        )) { BookSearchFeature() } withDependencies: {
            $0.searchHistoryClient.save = { _ in }
            $0.bookClient.search = { request in
                calls.withLock { $0.append(request) }
                for await _ in gate.stream { break }
                return books
            }
            $0.bookSearchClient = .live(bookClient: $0.bookClient, cache: cache)
        }
        await store.send(.refreshButtonTapped) {
            $0.searchGeneration = 1
            $0.isLoading = true
            $0.recentQueries = ["Nature"]
        }
        await store.send(.categoryChanged(.monograph)) { $0.category = .monograph }
        gate.continuation.yield()
        gate.continuation.finish()
        await store.receive(\.searchSucceeded) {
            $0.isLoading = false
            $0.books = books
        }
        #expect(store.state.visibleBooks == [books[0]])
        #expect(calls.withLock { $0 } == [.init(query: "Nature", category: .all)])
        #expect(cache.load(.init(query: "Nature", category: .all)) == books)
        await store.finish()
    }
}

private nonisolated func categoryBook(_ id: String, type: String? = nil) -> Book {
    Book(id: id, isbn: nil, controlNumber: id, title: id, author: "저자",
         publisher: nil, publicationYear: nil, description: nil, imageURL: nil, resourceTypes: type.map { [$0] } ?? [])
}
