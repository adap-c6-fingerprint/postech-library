import ComposableArchitecture
import Foundation
import Testing
@testable import fingerprint_library

@MainActor
struct BookSearchCancellationTests {
    @Test("검색 종료 시 화면 상태만 초기화하고 기록·찜·책바구니는 보존한다")
    func cancelPreservesSavedChoices() async {
        let book = Book(
            id: "result", isbn: "9788966260959", controlNumber: "record-1",
            title: "테스트 도서", author: "저자", publisher: nil,
            publicationYear: "2026", description: nil, imageURL: nil
        )
        let keys: Set<[String?]> = [book.recordKey]
        let store = TestStore(initialState: BookSearchFeature.State(
            query: "테스트", recentQueries: ["테스트"], favoriteBookKeys: keys,
            books: [book], errorMessage: "이전 오류", hasSearched: true,
            basketBooks: [book]
        )) {
            BookSearchFeature()
        }

        await store.send(.searchCancelled) {
            $0.searchGeneration += 1
            $0.query = ""
            $0.books = []
            $0.errorMessage = nil
            $0.hasSearched = false
        }
        #expect(store.state.recentQueries == ["테스트"])
        #expect(store.state.favoriteBookKeys == keys)
        #expect(store.state.basketBooks == [book])
    }

    @Test("진행 중 검색을 종료하면 늦은 응답 없이 다시 검색할 수 있다")
    func cancelInFlightAndSearchAgain() async {
        let store = TestStore(initialState: BookSearchFeature.State(query: "이전 검색")) {
            BookSearchFeature()
        } withDependencies: {
            $0.searchHistoryClient.save = { _ in }
            $0.bookClient.search = { request in
                let query = request.query
                if query == "이전 검색" {
                    try await Task.sleep(for: .seconds(60))
                }
                return []
            }
            $0.bookSearchClient = .live(bookClient: $0.bookClient, cache: BookSearchResultCache())
        }

        await store.send(.searchButtonTapped) {
            $0.searchGeneration += 1
            $0.isLoading = true
            $0.hasSearched = true
            $0.recentQueries = ["이전 검색"]
        }
        await store.send(.searchCancelled) {
            $0.searchGeneration += 1
            $0.query = ""
            $0.isLoading = false
            $0.hasSearched = false
        }
        await store.finish()

        await store.send(.queryChanged("새 검색")) { $0.query = "새 검색" }
        await store.send(.searchButtonTapped) {
            $0.searchGeneration += 1
            $0.isLoading = true
            $0.hasSearched = true
            $0.recentQueries = ["새 검색", "이전 검색"]
        }
        await store.receive(\.searchSucceeded) { $0.isLoading = false }
        await store.finish()
    }
}
