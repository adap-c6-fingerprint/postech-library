import ComposableArchitecture
import Foundation
import Testing
@testable import fingerprint_library

@MainActor
struct BookDetailHoldingsFeatureTests {
    private var book: Book {
        Book(id: "primo:alma123", isbn: nil, controlNumber: "primo:alma123", title: "선택한 책",
             author: "저자", publisher: nil, publicationYear: nil, description: nil, imageURL: nil)
    }

    @Test("소장정보를 조회하고 같은 화면의 중복 조회를 막는다")
    func loadOnce() async {
        let holding = BookHolding(recordID: "alma123", callNumber: "QA76", location: "3층", locationCode: "c3b", availability: .available)
        let store = TestStore(initialState: BookDetailFeature.State(book: book)) { BookDetailFeature() } withDependencies: {
            $0.bookHoldingsClient.fetch = { _ in holding }
        }
        await store.send(.loadHoldings) { $0.holdingsState = .loading }
        await store.receive(\.holdingsLoaded) { $0.holdingsState = .loaded(holding) }
        await store.send(.loadHoldings)
        await store.finish()
    }

    @Test("소장 조회 실패 후 재시도할 수 있다")
    func retryAfterFailure() async {
        let store = TestStore(initialState: BookDetailFeature.State(book: book)) { BookDetailFeature() } withDependencies: {
            $0.bookHoldingsClient.fetch = { _ in throw URLError(.notConnectedToInternet) }
        }
        await store.send(.loadHoldings) { $0.holdingsState = .loading }
        await store.receive(\.holdingsFailed) { $0.holdingsState = .failed }
        store.dependencies.bookHoldingsClient.fetch = { _ in nil }
        await store.send(.retryHoldingsButtonTapped) { $0.holdingsState = .loading }
        await store.receive(\.holdingsLoaded) { $0.holdingsState = .loaded(nil) }
        await store.finish()
    }

    @Test("추천 상세에서 담은 책은 검색 탭의 같은 장바구니에 한 번만 저장한다")
    func sharedBasket() async {
        let book = book
        var initial = AppFeature.State()
        initial.home.detail = BookDetailFeature.State(book: book)
        let store = TestStore(initialState: initial) { AppFeature() }
        for attempt in 0..<2 {
            await store.send(.home(.detail(.presented(.addToBasketButtonTapped))))
            await store.receive(\.home.detail.presented.delegate)
            await store.receive(\.home.delegate)
            await store.receive(\.bookSearch.addToBasket) {
                if attempt == 0 { $0.bookSearch.basketBooks = [book] }
            }
        }
        await store.finish()
    }

    @Test("경로 데이터가 연결되면 목업 표시를 실제 요약으로 교체한다")
    func replacesMockRoute() async {
        let store = TestStore(initialState: BookDetailFeature.State(book: book)) { BookDetailFeature() }
        let summary = BookRouteSummary(walkingMinutes: 4, stepCount: 7, distanceMeters: 210, isMock: false)
        await store.send(.routeSummaryUpdated(summary)) { $0.routeSummary = summary }
    }
}
