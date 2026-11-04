import ComposableArchitecture
import Testing
@testable import fingerprint_library

extension IndoorMapSerialTests {
    @MainActor
    struct BookNavigationPresentationFeatureTests {
        @Test("현재 책 근처에 도착하기 전에는 다음 책 경로로 건너뛰지 않는다")
        func cannotSkipUnreachedStop() async throws {
            var initial = BookNavigationFeature.State(session: try NavigationGuidanceTestFixture.session())
            initial.isCancelConfirmationPresented = true
            let store = TestStore(initialState: initial) { BookNavigationFeature() }
            await store.send(.nextBookTapped)
            await store.finish()
        }

        @Test("현재 서가 도착 후에는 다음 책의 경로·헤더·진행 구간으로 전환한다")
        func nextBookAfterArrival() async throws {
            let session = try NavigationGuidanceTestFixture.session()
            var initial = BookNavigationFeature.State(session: session)
            initial.isCancelConfirmationPresented = true
            initial.progress = try initial.currentPlan?.progress(
                for: NavigationGuidanceTestFixture.position(x: 20, y: 20), at: NavigationGuidanceTestFixture.now)
            let store = TestStore(initialState: initial) { BookNavigationFeature() }
            await store.send(.nextBookTapped) {
                $0.currentStopIndex = 1
                $0.isCancelConfirmationPresented = false
                $0.progress = nil
                $0.statusMessage = "다음 책까지의 위치를 확인하고 있어요."
                $0.cameraRequest = .init(id: 1, target: .route(session.legs[1],
                    featureIDs: session.stops[1].candidateShelves.map(\.mapElementID)))
            }
            #expect(store.state.currentStop?.book == session.stops[1].book)
            #expect(store.state.currentRoute == session.legs[1])
            await store.send(.nextBookTapped)
            await store.finish()
        }

        @Test("시트 높이가 바뀌어도 사용자가 해제한 자동 카메라 추적을 재개하지 않는다")
        func sheetKeepsManualCamera() async throws {
            var initial = BookNavigationFeature.State(session: try NavigationGuidanceTestFixture.session())
            initial.followsNavigationCamera = false
            let store = TestStore(initialState: initial) { BookNavigationFeature() }
            await store.send(.viewportChanged)
            await store.finish()
        }
    }
}
