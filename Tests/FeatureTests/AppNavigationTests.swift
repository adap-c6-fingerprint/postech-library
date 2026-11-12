import ComposableArchitecture
import Foundation
import Testing
@testable import fingerprint_library

@MainActor
struct AppNavigationTests {
    func makeState(_ configure: (inout AppFeature.State) -> Void = { _ in }) -> AppFeature.State {
        withDependencies { $0.uuid = .incrementing } operation: {
            var state = AppFeature.State()
            configure(&state)
            return state
        }
    }

    func makeStore(_ state: AppFeature.State) -> TestStoreOf<AppFeature> {
        let store = TestStore(initialState: state) { AppFeature() } withDependencies: {
            $0.uuid = .incrementing
        }
        store.exhaustivity = .off
        return store
    }

    @Test func 홈의_이동_요청은_추천_탭_스택에_쌓는다() async {
        let store = makeStore(makeState())
        await store.send(.home(.delegate(.showCart)))
        #expect(store.state.recommendationsPath.count == 1)
        #expect(store.state.recommendationsPath.first.flatMap { if case .cart = $0 { true } else { nil } } == true)
        #expect(store.state.mapPath.isEmpty && store.state.searchPath.isEmpty)
    }

    @Test func 검색의_이동_요청은_요청한_지금_탭에_쌓는다() async {
        let store = makeStore(makeState())
        await store.send(.tabSelected(.map))
        await store.send(.bookSearch(.delegate(.showFavorites)))
        #expect(store.state.mapPath.count == 1)
        #expect(store.state.searchPath.isEmpty)
    }

    @Test func 상세의_안내_요청은_Modal로_띄우고_닫히면_그_상세에_알린다() async {
        let store = makeStore(makeState { state in
            state.recommendationsPath.append(.detail(BookDetailFeature.State(book: makeBook(1))))
        })
        let detailID = store.state.recommendationsPath.ids[0]

        await store.send(.recommendationsPath(.element(id: detailID, action: .detail(.guidanceStarted))))
        await store.receive(\.recommendationsPath)
        guard case let .routePreview(preview)? = store.state.modal else {
            Issue.record("경로 미리보기가 뜨지 않았다")
            return
        }
        #expect(preview.entryMode == .direct)
        #expect(preview.destination.books == [makeBook(1)])
        #expect(store.state.guidanceOrigin == .init(tab: .recommendations, elementID: detailID))
        guard case let .detail(detail)? = store.state.recommendationsPath[id: detailID] else { return }
        #expect(detail.isGuidancePresented)

        await store.send(.modal(.dismiss))
        await store.receive(\.recommendationsPath)
        #expect(store.state.modal == nil)
        #expect(store.state.guidanceOrigin == nil)
        guard case let .detail(after)? = store.state.recommendationsPath[id: detailID] else { return }
        #expect(!after.isGuidancePresented)
    }

    @Test func 여러_권_안내는_순서를_확인한_뒤_출발한다() async {
        let store = makeStore(makeState { state in
            state.searchPath.append(.cart(BookCartFeature.State()))
        })
        let cartID = store.state.searchPath.ids[0]
        await store.send(.searchPath(.element(id: cartID, action: .cart(.delegate(.startGuidance([makeBook(1), makeBook(2)]))))))
        guard case let .routePreview(preview)? = store.state.modal else {
            Issue.record("경로 미리보기가 뜨지 않았다")
            return
        }
        #expect(preview.entryMode == .preview)
    }

    @Test func 홈으로_돌아가면_모든_탭_스택과_안내를_닫는다() async {
        let store = makeStore(makeState { state in
            state.selectedTab = .search
            state.searchPath.append(.favorites(BookFavoritesFeature.State()))
            state.recommendationsPath.append(.myPage(MyPageFeature.State()))
            state.modal = .routePreview(BookRoutePreviewFeature.State(books: [makeBook(1)], entryMode: .direct))
        })
        await store.send(.goHomeRequested) {
            $0.searchPath = StackState()
            $0.recommendationsPath = StackState()
            $0.modal = nil
            $0.selectedTab = .map
        }
    }
}
