import Foundation
import Testing

@testable import fingerprint_library

struct IndoorRouteSearchTests {
    private typealias F = IndoorRoutingTestFactory

    @Test("A*를 독립적인 O(V²) Dijkstra와 모든 노드 쌍·계단 정책에서 비교한다")
    func matchesIndependentOracle() throws {
        let a = F.node("a")
        let b = F.node("b", x: 20)
        let c = F.node("c", y: 20)
        let d = F.node("d", x: 20, level: 1)
        let e = F.node("e", y: 20, level: 1)
        let isolated = F.node("isolated", x: 100)
        let graph = F.graph(
            [a, b, c, d, e, isolated],
            [
                F.edge("ab", a, b), F.edge("ac", a, c, direction: .directed),
                F.edge("bd", b, d, category: .stairs), F.edge("ce", c, e, category: .elevator), F.edge("de", d, e),
            ])
        let index = try RoutingGraphIndex(
            graph: graph,
            transitionDistances: [
                "bd": .init(meters: 10, source: .estimated), "ce": .init(meters: 20, source: .measured),
            ])
        for excludesStairs in [false, true] {
            for start in graph.nodes {
                for target in graph.nodes {
                    let actual = try AStarSearcher(index: index).search(
                        from: start.id, to: target.id, excludingStairs: excludesStairs)
                    let expected = oracle(index, from: start.id, to: target.id, excludingStairs: excludesStairs)
                    #expect((actual == nil) == (expected == nil))
                    if let actual, let expected {
                        #expect(abs(actual.reduce(0) { $0 + $1.distanceMeters } - expected) < 0.000_001)
                    }
                }
            }
        }
    }

    @Test("직선이 짧아 보여도 실제 polyline이 긴 경로를 피한다")
    func usesFullGeometry() throws {
        let a = F.node("a")
        let b = F.node("b", x: 10)
        let c = F.node("c", y: 10)
        let d = F.node("d", x: 10, y: 10)
        let graph = F.graph(
            [a, b, c, d],
            [
                F.edge("ab", a, b),
                F.edge(
                    "bd", b, d, coordinates: [b.coordinate, F.node("detour", x: 100, y: 100).coordinate, d.coordinate]),
                F.edge("ac", a, c), F.edge("cd", c, d),
            ])
        let route = try route(F.request(graph: graph, start: a.coordinate, target: d.id))
        #expect(route.edgeIDs == ["ac", "cd"])
        #expect(abs(route.distanceMeters - 20) < 0.1)
    }

