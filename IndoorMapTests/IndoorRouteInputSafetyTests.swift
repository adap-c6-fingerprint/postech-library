import ComposableArchitecture
import Foundation
import Testing

@testable import fingerprint_library

extension IndoorMapSerialTests {
    @MainActor
    struct IndoorRouteInputSafetyTests {
        private typealias F = IndoorRoutingTestFactory

        private actor SearchProbe {
            var starts: [IndoorPosition] = []
            func record(_ position: IndoorPosition) { starts.append(position) }
        }

        private func request(source: IndoorPosition.Source) -> IndoorRouteRequest {
            let a = F.node("a")
            let b = F.node("b", x: 20)
            let original = F.request(
                graph: F.graph([a, b], [F.edge("ab", a, b)]), start: a.coordinate, target: b.id)
            return .init(
                navigation: original.navigation,
                start: .init(
                    coordinate: a.coordinate, floorOrdinal: 0,
                    horizontalAccuracy: source == .manual ? nil : 1, timestamp: F.now,
                    source: source),
                destination: original.destination, preference: .shortestDistance)
        }

        private func state(_ request: IndoorRouteRequest) -> IndoorMapFeature.State {
            var state = IndoorMapFeature.State()
            state.isActive = true
            state.authorization = .authorized(precise: true)
            state.navigation = request.navigation
            state.routeDestinationKey = request.destination
            state.latestPosition = request.start
            return state
        }

        @Test(
            "공급 실패 후에는 센서·재생·시뮬레이션의 이전 위치로 탐색하지 않고 새 위치 수신 후 복구한다",
            arguments: [IndoorPosition.Source.sensor, .replay, .simulation])
        func blocksUnavailableFix(_ source: IndoorPosition.Source) async throws {
            let request = request(source: source)
            guard case .route(let oldRoute) = try IndoorRouteSearchEngine().search(request) else {
                throw IndoorRoutingError.noRoute
            }
            var initial = state(request)
            initial.route = oldRoute
            let probe = SearchProbe()
            let store = TestStore(initialState: initial) {
                IndoorMapFeature()
            } withDependencies: {
                $0.date.now = F.now
                $0.indoorRouteClient.search = { request in
                    await probe.record(request.start)
                    return try IndoorRouteSearchEngine().search(request)
                }
            }
            await store.send(.locationEvent(.unavailable("위치 공급 실패"))) {
                $0.latestPosition = nil
                $0.locationMessage = "위치 공급 실패"
                $0.route = nil
                $0.routeRequestID = 1
            }
            #expect(store.state.currentPosition == nil)
            await store.send(.routeRequested) {
                $0.routeError = IndoorRoutingError.invalidPosition.localizedDescription
                $0.routeRequestID = 2
            }
            await store.finish()
            #expect(await probe.starts.isEmpty)

            await store.send(.currentLocationTapped) {
                $0.wantsRecenter = true
                $0.locationMessage = "현재 위치를 확인하고 있어요. 위치가 확인되면 지도를 이동할게요."
            }
            let fresh = IndoorPosition(
                coordinate: F.node("fresh", x: 5).coordinate, floorOrdinal: 0,
                horizontalAccuracy: 1, timestamp: F.now.addingTimeInterval(1), source: source)
            await store.send(.locationEvent(.position(fresh))) {
                $0.latestPosition = fresh
                $0.locationMessage = nil
                $0.wantsRecenter = false
                $0.cameraRequest = .init(id: 1, target: .position(fresh.coordinate))
            }
            let freshRequest = IndoorRouteRequest(
                navigation: request.navigation, start: fresh,
                destination: request.destination, preference: .shortestDistance)
            guard case .route(let freshRoute) = try IndoorRouteSearchEngine().search(freshRequest)
            else {
                throw IndoorRoutingError.noRoute
            }
            await store.send(.routeRequested) {
                $0.routeError = nil
                $0.isRouting = true
                $0.routeRequestID = 3
            }
            await store.receive(\.routeLoaded) {
                $0.isRouting = false
                $0.route = freshRoute
            }
            await store.finish()
            #expect(await probe.starts == [fresh])
        }

        @Test(
            "센서 공급 오류는 독립적인 수동 출발점·경로를 유지하며 센서 복귀 때 이전 센서 좌표를 재사용하지 않는다",
            arguments: [IndoorLocationEvent.unavailable("실패"), .temporarilyUnavailable("대기")])
        func preservesIndependentManualOrigin(_ event: IndoorLocationEvent) async throws {
            let request = request(source: .manual)
            guard case .route(let route) = try IndoorRouteSearchEngine().search(request) else {
                throw IndoorRoutingError.noRoute
            }
            var initial = state(request)
            initial.manualPosition = request.start
            initial.latestPosition = self.request(source: .sensor).start
            initial.route = route
            let probe = SearchProbe()
            let store = TestStore(initialState: initial) {
                IndoorMapFeature()
            } withDependencies: {
                $0.date.now = F.now
                $0.indoorRouteClient.search = { actual in
                    await probe.record(actual.start)
                    #expect(actual.start == request.start)
                    return .route(route)
                }
            }
            await store.send(.locationEvent(event)) { $0.latestPosition = nil }
            #expect(store.state.currentPosition == request.start)
            #expect(store.state.route == route)
            await store.send(.routeRequested) {
                $0.route = nil
                $0.isRouting = true
                $0.routeRequestID = 1
            }
            await store.receive(\.routeLoaded) {
                $0.isRouting = false
                $0.route = route
            }
            await store.send(.currentLocationTapped) {
                $0.manualPosition = nil
                $0.wantsRecenter = true
                $0.locationMessage = "현재 위치를 확인하고 있어요. 위치가 확인되면 지도를 이동할게요."
            }
            #expect(store.state.currentPosition == nil)
            await store.send(.routeRequested) {
                $0.route = nil
                $0.routeError = IndoorRoutingError.invalidPosition.localizedDescription
                $0.routeRequestID = 2
            }
            await store.finish()
            #expect(await probe.starts == [request.start])
        }

        @Test(
            "서가에서 20m 떨어진 좌표가 목적지 노드로 연결돼도 실제 도착으로 안내하지 않는다",
            arguments: [0.0, 20.0])
        func distinguishesSnappedStartFromArrival(offset: Double) throws {
            let a = F.node("a")
            let destination = F.node("destination", x: 20)
            let actualCoordinate = F.node("actual", x: 20, y: offset).coordinate
            let request = F.request(
                graph: F.graph([a, destination], [F.edge("path", a, destination)]),
                start: actualCoordinate, target: destination.id)
            guard case .route(let route) = try IndoorRouteSearchEngine().search(request) else {
                throw IndoorRoutingError.noRoute
            }
            #expect(route.startsAtDestinationNode)
            #expect(route.edgeIDs.isEmpty)
            #expect(route.distanceMeters == 0)
            #expect(route.start.actualCoordinate == actualCoordinate)
            #expect(route.start.routeCoordinate == destination.coordinate)
            #expect(abs(route.start.distanceToGraphMeters - offset) < 0.01)
            var presentation = state(request)
            presentation.route = route
            #expect(presentation.routeSummary == "통로 연결 지점이 서가 도착점과 같아요")
        }
    }
}
