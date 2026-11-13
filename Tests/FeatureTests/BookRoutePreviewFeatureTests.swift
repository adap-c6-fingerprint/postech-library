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

    @Test func 수동_출발_위치는_주입한_현재_시각으로_만든다() async {
        let now = Date(timeIntervalSinceReferenceDate: 1_000)
        var state = withDependencies { $0.uuid = .incrementing } operation: {
            BookRoutePreviewFeature.State(books: [makeBook(1)], entryMode: .preview)
        }
        state.isOriginPickerPresented = true
        let store = TestStore(initialState: state) { BookRoutePreviewFeature() } withDependencies: {
            $0.uuid = .incrementing
            $0.date.now = now
        }
        store.exhaustivity = .off
        let coordinate = IndoorMapCoordinate(latitude: 36.0127633, longitude: 129.3251348)

        await store.send(.originConfirmed(coordinate, floorOrdinal: 2))

        #expect(!store.state.isOriginPickerPresented)
        #expect(store.state.manualStart == IndoorPosition(
            coordinate: coordinate, floorOrdinal: 2, horizontalAccuracy: nil, timestamp: now, source: .manual))
    }
}
