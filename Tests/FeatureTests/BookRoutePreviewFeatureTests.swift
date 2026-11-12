import ComposableArchitecture
import Foundation
import Testing
@testable import fingerprint_library

@MainActor
struct BookRoutePreviewFeatureTests {
    @Test func 늦게_온_이전_요청의_실패는_최신_요청을_덮지_않는다() async {
        var state = withDependencies { $0.uuid = .incrementing } operation: {
            BookRoutePreviewFeature.State(books: [makeBook(1), makeBook(2)], entryMode: .preview)
        }
        state.requestID = 2
        state.isLoadingRoute = true
        state.lastRequest = state.routeRequest
        let store = TestStore(initialState: state) { BookRoutePreviewFeature() } withDependencies: {
            $0.uuid = .incrementing
        }
        store.exhaustivity = .off

        await store.send(.routeFailed(requestID: 1, "이전 요청 실패"))
        #expect(store.state.isLoadingRoute)
        #expect(store.state.routeError == nil)

        await store.send(.routeFailed(requestID: 2, "최신 요청 실패"))
        #expect(!store.state.isLoadingRoute)
        #expect(store.state.routeError == "최신 요청 실패")
    }

    @Test func 지금_안내할_수_없을_때_책을_책바구니에_담고_닫는다() async {
        let state = withDependencies { $0.uuid = .incrementing } operation: {
            BookRoutePreviewFeature.State(books: [makeBook(1)], entryMode: .direct)
        }
        let isDismissed = LockIsolated(false)
        let store = TestStore(initialState: state) { BookRoutePreviewFeature() } withDependencies: {
            $0.uuid = .incrementing
            $0.date.now = Date(timeIntervalSinceReferenceDate: 0)
            $0.dismiss = DismissEffect { isDismissed.setValue(true) }
        }
        store.exhaustivity = .off
        await store.send(.addToCartTapped)
        await store.finish()
        @Shared(.bookCart) var cart
        #expect(cart.map(\.book.id) == [makeBook(1).id])
        #expect(isDismissed.value)
    }
}
