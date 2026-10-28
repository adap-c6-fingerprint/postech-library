import ComposableArchitecture
import Foundation
import Testing
@testable import fingerprint_library

@MainActor
struct BookHoldingsIntegrationTests {
    @Test("상세는 전체 소장처를 보존하면서 표시할 대표 항목만 선택한다")
    func preservesHoldingsAndSelectsPresentation() {
        let unavailable = holding("unavailable", availability: "unavailable")
        let unknown = holding("unknown", availability: "check_holdings")
        let available = holding("available", availability: "available")
        let holdings = [unavailable, unknown, available]
        var state = BookDetailFeature.State(book: book())
        state.holdingsState = .loaded(holdings)
        #expect(state.displayedHolding == available)
        #expect(state.holdingsState == .loaded(holdings))
        #expect(BookHoldingPresentation.preferred(in: [unavailable, unknown]) == unknown)
        #expect(BookHoldingPresentation.preferred(in: []) == nil)
    }

    @Test("상세의 서가 지도는 같은 책·전체 소장처를 받고 기존 찜·상세 상태를 보존한다")
    func detailDirectionsReusesLoadedHoldings() async {
        let selected = book()
        let holdings = [holding("general"), holding("smart", locationCode: "smart")]
        var initial = BookDetailFeature.State(book: selected, isFavorite: true)
        initial.holdingsState = .loaded(holdings)
        let store = TestStore(initialState: initial) { BookDetailFeature() }
        await store.send(.directionsButtonTapped) {
            var destination = BookShelfMapFeature.State(book: selected)
            destination.holdings[selected.id] = .loaded(holdings)
            $0.shelfMap = destination
        }
        #expect(store.state.isFavorite)
        #expect(store.state.holdingsState == .loaded(holdings))
        await store.send(.shelfMap(.dismiss)) { $0.shelfMap = nil }
        #expect(store.state.book == selected)
        await store.finish()
    }

    @Test("자료번호 없는 상세는 다른 판본 조회 없이 실패 상태를 표시한다")
    func detailRejectsMissingRecordID() async {
        let selected = Book(id: "local", isbn: "9788966260959", controlNumber: nil,
                            title: "선택한 책", author: "저자", publisher: nil,
                            publicationYear: nil, description: nil, imageURL: nil)
        let store = TestStore(initialState: BookDetailFeature.State(book: selected)) { BookDetailFeature() }
        await store.send(.loadHoldings) { $0.holdingsState = .failed }
        await store.finish()
    }

    @Test("검색 분류·검색 결과·찜을 유지하며 선택 도서의 서가 지도를 연다")
    func searchDirectionsPreservesCategory() async {
        let selected = book()
        var initial = BookSearchFeature.State(query: "Nature", category: .journal,
                                             favoriteBookKeys: [selected.recordKey], books: [selected],
                                             hasSearched: true, basketBooks: [selected])
        initial.recentQueries = ["Nature"]
        let store = TestStore(initialState: initial) { BookSearchFeature() }
        await store.send(.directionsButtonTapped(selected)) {
            $0.shelfMap = BookShelfMapFeature.State(book: selected)
        }
        await store.send(.shelfMap(.dismiss)) { $0.shelfMap = nil }
        #expect(store.state == initial)
        await store.finish()
    }

    @Test("추천 상세의 책바구니 추가·검색의 삭제·길안내가 루트의 같은 목록을 사용한다")
    func rootBasketDirectionsUsesSharedSelection() async {
        let selected = book(), other = book("alma991000958759703280")
        let suite = "BookHoldingsIntegrationTests.\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let client = BookBasketClient.userDefaults(suiteName: suite)
        client.save([BookBasketItem(book: other, addedAt: .distantPast)])
        var initial = AppFeature.State()
        initial.home.detail = BookDetailFeature.State(book: selected)
        initial.bookSearch.category = .journal
        initial.bookSearch.basketBooks = [other]
        let store = TestStore(initialState: initial) { AppFeature() } withDependencies: {
            $0.bookBasketClient = client
            $0.date.now = Date(timeIntervalSince1970: 1_000)
        }
        await store.send(.home(.detail(.presented(.addToBasketButtonTapped)))) {
            $0.bookSearch.basketBooks = [other, selected]
        }
        await store.send(.bookSearch(.removeFromBasket([other.id]))) { $0.bookSearch.basketBooks = [selected] }
        await store.send(.bookSearch(.basketDirectionsButtonTapped([selected.id]))) {
            $0.bookSearch.shelfMap = BookShelfMapFeature.State(book: selected)
        }
        #expect(store.state.bookSearch.category == .journal)
        #expect(store.state.bookSearch.shelfMap?.books == [selected])
        await store.send(.bookSearch(.shelfMap(.dismiss))) { $0.bookSearch.shelfMap = nil }
        await store.finish()
    }

    private func book(_ recordID: String = "alma991000958759703286") -> Book {
        Book(id: "primo:\(recordID)", isbn: "9788966260959", controlNumber: "primo:\(recordID)",
             title: "선택한 책", author: "저자", publisher: nil, publicationYear: nil,
             description: nil, imageURL: nil)
    }

    private func holding(_ id: String, availability: String = "available", locationCode: String = "c3b") -> BookHolding {
        BookHolding(holdingID: id, institutionCode: "82POSTECH_INST", libraryCode: "MAIN",
                    locationCode: locationCode, locationName: id, callNumber: "CB113.H4 .H3713 2015",
                    availability: availability)
    }
}
