import ComposableArchitecture
import Foundation
import Testing
@testable import fingerprint_library

@MainActor
struct BookDetailHoldingsFeatureTests {
    private var book: Book {
        Book(id: "primo:alma991000958759703286", isbn: nil, controlNumber: "primo:alma991000958759703286", title: "선택한 책",
             author: "저자", publisher: nil, publicationYear: nil, description: nil, imageURL: nil)
    }

    @Test("소장정보를 조회하고 같은 화면의 중복 조회를 막는다")
    func loadOnce() async {
        let holding = BookHolding(holdingID: "holding-1", institutionCode: "82POSTECH_INST", libraryCode: "MAIN", locationCode: "c3b", locationName: "3층", callNumber: "QA76", availability: "available")
        let store = TestStore(initialState: BookDetailFeature.State(book: book)) { BookDetailFeature() } withDependencies: {
            $0.bookHoldingsClient.fetch = { recordID in
                #expect(recordID == "alma991000958759703286")
                return [holding]
            }
        }
        await store.send(.loadHoldings) { $0.holdingsState = .loading }
        await store.receive(\.holdingsLoaded) { $0.holdingsState = .loaded([holding]) }
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
        store.dependencies.bookHoldingsClient.fetch = { _ in [] }
        await store.send(.retryHoldingsButtonTapped) { $0.holdingsState = .loading }
        await store.receive(\.holdingsLoaded) { $0.holdingsState = .loaded([]) }
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
            if attempt == 0 {
                await store.receive(\.bookSearch.addToBasket) { $0.bookSearch.basketBooks = [book] }
            } else {
                await store.receive(\.bookSearch.addToBasket)
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
