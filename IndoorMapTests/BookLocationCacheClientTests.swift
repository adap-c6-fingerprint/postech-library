import ComposableArchitecture
import Foundation
import Testing
@testable import fingerprint_library

@MainActor
struct BookLocationCacheClientTests {
    @Test("번들의 실제 추천 도서는 외부 조회 없이 소장과 서가를 찾으며 최신 로컬 사본을 우선한다")
    func usesBundledHoldingsOffline() async throws {
        let suite = "location-cache-\(UUID())"
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let cache = BookLocationCacheClient.userDefaults(suiteName: suite)
        await cache.prepare()
        let key: [String?] = ["control", "primo:alma991000416829703286"]
        let holdings = try #require(cache.load([key])[key])
        #expect(holdings.first?.callNumber == "TA357.5.D37 .김82 1998")
        let map = try await BundledIndoorMapLoader().loadLibrary()
        let labels = try await BundledShelfLabelLoader().loadLibrary(on: map)
        #expect(!HomeMapMarkerBuilder.favorites(holdings: [key: holdings], on: map, labels: labels).isEmpty)
        let dataset = try await RecommendationDatasetLoader().load()
        let book = try #require(dataset.book(recordID: "alma991000416829703286"))
        cache.record(book, [])
        let reopened = BookLocationCacheClient.userDefaults(suiteName: suite)
        await reopened.prepare()
        #expect(reopened.load([key])[key] == [])
    }

    @Test("일반 조회에서 받은 소장 정보를 로컬에 저장하고 다시 실행해도 복원한다")
    func persistsLocationsLocally() {
        let suite = "location-cache-\(UUID())"
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let book = BookHoldingTestData.book()
        let holdings = [BookHoldingTestData.holding()]
        let first = BookLocationCacheClient.userDefaults(suiteName: suite)
        first.record(book, holdings)
        let reopened = BookLocationCacheClient.userDefaults(suiteName: suite)
        #expect(reopened.load([book.recordKey])[book.recordKey] == holdings)
        let unprefixed: [String?] = ["control", "alma991000958759703280"]
        #expect(reopened.load([unprefixed])[unprefixed] == holdings)
    }

    @Test("위치를 모르는 찜은 빈 결과이며 기존 찜 저장 목록은 바꾸지 않는다")
    func keepsFavoritesSeparate() {
        let suite = "location-cache-\(UUID())"
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let favorites = BookFavoritesClient.userDefaults(suiteName: suite)
        let cache = BookLocationCacheClient.userDefaults(suiteName: suite)
        let book = BookHoldingTestData.book()
        favorites.save([book.recordKey])
        #expect(cache.load([book.recordKey]).isEmpty)
        cache.record(book, [BookHoldingTestData.holding()])
        #expect(favorites.load() == [book.recordKey])
        favorites.save([])
        #expect(!cache.load([book.recordKey]).isEmpty)
    }

    @Test("ISBN은 이미 로컬에 있는 같은 판본만 연결하고 빈 최신 응답은 과거 위치를 되살리지 않는다")
    func matchesLocalISBNAndClearsOldLocation() {
        let suite = "location-cache-\(UUID())"
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let cache = BookLocationCacheClient.userDefaults(suiteName: suite)
        let book = Book(id: "primo:alma991000000001", isbn: "9780131103627", controlNumber: "primo:alma991000000001",
                        title: "책", author: "저자", publisher: nil, publicationYear: nil, description: nil, imageURL: nil)
        let key: [String?] = ["metadata", "0-13-110362-8", "책"]
        cache.record(book, [BookHoldingTestData.holding()])
        #expect(cache.load([key])[key]?.count == 1)
        #expect(cache.load([["metadata", "9780201616224", "책"]]).isEmpty)
        cache.record(book, [])
        #expect(cache.load([key])[key] == [])
        #expect(cache.load([book.recordKey])[book.recordKey] == [])
    }

