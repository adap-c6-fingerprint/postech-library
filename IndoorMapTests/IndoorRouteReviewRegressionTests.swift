import ComposableArchitecture
import CoreLocation
import Foundation
import Testing

@testable import fingerprint_library

struct IndoorRouteReviewRegressionTests {
    private typealias F = IndoorRoutingTestFactory

    @Test("같은 방향으로 이어지는 엘리베이터 간선은 한 번의 탑승으로 표시한다")
    func mergesContinuousElevatorRide() throws {
        let a = F.node("a")
        let b = F.node("b", level: 4)
        let c = F.node("c", level: 5)
        let request = F.request(
            graph: F.graph(
                [a, b, c],
                [F.edge("ab", a, b, category: .elevator), F.edge("bc", b, c, category: .elevator)]),
            start: a.coordinate, target: c.id,
            distances: [
                "ab": .init(meters: 14, source: .estimated),
                "bc": .init(meters: 3.5, source: .estimated),
            ])
        let route = try route(request)
        #expect(route.floorChanges.count == 1)
        #expect(route.floorChanges.first?.fromFloorID == a.floorID)
        #expect(route.floorChanges.first?.toFloorID == c.floorID)
        #expect(route.floorChanges.first?.edgeIDs == ["ab", "bc"])
        #expect(route.edgeIDs == ["ab", "bc"])
        #expect(route.distanceMeters == 17.5)
    }

    @Test("실제 C5 1층→6층 엘리베이터 경로를 한 번의 탑승으로 표시한다")
    func countsC5ElevatorRide() async throws {
        let map = try await BundledIndoorMapLoader().loadC5()
        let data = try await BundledIndoorNavigationLoader().loadC5(on: map)
        let shelf = try #require(
            data.shelves.destinations.first { shelf in
                data.graph.nodes.first { $0.id == shelf.arrivalNodeID }?.level == 5
            })
        for start in data.graph.nodes where start.level == 0 {
            let request = IndoorRouteRequest(
                navigation: data,
                start: .init(
                    coordinate: start.coordinate, floorOrdinal: start.level,
                    horizontalAccuracy: 0, timestamp: Date(), source: .simulation),
                destination: shelf.key, preference: .elevatorPreferred)
            #expect(try route(request).floorChanges.count == 1)
        }
    }

    @Test(
        "수동 출발점만 정확도 값 없이 허용하고 센서·재생·시뮬레이션은 정확도를 요구한다",
        arguments: [IndoorPosition.Source.manual, .sensor, .replay, .simulation])
    func validatesAccuracyBySource(_ source: IndoorPosition.Source) throws {
        let a = F.node("a")
        let b = F.node("b", x: 20)
        let original = F.request(
            graph: F.graph([a, b], [F.edge("ab", a, b)]), start: a.coordinate, target: b.id)
        let request = IndoorRouteRequest(
            navigation: original.navigation,
            start: .init(
                coordinate: a.coordinate, floorOrdinal: 0, horizontalAccuracy: nil,
                timestamp: F.now, source: source),
            destination: original.destination, preference: .shortestDistance)
        if source == .manual {
            #expect(try route(request).edgeIDs == ["ab"])
        } else {
            #expect(throws: IndoorRoutingError.invalidPosition) { try route(request) }
        }
    }

    @Test(
        "도보 환승이나 층 이동 방향 전환이 있으면 엘리베이터 탑승을 합치지 않는다",
        arguments: [false, true])
    func preservesRealTransfers(reversesDirection: Bool) throws {
        let a = F.node("a")
        let b = F.node("b", level: reversesDirection ? 5 : 4)
        let c = F.node("c", x: reversesDirection ? 0 : 5, level: 4)
        let d = F.node("d", x: 5, level: 5)
        let edges =
            reversesDirection
            ? [F.edge("ab", a, b, category: .elevator), F.edge("bc", b, c, category: .elevator)]
            : [
                F.edge("ab", a, b, category: .elevator), F.edge("walk", b, c),
                F.edge("cd", c, d, category: .elevator),
            ]
        let distances: [String: RouteEdgeDistance] =
            reversesDirection
            ? [
                "ab": .init(meters: 17.5, source: .estimated),
                "bc": .init(meters: 3.5, source: .estimated),
            ]
            : [
                "ab": .init(meters: 14, source: .estimated),
                "cd": .init(meters: 3.5, source: .estimated),
            ]
        let request = F.request(
            graph: F.graph(reversesDirection ? [a, b, c] : [a, b, c, d], edges),
            start: a.coordinate, target: reversesDirection ? c.id : d.id, distances: distances)
        #expect(try route(request).floorChanges.count == 2)
    }

    @Test("층 정보 누락과 해당 층의 길찾기 데이터 누락을 구분하고 수동 위치도 통로 반경을 지킨다")
    func distinguishesMissingFloorData() throws {
        let a = F.node("a")
        let b = F.node("b", x: 20)
        let original = F.request(
            graph: F.graph([a, b], [F.edge("ab", a, b)]), start: a.coordinate, target: b.id)
        func request(level: Int?, coordinate: IndoorMapCoordinate? = nil) -> IndoorRouteRequest {
            .init(
                navigation: original.navigation,
                start: .init(
                    coordinate: coordinate ?? a.coordinate, floorOrdinal: level,
                    horizontalAccuracy: nil,
                    timestamp: F.now, source: .manual),
                destination: original.destination, preference: .shortestDistance)
        }
        #expect(throws: IndoorRoutingError.unknownFloor) { try route(request(level: nil)) }
        #expect(throws: IndoorRoutingError.noRoutingDataForFloor) { try route(request(level: 2)) }
        #expect(throws: IndoorRoutingError.farFromGraph) {
            try route(request(level: 0, coordinate: F.node("far", y: 100).coordinate))
        }
    }

    @Test("Core Location의 일시 오류와 권한 철회·다른 실패를 구분한다")
    func classifiesLocationFailures() {
        func event(_ code: CLError.Code) -> IndoorLocationEvent {
            LiveIndoorLocationProvider.failureEvent(
                for: NSError(domain: kCLErrorDomain, code: code.rawValue))
        }
        guard case .temporarilyUnavailable = event(.locationUnknown) else {
            Issue.record("locationUnknown을 일시적인 위치 대기로 처리하지 않았습니다.")
            return
        }
        #expect(event(.denied) == .authorization(.denied))
        guard case .unavailable = event(.network) else {
            Issue.record("그 밖의 위치 실패 처리가 바뀌었습니다.")
            return
        }
    }

    private func route(_ request: IndoorRouteRequest) throws -> IndoorRoute {
        guard case .route(let route) = try IndoorRouteSearchEngine().search(request) else {
            throw IndoorRoutingError.noRoute
        }
        return route
    }
}

