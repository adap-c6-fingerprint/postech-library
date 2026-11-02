import ComposableArchitecture
import Foundation
import Testing
@testable import fingerprint_library

@MainActor
struct RecentSearchBooksTests {
    @Test("선택한 도서를 재실행 후에도 복원하고 중복 없이 최근 5권을 유지한다")
    func persistsSelectionsAndMovesDuplicates() {
        let suite = "RecentSearchBooksTests.\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let client = RecentSearchBooksClient.userDefaults(suiteName: suite)
        for index in 0..<7 { client.record(book(index)) }
        let restored = RecentSearchBooksClient.userDefaults(suiteName: suite)
        #expect(restored.load() == (2..<7).reversed().map { book($0) })

        let selected = book(4, id: "new-display-id")
        restored.record(selected)
        #expect(restored.load().count == 5)
        #expect(restored.load().first == selected)
        #expect(restored.load().filter { $0.recordKey == selected.recordKey }.count == 1)
        #expect(restored.load().last == book(2))
    }

    @Test("기존 20권 기록도 최근 5권만 복원하고 새 선택 시 5권으로 저장한다")
    func limitsLegacyHistoryToFive() throws {
        let suite = "RecentSearchBooksTests.\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let defaults = try #require(UserDefaults(suiteName: suite))
        let legacy = (0..<20).map { index in
            ["id": "legacy-\(index)", "title": "도서 \(index)", "author": "저자"]
        }
        defaults.set(try JSONSerialization.data(withJSONObject: legacy), forKey: "recentSearchBooks")
        let client = RecentSearchBooksClient.userDefaults(suiteName: suite)
        #expect(client.load().map(\.id) == (0..<5).map { "legacy-\($0)" })

        let selected = book(7)
        client.record(selected)
        #expect(client.load().map(\.id) == [selected.id] + (0..<4).map { "legacy-\($0)" })
        let saved = try #require(defaults.data(forKey: "recentSearchBooks"))
        let records = try #require(JSONSerialization.jsonObject(with: saved) as? [[String: Any]])
        #expect(records.count == 5)
    }

    @Test("검색만으로는 최근 도서가 추가되지 않고 결과 선택 시 저장·상세 이동한다")
    func recordsOnlySelectedResults() async {
        let suite = "RecentSearchBooksTests.\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let client = RecentSearchBooksClient.userDefaults(suiteName: suite)
        let previous = book(0), selected = book(1)
        client.record(previous)
        let store = TestStore(initialState: BookSearchFeature.State(query: "블렌더")) {
            BookSearchFeature()
        } withDependencies: {
            $0.recentSearchBooksClient = client
            $0.bookSearchClient.cached = { _ in [selected] }
        }
        await store.send(.task) { $0.recentBooks = [previous] }
        await store.send(.searchButtonTapped) {
            $0.searchGeneration = 1
            $0.hasSearched = true
            $0.recentQueries = ["블렌더"]
            $0.books = [selected]
        }
        #expect(client.load() == [previous])
        await store.send(.bookSelected(selected)) {
            $0.recentBooks = [selected, previous]
            $0.detail = BookDetailFeature.State(book: selected, isFavorite: false)
        }
        await store.send(.detail(.dismiss)) { $0.detail = nil }
        await store.send(.searchCancelled) {
            $0.searchGeneration = 2
            $0.query = ""
            $0.books = []
            $0.hasSearched = false
        }
        #expect(client.load() == [selected, previous])
        #expect(store.state.recentBooks == [selected, previous])
        await store.finish()
    }

    @Test("소장 조회 실패·번호 누락을 구분하고 이전 화면의 응답은 반영하지 않는다")
    func handlesLibraryInfoAndStaleResponses() async {
        let selected = book(1)
        let missing = Book(id: "missing", isbn: nil, controlNumber: nil, title: "자료", author: "저자",
                           publisher: nil, publicationYear: nil, description: nil, imageURL: nil)
        let holding = BookHolding(holdingID: "h1", institutionCode: "82POSTECH_INST", libraryCode: "MAIN",
                                  locationCode: "c3b", locationName: "단행본3층", callNumber: "TR897.7", availability: "available")
        let store = TestStore(initialState: BookSearchFeature.State(recentBooks: [selected, missing])) {
            BookSearchFeature()
        } withDependencies: {
            $0.bookHoldingsClient.fetch = { recordID in
                #expect(recordID == "alma991000958759703281")
                throw URLError(.notConnectedToInternet)
            }
        }
        await store.send(.loadRecentBookInfo) {
            $0.recentBookInfoGeneration = 1
            $0.recentBookInfo = [selected.id: .loading, missing.id: .unavailable]
        }
        await store.receive(\.recentBookInfoFailed) { $0.recentBookInfo[selected.id] = .failed }
        store.dependencies.bookHoldingsClient.fetch = { _ in [holding] }
        await store.send(.loadRecentBookInfo) {
            $0.recentBookInfoGeneration = 2
            $0.recentBookInfo[selected.id] = .loading
        }
        await store.receive(\.recentBookInfoLoaded) {
            $0.recentBookInfo[selected.id] = .loaded(.init(holdings: [holding]))
        }
        await store.send(.recentBookInfoCancelled) { $0.recentBookInfoGeneration = 3 }
        await store.send(.recentBookInfoLoaded(generation: 2, selected.id, []))
        await store.send(.recentBookInfoFailed(generation: 2, selected.id))
        await store.send(.recentBookInfoLoaded(generation: 3, "removed", [holding]))
        await store.finish()
    }

    private func book(_ index: Int, id: String? = nil) -> Book {
        Book(id: id ?? "book-\(index)", isbn: "9788966260959", controlNumber: "alma99100095875970328\(index)",
             title: "블렌더 \(index)", author: "권현민", publisher: "출판사", publicationYear: "2023",
             description: "책 소개", imageURL: URL(string: "https://example.com/cover.jpg"), subLocation: "단행본3층")
    }
}
