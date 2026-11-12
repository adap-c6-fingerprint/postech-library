import ComposableArchitecture
import Foundation
import Testing
@testable import fingerprint_library

@MainActor
struct BookCartFeatureTests {
    func makeStore(cart numbers: [Int]) -> TestStoreOf<BookCartFeature> {
        @Shared(.bookCart) var cart
        $cart.withLock { $0 = makeCartItems(numbers) }
        return TestStore(initialState: BookCartFeature.State()) { BookCartFeature() }
    }

    @Test func 네_번째_책을_고르면_한도_알림을_한_번만_띄운다() async {
        let store = makeStore(cart: [1, 2, 3, 4, 5])
        for number in 1...3 {
            await store.send(.selectionToggled(makeBook(number).id)) {
                $0.selectedIDs.append(makeBook(number).id)
            }
        }
        await store.send(.selectionToggled(makeBook(4).id)) {
            $0.selectedIDs.append(makeBook(4).id)
            $0.$hasShownGuidanceLimitAlert.withLock { $0 = true }
            $0.isGuidanceLimitAlertPresented = true
        }
        #expect(!store.state.canStartGuidance)
        await store.send(.guidanceLimitAlertDismissed) { $0.isGuidanceLimitAlertPresented = false }
        await store.send(.selectionToggled(makeBook(4).id)) { $0.selectedIDs.removeLast() }
        await store.send(.selectionToggled(makeBook(5).id)) {
            // 이미 한 번 보여 줬으면 다시 띄우지 않는다.
            $0.selectedIDs.append(makeBook(5).id)
        }
    }

    @Test func 고른_책을_지우면_책바구니에서_빼고_선택을_비운다() async {
        let store = makeStore(cart: [1, 2, 3])
        await store.send(.selectionToggled(makeBook(2).id)) { $0.selectedIDs = [makeBook(2).id] }
        await store.send(.removeButtonTapped) { $0.isRemoveAlertPresented = true }
        await store.send(.removeConfirmed) {
            $0.isRemoveAlertPresented = false
            $0.selectedIDs = []
            $0.$items.withLock { $0 = makeCartItems([1, 3]) }
        }
    }

    @Test func 안내_시작은_고른_순서대로_한_권에서_세_권까지만_요청한다() async {
        let store = makeStore(cart: [1, 2])
        await store.send(.guidanceLinkTapped)

        await store.send(.selectionToggled(makeBook(2).id)) { $0.selectedIDs = [makeBook(2).id] }
        await store.send(.selectionToggled(makeBook(1).id)) { $0.selectedIDs.append(makeBook(1).id) }
        await store.send(.guidanceLinkTapped)
        await store.receive(\.delegate.startGuidance, [makeBook(2), makeBook(1)])
    }

    @Test func 다른_화면에서_책이_빠지면_선택에서도_뺀다() async {
        let store = makeStore(cart: [1, 2])
        await store.send(.selectionToggled(makeBook(1).id)) { $0.selectedIDs = [makeBook(1).id] }
        @Shared(.bookCart) var cart
        $cart.withLock { $0 = makeCartItems([2]) }
        await store.send(.task) { $0.selectedIDs = [] }
    }
}