extension IndoorMapSerialTests {
    @MainActor
    struct IndoorRouteLifecycleReviewTests {
        private typealias F = IndoorRoutingTestFactory

        @Test("일시적인 비활성화·재활성화는 완료된 경로 미리보기를 보존한다")
        func retainsCompletedPreview() async throws {
            let a = F.node("a")
            let b = F.node("b", x: 20)
            let request = F.request(
                graph: F.graph([a, b], [F.edge("ab", a, b)]), start: a.coordinate, target: b.id)
            guard case .route(let route) = try IndoorRouteSearchEngine().search(request) else {
                throw IndoorRoutingError.noRoute
            }
            var initial = IndoorMapFeature.State()
            initial.isActive = true
            initial.route = route
            initial.routeDestinationKey = request.destination
            initial.latestPosition = request.start
            let events = AsyncStream<IndoorLocationEvent>.makeStream()
            let store = TestStore(initialState: initial) {
                IndoorMapFeature()
            } withDependencies: {
                $0.date.now = F.now
                $0.indoorLocationClient.events = { events.stream }
            }
            await store.send(.sceneActiveChanged(false)) { $0.isActive = false }
            await store.send(.sceneActiveChanged(true)) { $0.isActive = true }
            // 실제 simulator provider도 재구독 시 이 초기 상태를 전달한다.
            events.continuation.yield(.temporarilyUnavailable("연결 대기"))
            await store.receive(\.locationEvent) {
                $0.latestPosition = nil
                $0.locationMessage = "연결 대기"
            }
            #expect(store.state.route == route)
            events.continuation.yield(.position(request.start))
            await store.receive(\.locationEvent) {
                $0.latestPosition = request.start
                $0.locationMessage = nil
            }
            #expect(store.state.route == route)
            events.continuation.finish()
            await store.finish()
        }

