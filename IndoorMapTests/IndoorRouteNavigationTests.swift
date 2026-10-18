import ComposableArchitecture
import Foundation
import Testing

@testable import fingerprint_library

extension IndoorMapSerialTests {
    @MainActor
    struct IndoorRouteNavigationTests {
        private typealias F = IndoorRoutingTestFactory

        @Test("경로 설정 push·pop은 위치를 유지하고 닫힌 화면의 탐색 결과를 무시한다")
        func pushesAndPopsRouteSettings() async throws {
            let a = F.node("a")
            let b = F.node("b", x: 20)
            let request = F.request(
                graph: F.graph([a, b], [F.edge("ab", a, b)]), start: a.coordinate, target: b.id)
            let outcome = try IndoorRouteSearchEngine().search(request)
            var initial = AppFeature.State()
            initial.indoorMap.navigation = request.navigation
            initial.indoorMap.selectedShelfKey = request.destination
            initial.indoorMap.latestPosition = request.start
            initial.indoorMap.isActive = true
            let started = AsyncStream<Void>.makeStream()
            let store = TestStore(initialState: initial) {
                AppFeature()
            } withDependencies: {
                $0.date.now = F.now
                $0.indoorRouteClient.search = { _ in
                    started.continuation.yield(())
                    try await Task.sleep(for: .seconds(60))
                    return outcome
                }
            }
            await store.send(.indoorMap(.routeSettingsTapped)) {
                $0.indoorMap.routeDestinationKey = request.destination
            }
            await store.receive(\.indoorMap.delegate) { $0.isRouteSettingsPresented = true }
            await store.receive(\.indoorMap.routeRequested) {
                $0.indoorMap.isRouting = true
                $0.indoorMap.routeRequestID = 1
            }
            var iterator = started.stream.makeAsyncIterator()
            _ = await iterator.next()
            await store.send(.indoorMap(.routeSettingsTapped))
            await store.receive(\.indoorMap.delegate)
            await store.send(.routeSettingsPresentationChanged(false)) {
                $0.isRouteSettingsPresented = false
            }
            await store.receive(\.indoorMap.routeCleared) {
                $0.indoorMap.selectedShelfKey = nil
                $0.indoorMap.routeDestinationKey = nil
                $0.indoorMap.isRouting = false
                $0.indoorMap.routeRequestID = 2
            }
            await store.send(.indoorMap(.routeLoaded(requestID: 1, outcome)))
            await store.finish()
            #expect(store.state.indoorMap.isActive)
            #expect(store.state.indoorMap.currentPosition == request.start)
        }

        @Test("목적지가 없으면 경로 설정 화면을 열지 않는다")
        func requiresDestination() async {
            let store = TestStore(initialState: AppFeature.State()) { AppFeature() }
            await store.send(.indoorMap(.routeSettingsTapped))
            await store.send(.routeSettingsPresentationChanged(true))
            #expect(!store.state.isRouteSettingsPresented)
        }

        @Test("위치 포커스는 현재 위치의 층으로 복귀하고 다른 층의 서가 선택을 해제한다")
        func recentersOnCurrentFloor() async {
            var initial = IndoorMapFeature.State()
            initial.map = IndoorMapTestData.map()
            initial.selectedFloorID = IndoorMapTestData.groundID
            initial.selectedShelfKey = .init(datasetID: "c5", value: "ground-shelf")
            initial.authorization = .authorized(precise: true)
            initial.latestPosition = IndoorMapTestData.position()
            let store = TestStore(initialState: initial) {
                IndoorMapFeature()
            } withDependencies: {
                $0.date.now = IndoorMapTestData.now
            }
            await store.send(.currentLocationTapped) {
                $0.selectedFloorID = IndoorMapTestData.upperID
                $0.selectedShelfKey = nil
                $0.cameraRequest = .init(id: 1, target: .position(IndoorMapTestData.point))
            }
        }

        @Test("경로 설정의 이동 방식 변경은 새 조건으로 경로를 재계산한다")
        func recalculatesPreference() async throws {
            let a = F.node("a")
            let b = F.node("b", x: 20)
            let request = F.request(
                graph: F.graph([a, b], [F.edge("ab", a, b)]), start: a.coordinate, target: b.id)
            guard case .route(let route) = try IndoorRouteSearchEngine().search(request) else {
                throw IndoorRoutingError.noRoute
            }
            var initial = IndoorMapFeature.State()
            initial.navigation = request.navigation
            initial.latestPosition = request.start
            initial.routeDestinationKey = request.destination
            initial.route = route
            initial.isActive = true
            let store = TestStore(initialState: initial) {
                IndoorMapFeature()
            } withDependencies: {
                $0.date.now = F.now
                $0.indoorRouteClient.search = { actual in
                    #expect(actual.preference == .elevatorPreferred)
                    return .route(route)
                }
            }
            await store.send(.routePreferenceChanged(.elevatorPreferred)) {
                $0.routePreference = .elevatorPreferred
                $0.route = nil
                $0.isRouting = true
                $0.routeRequestID = 1
            }
            await store.receive(\.routeLoaded) {
                $0.isRouting = false
                $0.route = route
            }
            await store.finish()
        }
    }
}
