import ComposableArchitecture
import Foundation
import Testing

@testable import fingerprint_library

extension IndoorMapSerialTests {
    @MainActor
    struct IndoorRouteFeatureTests {
        private typealias F = IndoorRoutingTestFactory
        private func request(stairsOnly: Bool = false) -> IndoorRouteRequest {
            let a = F.node("a")
            let b = F.node("b", x: stairsOnly ? 0 : 20, level: stairsOnly ? 1 : 0)
            return F.request(
                graph: F.graph([a, b], [F.edge("ab", a, b, category: stairsOnly ? .stairs : .walkway)]),
                start: a.coordinate, target: b.id,
                distances: stairsOnly ? ["ab": .init(meters: 10, source: .estimated)] : [:],
                preference: stairsOnly ? .elevatorPreferred : .shortestDistance)
        }
        private func state(_ request: IndoorRouteRequest) -> IndoorMapFeature.State {
            var state = IndoorMapFeature.State()
            state.navigation = request.navigation
            state.selectedShelfKey = request.destination
            state.latestPosition = request.start
            state.routePreference = request.preference
            state.isActive = true
            return state
        }
        @Test("선택한 서가와 현재 위치 스냅샷으로 비동기 탐색하고 결과를 표시한다")
        func searchesSelectedShelf() async throws {
            let request = request()
            let outcome = try IndoorRouteSearchEngine().search(request)
            guard case .route(let route) = outcome else { return }
            let store = TestStore(initialState: state(request)) {
                IndoorMapFeature()
            } withDependencies: {
                $0.date.now = F.now
                $0.indoorRouteClient.search = { actual in
                    #expect(actual == request)
                    return try IndoorRouteSearchEngine().search(actual)
                }
            }
            await store.send(.routeRequested) {
                $0.routeDestinationKey = request.destination
                $0.isRouting = true
                $0.routeRequestID = 1
            }
            await store.receive(\.routeLoaded) {
                $0.isRouting = false
                $0.route = route
            }
            await store.finish()
        }
        @Test("화면 이탈 시 탐색을 취소하고 이전 성공·실패 응답을 무시한다")
        func cancelsAndRejectsOldResults() async throws {
            let request = request()
            let outcome = try IndoorRouteSearchEngine().search(request)
            let started = AsyncStream<Void>.makeStream()
            let store = TestStore(initialState: state(request)) {
                IndoorMapFeature()
            } withDependencies: {
                $0.date.now = F.now
                $0.indoorRouteClient.search = { _ in
                    started.continuation.yield(())
                    try await Task.sleep(for: .seconds(5))
                    return outcome
                }
            }
            await store.send(.routeRequested) {
                $0.routeDestinationKey = request.destination
                $0.isRouting = true
                $0.routeRequestID = 1
            }
            var iterator = started.stream.makeAsyncIterator()
            _ = await iterator.next()
            await store.send(.disappeared) {
                $0.isActive = false
                $0.isRouting = false
                $0.routeRequestID = 2
            }
            await store.send(.routeLoaded(requestID: 1, outcome))
            await store.send(.routeFailed(requestID: 1, "이전 오류"))
            await store.finish()
            #expect(store.state.route == nil)
        }
        @Test("계단 확인 후 새 현재 위치로 다시 탐색하며 다음 요청에 허용을 영구 저장하지 않는다")
        func confirmsStairFallback() async throws {
            let request = request(stairsOnly: true)
            var confirmed = request
            confirmed.allowsStairFallback = true
            guard case .route(let route) = try IndoorRouteSearchEngine().search(confirmed) else { return }
            let store = TestStore(initialState: state(request)) {
                IndoorMapFeature()
            } withDependencies: {
                $0.date.now = F.now
                $0.indoorRouteClient.search = { try IndoorRouteSearchEngine().search($0) }
            }
            await store.send(.routeRequested) {
                $0.routeDestinationKey = request.destination
                $0.isRouting = true
                $0.routeRequestID = 1
            }
            await store.receive(\.routeLoaded) {
                $0.isRouting = false
                $0.requiresStairConfirmation = true
            }
            await store.send(.useStairsTapped) {
                $0.requiresStairConfirmation = false
                $0.isRouting = true
                $0.routeRequestID = 2
            }
            await store.receive(\.routeLoaded) {
                $0.isRouting = false
                $0.route = route
            }
            await store.send(.routeRequested) {
                $0.route = nil
                $0.isRouting = true
                $0.routeRequestID = 3
            }
            await store.receive(\.routeLoaded) {
                $0.isRouting = false
                $0.requiresStairConfirmation = true
            }
            await store.send(.dismissStairConfirmation) { $0.requiresStairConfirmation = false }
            await store.finish()
        }
        @Test("위치 단절은 기존 경로를 지우고 오래된 위치로 새 탐색을 시작하지 않는다")
        func requiresAvailableCurrentPosition() async throws {
            let request = request()
            guard case .route(let route) = try IndoorRouteSearchEngine().search(request) else { return }
            var initial = state(request)
            initial.route = route
            initial.routeDestinationKey = request.destination
            let store = TestStore(initialState: initial) {
                IndoorMapFeature()
            } withDependencies: {
                $0.date.now = F.now
            }
            await store.send(.locationEvent(.unavailable("단절"))) {
                $0.latestPosition = nil
                $0.locationMessage = "단절"
                $0.route = nil
                $0.routeRequestID = 1
            }
            await store.send(.routeRequested) {
                $0.routeRequestID = 2
                $0.routeError = IndoorRoutingError.invalidPosition.localizedDescription
            }
            await store.finish()
        }
    }
}