    @Test("기존 검색 응답에 포함된 소장만 저장하고 책마다 별도 API를 호출하지 않는다")
    func capturesExistingSearchResponse() throws {
        let suite = "location-cache-\(UUID())"
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let data = Data(#"{"docs":[{"pnx":{"control":{"recordid":["alma991000000001"]},"display":{"title":["이미 검색한 책"]}},"delivery":{"holding":[{"organization":"82POSTECH_INST","libraryCode":"MAIN","subLocationCode":"c3b","callNumber":"RC263 .R632 1990"}]}},{"pnx":{"control":{"recordid":["alma991000000002"]},"display":{"title":["소장이 없는 책"]}},"delivery":{"holding":[],"bestlocation":{"callNumber":"되살리면 안 되는 위치"}}}] }"#.utf8)
        let books = try BookClient.books(from: data)
        let cache = BookLocationCacheClient.userDefaults(suiteName: suite)
        cache.record(books[1], [BookHoldingTestData.holding()])
        cache.recordSearchResponse(data, books: books)
        let restored = BookLocationCacheClient.userDefaults(suiteName: suite)
        #expect(restored.load([books[0].recordKey])[books[0].recordKey]?.first?.callNumber == "RC263 .R632 1990")
        #expect(restored.load([books[1].recordKey])[books[1].recordKey] == [])
        #expect(try PrimoHoldingsMapper.decode(data, recordID: "alma991000000001").count == 1)
        #expect(try PrimoHoldingsMapper.decode(data, recordID: "alma999999999999").isEmpty)
    }

    @Test("소장 필드가 누락되거나 빈 객체인 검색 응답은 저장된 위치를 지우지 않는다", arguments: [
        #"{"pnx":{"control":{"recordid":["alma991000000001"]},"display":{"title":["검색 결과"]}}}"#,
        #"{"pnx":{"control":{"recordid":["alma991000000001"]},"display":{"title":["검색 결과"]}},"delivery":{}}"#,
        #"{"pnx":{"control":{"recordid":["alma991000000001"]},"display":{"title":["검색 결과"]},"delivery":{}}}"#,
        #"{"pnx":{"control":{"recordid":["alma991000000001"]},"display":{"title":["검색 결과"],"availlibrary":null}}}"#
    ])
    func preservesLocationWhenSearchOmitsHoldings(document: String) throws {
        let suite = "location-cache-\(UUID())"
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let data = Data("{\"docs\":[\(document)]}".utf8)
        let books = try BookClient.books(from: data)
        let book = try #require(books.first)
        let previous = [BookHoldingTestData.holding()]
        let cache = BookLocationCacheClient.userDefaults(suiteName: suite)
        cache.record(book, previous)
        cache.recordSearchResponse(data, books: books)
        #expect(try PrimoHoldingsMapper.decodeAll(data)["alma991000000001"] == nil)
        #expect(try PrimoHoldingsMapper.decode(data, recordID: "alma991000000001").isEmpty)
        #expect(cache.load([book.recordKey])[book.recordKey] == previous)
        #expect(BookLocationCacheClient.userDefaults(suiteName: suite).load([book.recordKey])[book.recordKey] == previous)
    }

    @Test("PNX에 빈 소장 목록이 명시되면 기존 위치를 제거하고 빈 결과를 복원한다")
    func clearsLocationForExplicitEmptyAvailability() throws {
        let suite = "location-cache-\(UUID())"
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let data = Data(#"{"docs":[{"pnx":{"control":{"recordid":["alma991000000001"]},"display":{"title":["검색 결과"],"availlibrary":[]}}}]}"#.utf8)
        let books = try BookClient.books(from: data)
        let book = try #require(books.first)
        let cache = BookLocationCacheClient.userDefaults(suiteName: suite)
        cache.record(book, [BookHoldingTestData.holding()])
        cache.recordSearchResponse(data, books: books)
        #expect(cache.load([book.recordKey])[book.recordKey] == [])
        #expect(BookLocationCacheClient.userDefaults(suiteName: suite).load([book.recordKey])[book.recordKey] == [])
    }

    @Test("검색 결과의 추가·변경·명시적 빈 소장을 한 배치로 저장하고 모두 복원한다")
    func recordsSearchResultsInOneBatch() throws {
        let suite = "location-cache-\(UUID())"
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let documents: [[String: Any]] = (1...3).map { index in
            ["pnx": ["control": ["recordid": ["alma99100000000\(index)"]],
                     "display": ["title": ["검색 결과 \(index)"]]],
             "delivery": ["holding": index == 3 ? [] : [["callNumber": "RC\(index)"]]]]
        }
        let data = try JSONSerialization.data(withJSONObject: ["docs": documents])
        let books = try BookClient.books(from: data)
        try #require(books.count == 3)
        var cache = BookLocationCacheClient.userDefaults(suiteName: suite)
        cache.record(books[0], [BookHoldingTestData.holding()])
        cache.record(books[2], [BookHoldingTestData.holding()])
        let batch = try #require(cache.recordBatch)
        let batchCalls = LockIsolated(0)
        cache.recordBatch = { entries in
            batchCalls.withValue { $0 += 1 }
            batch(entries)
        }
        cache.record = { _, _ in Issue.record("검색 결과를 책마다 따로 기록하면 안 된다") }
        cache.recordSearchResponse(data, books: books)
        #expect(batchCalls.value == 1)
        let keys = Set(books.map(\.recordKey))
        let saved = cache.load(keys)
        #expect(saved[books[0].recordKey]?.first?.callNumber == "RC1")
        #expect(saved[books[1].recordKey]?.first?.callNumber == "RC2")
        #expect(saved[books[2].recordKey] == [])
        #expect(BookLocationCacheClient.userDefaults(suiteName: suite).load(keys) == saved)
    }
}