        @Test("일시적 위치 오류는 경로를 보존하고 오래된 위치로 재계산하지 않는다")
        func retainsPreviewDuringSignalLoss() async throws {
            let a = F.node("a")
            let b = F.node("b", x: 20)
            let request = F.request(
                graph: F.graph([a, b], [F.edge("ab", a, b)]), start: a.coordinate, target: b.id)
            guard case .route(let route) = try IndoorRouteSearchEngine().search(request) else {
                throw IndoorRoutingError.noRoute
            }
            var initial = IndoorMapFeature.State()
            initial.isActive = true
            initial.route = route
            initial.routeDestinationKey = request.destination
            initial.navigation = request.navigation
            initial.latestPosition = request.start
            let store = TestStore(initialState: initial) {
                IndoorMapFeature()
            } withDependencies: {
                $0.date.now = F.now
            }
            await store.send(.locationEvent(.temporarilyUnavailable("위치 신호 대기"))) {
                $0.latestPosition = nil
                $0.locationMessage = "위치 신호 대기"
            }
            #expect(store.state.route == route)
            #expect(store.state.currentPosition == nil)
            // 권한 철회는 일시 오류가 아니므로 기존 경로까지 무효화한다.
            await store.send(.locationEvent(.authorization(.denied))) {
                $0.authorization = .denied
                $0.route = nil
                $0.routeRequestID = 1
            }
            await store.finish()
        }

        @Test(
            "비활성화·일시 위치 오류는 진행 중인 탐색을 취소하고 늦은 결과를 버린다",
            arguments: [false, true])
        func cancelsPendingSearch(temporaryLocationFailure: Bool) async throws {
            let a = F.node("a")
            let b = F.node("b", x: 20)
            let request = F.request(
                graph: F.graph([a, b], [F.edge("ab", a, b)]), start: a.coordinate, target: b.id)
            let outcome = try IndoorRouteSearchEngine().search(request)
            var initial = IndoorMapFeature.State()
            initial.isActive = true
            initial.navigation = request.navigation
            initial.latestPosition = request.start
            initial.routeDestinationKey = request.destination
            let started = AsyncStream<Void>.makeStream()
            let store = TestStore(initialState: initial) {
                IndoorMapFeature()
            } withDependencies: {
                $0.date.now = F.now
                $0.indoorRouteClient.search = { _ in
                    started.continuation.yield(())
                    try await Task.sleep(for: .seconds(60))
                    return outcome
                }
            }
            await store.send(.routeRequested) {
                $0.isRouting = true
                $0.routeRequestID = 1
            }
            var iterator = started.stream.makeAsyncIterator()
            _ = await iterator.next()
            await store.send(
                temporaryLocationFailure
                    ? .locationEvent(.temporarilyUnavailable("대기")) : .sceneActiveChanged(false)
            ) {
                if temporaryLocationFailure {
                    $0.latestPosition = nil
                    $0.locationMessage = "대기"
                } else {
                    $0.isActive = false
                }
                $0.isRouting = false
                $0.routeRequestID = 2
            }
            await store.send(.routeLoaded(requestID: 1, outcome))
            await store.send(.routeFailed(requestID: 1, "늦은 오류"))
            await store.finish()
        }

        @Test("비활성화 후에는 이전 계단 확인을 사용해 탐색을 시작하지 않는다")
        func cancelsStairConfirmation() async {
            var initial = IndoorMapFeature.State()
            initial.isActive = true
            initial.requiresStairConfirmation = true
            initial.routeRequestID = 1
            let store = TestStore(initialState: initial) { IndoorMapFeature() }
            await store.send(.sceneActiveChanged(false)) {
                $0.isActive = false
                $0.requiresStairConfirmation = false
                $0.routeRequestID = 2
            }
            await store.send(.useStairsTapped)
            await store.finish()
        }
    }
}
