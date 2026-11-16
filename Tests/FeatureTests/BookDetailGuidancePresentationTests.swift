import ComposableArchitecture
import Foundation
import Testing
@testable import fingerprint_library

@MainActor
struct BookDetailGuidancePresentationTests {
    private let requestID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    @Test func 상세_닫힘_완료_뒤에_안내를_한_번만_요청한다() async {
        let store = TestStore(initialState: BookDetailFeature.State(book: makeBook(1))) {
            BookDetailFeature()
        } withDependencies: { [requestID] in
            $0.uuid = .init { requestID }
        }

        await store.send(.guidanceStarted) {
            $0.isGuidancePresented = true
            $0.pendingGuidanceRequest = .init(id: requestID, books: [makeBook(1)])
        }
        await store.send(.guidanceStarted)
        await store.send(.guidanceSheetDismissed(requestID: requestID)) {
            $0.pendingGuidanceRequest = nil
        }
        await store.receive(\.delegate.startGuidance, [makeBook(1)])
        await store.send(.guidanceSheetDismissed(requestID: requestID))
        await store.send(.guidanceDismissed) {
            $0.isGuidancePresented = false
        }
        await store.finish()
    }

    @Test func 요청이_취소된_뒤_늦게_온_닫힘_완료는_무시한다() async {
        let store = TestStore(initialState: BookDetailFeature.State(book: makeBook(1))) {
            BookDetailFeature()
        } withDependencies: { [requestID] in
            $0.uuid = .init { requestID }
        }
        await store.send(.guidanceStarted) {
            $0.isGuidancePresented = true
            $0.pendingGuidanceRequest = .init(id: requestID, books: [makeBook(1)])
        }
        await store.send(.guidanceDismissed) {
            $0.isGuidancePresented = false
            $0.pendingGuidanceRequest = nil
        }
        await store.send(.guidanceSheetDismissed(requestID: requestID))
        await store.finish()
    }

    @Test func 장바구니와_상세_시트를_차례로_닫은_뒤_선택한_책을_안내한다() async {
        var state = BookDetailFeature.State(book: makeBook(1))
        state.cart = BookCartFeature.State()
        let store = TestStore(initialState: state) { BookDetailFeature() } withDependencies: { [requestID] in
            $0.uuid = .init { requestID }
        }
        let books = [makeBook(2), makeBook(3)]

        await store.send(.cart(.presented(.delegate(.startGuidance(books))))) {
            $0.cart = nil
            $0.pendingGuidanceRequest = .init(id: requestID, books: books)
        }
        await store.send(.guidanceSheetDismissed(requestID: requestID))
        await store.send(.guidanceStarted)
        await store.send(.cartCoverDismissed) {
            $0.isGuidancePresented = true
        }
        await store.send(.cartCoverDismissed)
        await store.send(.guidanceSheetDismissed(requestID: requestID)) {
            $0.pendingGuidanceRequest = nil
        }
        await store.receive(\.delegate.startGuidance, books)
        await store.finish()
    }

    @Test func 장바구니를_그냥_닫으면_안내를_시작하지_않는다() async {
        let store = TestStore(initialState: BookDetailFeature.State(book: makeBook(1))) {
            BookDetailFeature()
        } withDependencies: { [requestID] in
            $0.uuid = .init { requestID }
        }
        await store.send(.cartCoverDismissed)
        await store.send(.guidanceSheetDismissed(requestID: requestID))
        await store.finish()
    }

    @Test func 이전_요청의_완료_이벤트는_새_안내를_열지_않는다() async {
        let newID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        var state = BookDetailFeature.State(book: makeBook(1))
        state.isGuidancePresented = true
        state.pendingGuidanceRequest = .init(id: newID, books: [makeBook(1)])
        let store = TestStore(initialState: state) { BookDetailFeature() }
        await store.send(.guidanceSheetDismissed(requestID: requestID))
        await store.send(.guidanceSheetDismissed(requestID: newID)) {
            $0.pendingGuidanceRequest = nil
        }
        await store.receive(\.delegate.startGuidance, [makeBook(1)])
        await store.finish()
    }

    @Test func 빈_안내_요청으로_상세_시트를_숨기지_않는다() async {
        var state = BookDetailFeature.State(book: makeBook(1))
        state.cart = BookCartFeature.State()
        let store = TestStore(initialState: state) { BookDetailFeature() } withDependencies: { [requestID] in
            $0.uuid = .init { requestID }
        }
        await store.send(.cart(.presented(.delegate(.startGuidance([])))))
        await store.finish()
    }
}