    @Test("긴 단방향 간선 중간에서 목적지 방향의 남은 구간만 사용한다")
    func attachesToDirectedEdge() throws {
        let a = F.node("a")
        let b = F.node("b", x: 100)
        let point = F.node("point", x: 25).coordinate
        let graph = F.graph([a, b], [F.edge("ab", a, b, direction: .directed)])
        let forward = try route(F.request(graph: graph, start: point, target: b.id))
        #expect(abs(forward.distanceMeters - 75) < 0.1)
        #expect(forward.segments.first?.coordinates.first == point)
        #expect(forward.start.actualCoordinate == point)
        #expect(throws: IndoorRoutingError.noRoute) {
            try IndoorRouteSearchEngine().search(F.request(graph: graph, start: point, target: a.id))
        }
    }

    @Test("양방향 간선의 역방향 좌표 순서와 꺾인 polyline의 부분 길이를 유지한다")
    func preservesReverseAndPartialGeometry() throws {
        let a = F.node("a")
        let b = F.node("b", x: 100, y: 100)
        let corner = F.node("corner", y: 100).coordinate
        let graph = F.graph([a, b], [F.edge("ab", a, b, coordinates: [a.coordinate, corner, b.coordinate])])
        let reverse = try route(F.request(graph: graph, start: b.coordinate, target: a.id))
        #expect(reverse.segments.first?.coordinates == [b.coordinate, corner, a.coordinate])
        let partial = try route(F.request(graph: graph, start: F.node("mid", y: 50).coordinate, target: b.id))
        #expect(abs(partial.distanceMeters - 150) < 0.1)
    }

    @Test("계단 회피를 먼저 적용하고 불가능할 때만 명시적 계단 확인을 요청한다")
    func stairFallbackIsExplicit() throws {
        let a = F.node("a")
        let b = F.node("b", level: 1)
        let graph = F.graph([a, b], [F.edge("stairs", a, b, category: .stairs)])
        var request = F.request(
            graph: graph, start: a.coordinate, target: b.id,
            distances: ["stairs": .init(meters: 10, source: .estimated)], preference: .elevatorPreferred)
        #expect(try IndoorRouteSearchEngine().search(request) == .requiresStairConfirmation)
        request.allowsStairFallback = true
        let route = try route(request)
        #expect(route.floorChanges.count == 1)
        #expect(route.segments.isEmpty)
        #expect(route.distanceMeters == 10)
        #expect(route.usesEstimatedDistances)
    }

    @Test("엘리베이터 우선은 임의 가산점 없이 계단 제외 경로의 실제 거리 합을 쓴다")
    func prefersElevatorByFiltering() throws {
        let a = F.node("a")
        let b = F.node("b", level: 1)
        let graph = F.graph(
            [a, b], [F.edge("stairs", a, b, category: .stairs), F.edge("lift", a, b, category: .elevator)])
        let distances: [String: RouteEdgeDistance] = [
            "stairs": .init(meters: 8, source: .measured), "lift": .init(meters: 12, source: .measured),
        ]
        #expect(
            try route(F.request(graph: graph, start: a.coordinate, target: b.id, distances: distances)).edgeIDs == [
                "stairs"
            ])
        let preferred = try route(
            F.request(
                graph: graph, start: a.coordinate, target: b.id, distances: distances, preference: .elevatorPreferred))
        #expect(preferred.edgeIDs == ["lift"])
        #expect(preferred.distanceMeters == 12)
        #expect(!preferred.usesEstimatedDistances)
    }

    @Test("시작=도착은 성공하며 단절·원거리·층 누락·잘못된 거리 자료는 구분한다")
    func handlesBoundaryCases() throws {
        let a = F.node("a")
        let b = F.node("b", x: 100)
        let disconnected = F.graph([a, b], [])
        let same = try route(F.request(graph: disconnected, start: a.coordinate, target: a.id))
        #expect(same.isAlreadyAtDestination)
        #expect(same.distanceMeters == 0)
        #expect(throws: IndoorRoutingError.noRoute) {
            try IndoorRouteSearchEngine().search(F.request(graph: disconnected, start: a.coordinate, target: b.id))
        }
        let graph = F.graph([a, b], [F.edge("ab", a, b)])
        #expect(throws: IndoorRoutingError.farFromGraph) {
            try IndoorRouteSearchEngine().search(
                F.request(graph: graph, start: F.node("far", y: 100).coordinate, target: b.id))
        }
        #expect(throws: IndoorRoutingError.unknownFloor) {
            try IndoorRouteSearchEngine().search(F.request(graph: graph, start: a.coordinate, level: 99, target: b.id))
        }
        let upper = F.node("upper", level: 1)
        let stairs = F.graph([a, upper], [F.edge("stairs", a, upper, category: .stairs)])
        #expect(throws: IndoorRoutingError.missingTransitionDistances) {
            try route(F.request(graph: stairs, start: a.coordinate, target: upper.id))
        }
        #expect(throws: IndoorRoutingError.invalidGraph) {
            try route(
                F.request(
                    graph: stairs, start: a.coordinate, target: upper.id,
                    distances: ["stairs": .init(meters: -1, source: .estimated)]))
        }
    }

    @Test("이미 취소된 계산은 결과를 만들지 않는다")
    func cooperatesWithCancellation() async throws {
        let a = F.node("a")
        let b = F.node("b", x: 100)
        let request = F.request(graph: F.graph([a, b], [F.edge("ab", a, b)]), start: a.coordinate, target: b.id)
        let (stream, continuation) = AsyncStream<Void>.makeStream()
        let task = Task {
            for await _ in stream { break }
            return try IndoorRouteSearchEngine().search(request)
        }
        task.cancel()
        continuation.finish()
        do {
            _ = try await task.value
            Issue.record("취소된 탐색이 성공했습니다.")
        } catch is CancellationError {}
    }

    @Test("실제 C5의 동일 층·층간 가상 서가 경로와 추정값 표시를 검증한다")
    func routesBundledC5() async throws {
        let map = try await BundledIndoorMapLoader().loadC5()
        let data = try await BundledIndoorNavigationLoader().loadC5(on: map)
        #expect(data.transitionDistances.count == 5)
        for shelf in data.shelves.destinations {
            let target = try #require(data.graph.nodes.first { $0.id == shelf.arrivalNodeID })
            let origin = try #require(data.graph.nodes.first { $0.level == target.level && $0.id != target.id })
            let request = IndoorRouteRequest(
                navigation: data,
                start: .init(
                    coordinate: origin.coordinate, floorOrdinal: origin.level,
                    horizontalAccuracy: 0, timestamp: Date(), source: .simulation), destination: shelf.key,
                preference: .shortestDistance)
            let local = try route(request)
            #expect(local.nodeIDs.last == target.id)
            let other = try #require(data.graph.nodes.first { $0.level != target.level })
            let across = try route(
                .init(
                    navigation: data,
                    start: .init(
                        coordinate: other.coordinate, floorOrdinal: other.level,
                        horizontalAccuracy: 0, timestamp: Date(), source: .simulation), destination: shelf.key,
                    preference: .shortestDistance))
            #expect(!across.floorChanges.isEmpty)
            #expect(across.usesEstimatedDistances)
        }
    }

    private func route(_ request: IndoorRouteRequest) throws -> IndoorRoute {
        guard case .route(let route) = try IndoorRouteSearchEngine().search(request) else {
            throw IndoorRoutingError.noRoute
        }
        return route
    }
    /// Heap·A*의 방문 순서·predecessor 구현을 공유하지 않는 기준 탐색기.
    private func oracle(_ index: RoutingGraphIndex, from start: String, to target: String, excludingStairs: Bool)
        -> Double?
    {
        var remaining = Set(index.nodesByID.keys)
        var costs = [start: 0.0]
        while let current = remaining.min(by: { costs[$0, default: .infinity] < costs[$1, default: .infinity] }) {
            guard let cost = costs[current] else { return nil }
            if current == target { return cost }
            remaining.remove(current)
            for edge in index.outgoing[current, default: []] where remaining.contains(edge.toNodeID) {
                if excludingStairs && edge.category == .stairs { continue }
                costs[edge.toNodeID] = min(costs[edge.toNodeID, default: .infinity], cost + edge.distanceMeters)
            }
        }
        return nil
    }
}
