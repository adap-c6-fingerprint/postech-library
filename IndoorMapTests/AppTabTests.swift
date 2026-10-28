import ComposableArchitecture
import Testing
@testable import fingerprint_library

@MainActor
struct AppTabTests {
    @Test("앱은 홈(지도) 탭에서 시작한다")
    func startsOnHomeTab() {
        #expect(AppFeature.State().selectedTab == .home)
    }

    @Test("하단 탭바에서 홈을 누르면 메인 지도 탭으로 돌아온다")
    func selectsHomeTab() async {
        let store = TestStore(initialState: AppFeature.State()) { AppFeature() }
        await store.send(.tabSelected(.recommendation)) {
            $0.selectedTab = .recommendation
        }
        await store.send(.tabSelected(.home)) {
            $0.selectedTab = .home
        }
    }

    @Test("이미 홈 탭일 때 홈을 다시 눌러도 지도 상태는 바뀌지 않는다")
    func reselectingHomeKeepsMapState() async {
        let store = TestStore(initialState: AppFeature.State()) { AppFeature() }
        await store.send(.tabSelected(.home))
    }
}
