import ComposableArchitecture
import Foundation
import Testing
@testable import fingerprint_library

@MainActor
struct BookBasketMergeIntegrationTests {
    @Test("홈에서 삭제하면 검색 권수와 다른 열린 책바구니의 선택도 즉시 갱신된다")
    func homeDeletionSynchronizesSearchAndOpenBaskets() async {
        let suite = "BookBasketMergeIntegrationTests.\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let client = BookBasketClient.userDefaults(suiteName: suite)
        let items = [item("a"), item("b")]
        client.save(items)
        var initial = AppFeature.State()
        initial.bookSearch.category = .journal
        initial.bookSearch.basketBooks = items.map(\.book)
        initial.home.basket = BookBasketFeature.State(
            items: items, isSelectingForGuidance: true, selectedIDs: [items[0].id]
        )
        initial.bookSearch.basket = BookBasketFeature.State(
            items: items, isSelectingForGuidance: true, selectedIDs: items.map(\.id)
        )
        let store = TestStore(initialState: initial) { AppFeature() } withDependencies: {
            $0.bookBasketClient = client
        }
        await store.send(.home(.basket(.presented(.removeConfirmed)))) {
            $0.home.basket?.items = [items[1]]
            $0.home.basket?.selectedIDs = []
            $0.bookSearch.basketBooks = [items[1].book]
            $0.bookSearch.basket?.items = [items[1]]
            $0.bookSearch.basket?.selectedIDs = [items[1].id]
        }
        #expect(client.load() == [items[1]])
        await store.send(.home(.basket(.dismiss))) { $0.home.basket = nil }
        await store.send(.bookSearch(.task))
        #expect(store.state.bookSearch.category == .journal)
        #expect(store.state.bookSearch.basketBooks == [items[1].book])
        await store.finish()
    }

    @Test("검색에서 담으면 열린 홈 책바구니에도 반영하고 중복 담기는 시각을 바꾸지 않는다")
    func searchAdditionSynchronizesHomeWithoutDuplicating() async {
        let suite = "BookBasketMergeIntegrationTests.\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let client = BookBasketClient.userDefaults(suiteName: suite)
        let selected = item("a")
        var initial = AppFeature.State()
        initial.home.basket = BookBasketFeature.State()
        let store = TestStore(initialState: initial) { AppFeature() } withDependencies: {
            $0.bookBasketClient = client
            $0.date.now = selected.addedAt
        }
        await store.send(.bookSearch(.addToBasket(selected.book))) {
            $0.bookSearch.basketBooks = [selected.book]
            $0.home.basket?.items = [selected]
        }
        store.dependencies.date.now = Date(timeIntervalSince1970: 9_999)
        await store.send(.bookSearch(.addToBasket(selected.book)))
        #expect(client.load() == [selected])
        await store.finish()
    }

    @Test("검색 책바구니에서 고른 순서대로 서가 지도를 열고 검색 분류·결과·찜을 유지한다")
    func searchBasketDirectionsPreservesSearch() async {
        let items = [item("a"), item("b")]
        var initial = BookSearchFeature.State(
            query: "Nature", category: .journal, recentQueries: ["Nature"],
            favoriteBookKeys: [items[0].book.recordKey], books: items.map(\.book),
            hasSearched: true, basketBooks: items.map(\.book)
        )
        initial.basket = BookBasketFeature.State(
            items: items, isSelectingForGuidance: true, selectedIDs: [items[1].id, items[0].id]
        )
        let store = TestStore(initialState: initial) { BookSearchFeature() }
        await store.send(.basket(.presented(.startGuidanceButtonTapped)))
        await store.receive(\.basket.presented.delegate) {
            $0.shelfMap = BookShelfMapFeature.State(books: [items[1].book, items[0].book])
        }
        await store.send(.shelfMap(.dismiss)) { $0.shelfMap = nil }
        #expect(store.state == initial)
        await store.finish()
    }

    @Test("홈 책바구니와 상세의 안내 요청은 실제 서가 지도 상태로 연결된다")
    func homeGuidanceConnectsBasketAndDetail() async {
        let selected = item("a")
        var initial = HomeFeature.State()
        initial.basket = BookBasketFeature.State(
            items: [selected], isSelectingForGuidance: true, selectedIDs: [selected.id]
        )
        initial.detail = BookDetailFeature.State(book: selected.book, isFavorite: true)
        let store = TestStore(initialState: initial) { HomeFeature() }
        await store.send(.basket(.presented(.startGuidanceButtonTapped)))
        await store.receive(\.basket.presented.delegate) {
            $0.shelfMap = BookShelfMapFeature.State(book: selected.book)
        }
        await store.send(.shelfMap(.dismiss)) { $0.shelfMap = nil }
        await store.send(.detail(.presented(.startGuidanceButtonTapped)))
        await store.receive(\.detail.presented.delegate) {
            $0.shelfMap = BookShelfMapFeature.State(book: selected.book)
        }
        #expect(store.state.detail?.isFavorite == true)
        await store.finish()
    }

    @Test("검색 재진입은 저장소에서 삭제된 책을 화면 목록에서도 제거한다")
    func taskRemovesStaleBasketEntries() async {
        let selected = item("a")
        let store = TestStore(initialState: BookSearchFeature.State(basketBooks: [selected.book])) {
            BookSearchFeature()
        } withDependencies: {
            $0.bookBasketClient.load = { [] }
        }
        await store.send(.task) { $0.basketBooks = [] }
        await store.finish()
    }

    private func item(_ id: String) -> BookBasketItem {
        BookBasketItem(
            book: Book(id: id, isbn: nil, controlNumber: "alma\(id)", title: "도서 \(id)",
                       author: "저자", publisher: nil, publicationYear: nil,
                       description: nil, imageURL: nil),
            addedAt: Date(timeIntervalSince1970: 1_000)
        )
    }
}
