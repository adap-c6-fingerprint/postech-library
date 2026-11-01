import ComposableArchitecture
import Foundation
import Testing
@testable import fingerprint_library

extension IndoorMapSerialTests {
    @MainActor
    struct BookNavigationCameraFeatureTests {
        private typealias F = NavigationGuidanceTestFixture

        @Test("자동 확대는 위치를 따라가고 수동 조작 뒤에는 현재 위치 버튼으로 재개한다")
        func pausesAndResumes() async throws {
            let store = try makeStore()
            await store.send(.locationEvent(subscriptionID: 0, .position(F.position(x: 0))))
            let first = store.state.cameraRequest
            guard case .navigation = first.target else { Issue.record("자동 카메라 요청 누락"); return }
            store.dependencies.date.now = F.now.addingTimeInterval(1)
            await store.send(.locationEvent(subscriptionID: 0, .position(F.position(x: 0.5, seconds: 1))))
            #expect(store.state.cameraRequest == first)
            store.dependencies.date.now = F.now.addingTimeInterval(2)
            await store.send(.locationEvent(subscriptionID: 0, .position(F.position(x: 5, seconds: 2))))
            #expect(store.state.cameraRequest.id > first.id)
            await store.send(.mapInteractionBegan)
            let manual = store.state.cameraRequest
            store.dependencies.date.now = F.now.addingTimeInterval(4)
            await store.send(.locationEvent(subscriptionID: 0, .position(F.position(x: 10, seconds: 4))))
            #expect(store.state.latestPosition == F.position(x: 10, seconds: 4))
            #expect(store.state.cameraRequest == manual)
            await store.send(.recenterTapped)
            #expect(store.state.followsNavigationCamera)
            #expect(store.state.cameraRequest.id == manual.id + 1)
            guard case let .navigation(focus) = store.state.cameraRequest.target else {
                Issue.record("다시 현재 위치와 서가를 표시해야 한다"); return
            }
            #expect(focus.coordinates.contains(F.position(x: 10).coordinate))
            await store.send(.disappeared)
            await store.finish()
        }

        @Test("위치가 유효하지 않거나 만료되면 카메라를 움직이지 않고 회복 후 다시 맞춘다")
        func suspendsOnInvalidLocation() async throws {
            let store = try makeStore()
            let position = F.position(x: 5)
            await store.send(.locationEvent(subscriptionID: 0, .position(position)))
            let first = store.state.cameraRequest
            await store.send(.locationEvent(subscriptionID: 0, .temporarilyUnavailable("대기")))
            #expect(store.state.cameraRequest == first)
            store.dependencies.date.now = F.now.addingTimeInterval(1)
            await store.send(.locationEvent(subscriptionID: 0, .position(F.position(x: 5, seconds: 1))))
            #expect(store.state.cameraRequest.id > first.id)
            let recovered = store.state.cameraRequest
            store.dependencies.date.now = F.now.addingTimeInterval(2)
            await store.send(.locationEvent(subscriptionID: 0, .position(F.position(x: 10, accuracy: 50, seconds: 2))))
            #expect(store.state.cameraRequest == recovered)
            await store.send(.disappeared)
            await store.finish()
        }

        @Test("도착 화면에서는 확대를 멈추고 다음 책에서는 새 서가와 경로에 맞춘다")
        func changesDestination() async throws {
            let store = try makeStore()
            await store.send(.locationEvent(subscriptionID: 0, .position(F.position(x: 20, y: 15))))
            await store.send(.arrivalTestTapped)
            let arrived = store.state.cameraRequest
            store.dependencies.date.now = F.now.addingTimeInterval(1)
            await store.send(.locationEvent(subscriptionID: 0, .position(F.position(x: 20, y: 18, seconds: 1))))
            #expect(store.state.cameraRequest == arrived)
            await store.send(.continueFromArrival(stopIndex: 0))
            #expect(store.state.currentStopIndex == 1 && store.state.followsNavigationCamera)
            guard case let .navigation(focus) = store.state.cameraRequest.target else {
                Issue.record("다음 책으로 안내 범위를 바꿔야 한다"); return
            }
            #expect(focus.coordinates.contains(F.position(x: 20).coordinate))
            #expect(!focus.coordinates.contains(F.position(x: 20, y: 20).coordinate))
            #expect(store.state.cameraRequest.id > arrived.id)
            await store.send(.disappeared)
            await store.finish()
        }

        private func makeStore() throws -> TestStore<BookNavigationFeature.State, BookNavigationFeature.Action> {
            var state = BookNavigationFeature.State(session: try F.session())
            state.isActive = true
            state.authorization = .authorized(precise: true)
            let store = TestStore(initialState: state) { BookNavigationFeature() } withDependencies: {
                $0.date.now = F.now
                $0.continuousClock = TestClock()
            }
            store.exhaustivity = .off(showSkippedAssertions: false)
            return store
        }
    }
}
