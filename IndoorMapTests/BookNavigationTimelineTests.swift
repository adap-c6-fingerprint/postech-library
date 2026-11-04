import Foundation
import Testing
@testable import fingerprint_library

@MainActor
struct BookNavigationTimelineTests {
    private typealias N = IndoorRoutingTestFactory

    @Test("보행 40m·엘리베이터 20m·보행 40m를 정확히 4:2:4로 배치한다")
    func proportionalDistances() throws {
        let fixture = try makePlan()
        let timeline = BookNavigationTimeline(plans: [fixture.plan], bookCount: 1)
        #expect(timeline.hasCompleteDistances)
        #expect(timeline.segments.map(\.meters) == [40, 20, 40])
        #expect(timeline.segments.map { timeline.fraction(for: $0) } == [0.4, 0.2, 0.4])
        #expect(timeline.markers.map(\.fraction) == [0, 0.4, 0.6, 1])
        #expect(timeline.markers.map(\.kind) == [.walk, .elevator, .walk, .book])
        let progress = RouteGuidanceProgress(stepIndex: 1, fraction: 0.5, distanceAlongRoute: 50,
            coordinate: fixture.graph.nodes[1].coordinate, maneuver: .straight, distanceToManeuver: nil, remainingMeters: 50)
        #expect(timeline.completion(of: timeline.segments[0], stopIndex: 0, progress: progress) == 1)
        #expect(timeline.completion(of: timeline.segments[1], stopIndex: 0, progress: progress) == 0.5)
        #expect(timeline.completion(of: timeline.segments[2], stopIndex: 0, progress: progress) == 0)
    }

    @Test("여러 책의 경유지 숫자는 방문 순서와 누적 거리 위치를 사용한다")
    func waypoints() throws {
        let fixture = try makePlan()
        let timeline = BookNavigationTimeline(plans: [fixture.plan, fixture.plan], bookCount: 2)
        #expect(timeline.totalMeters == 200)
        let points = timeline.markers.filter { if case .waypoint = $0.kind { return true }; return false }
        #expect(points.map(\.kind) == [.waypoint(1), .waypoint(2)])
        #expect(points.map(\.fraction) == [0.5, 1])
        #expect(timeline.completion(of: timeline.segments[0], stopIndex: 1, progress: nil) == 1)
        #expect(timeline.completion(of: timeline.segments[3], stopIndex: 1, progress: nil) == 0)
    }

    @Test("탐색의 구간별 거리 합은 총 거리와 같고 층간 이동 거리도 보존한다")
    func enginePreservesDistances() throws {
        let fixture = try makePlan()
        let request = N.request(graph: fixture.graph, start: fixture.graph.nodes[0].coordinate,
            target: "d", distances: ["lift": .init(meters: 20, source: .measured)])
        guard case let .route(route) = try IndoorRouteSearchEngine().search(request) else {
            Issue.record("경로 탐색에 실패했습니다"); return
        }
        let distances = try #require(route.edgeDistancesMeters)
        #expect(distances.count == 3 && distances[1] == 20)
        #expect(distances.reduce(0, +) == route.distanceMeters)
        #expect(try RouteGuidancePlan(route: route, graph: fixture.graph).steps.map(\.meters) == distances.map(Optional.some))
    }

    @Test("계단 구간과 누락된 거리·잘못된 비용을 구분한다")
    func stairsAndInvalidDistances() throws {
        let fixture = try makePlan(category: .stairs)
        #expect(BookNavigationTimeline(plans: [fixture.plan], bookCount: 1).segments[1].kind == .stairs)
        #expect(!BookNavigationTimeline(plans: [nil], bookCount: 1).hasCompleteDistances)
        var route = fixture.route
        route.edgeDistancesMeters = [40, 10, 40]
        #expect(throws: RouteGuidanceError.invalidRoute) { try RouteGuidancePlan(route: route, graph: fixture.graph) }
    }

    @Test("같은 위치의 여러 책은 순번을 함께 표시하고 0m에서도 비율이 유효하다")
    func zeroDistanceWaypoints() throws {
        let fixture = try makePlan()
        let zero = NavigationGuidanceTestFixture.make(nodes: [fixture.graph.nodes[3]])
        let plan = try RouteGuidancePlan(route: zero.route, graph: zero.graph)
        let timeline = BookNavigationTimeline(plans: [fixture.plan, plan, plan], bookCount: 3)
        #expect(timeline.markers.last?.kind == .waypoints([1, 2, 3]))
        #expect(timeline.markers.last?.fraction == 1)
        let empty = BookNavigationTimeline(plans: [plan], bookCount: 1)
        #expect(empty.totalMeters == 0)
        #expect(empty.markers.allSatisfy { $0.fraction.isFinite })
    }

    func makePlan(category: RouteEdgeCategory = .elevator) throws -> (plan: RouteGuidancePlan, route: IndoorRoute, graph: RoutingGraph) {
        let a = N.node("a"), b = N.node("b", x: 40)
        let c = N.node("c", x: 40, level: 1), d = N.node("d", x: 80, level: 1)
        let graph = N.graph([a, b, c, d], [N.edge("walk1", a, b), N.edge("lift", b, c, category: category), N.edge("walk2", c, d)])
        let route = IndoorRoute(destination: .init(datasetID: "test", value: "d"), nodeIDs: ["a", "b", "c", "d"],
            edgeIDs: ["walk1", "lift", "walk2"], segments: [.init(floorID: a.floorID, coordinates: [a.coordinate, b.coordinate]),
                .init(floorID: c.floorID, coordinates: [c.coordinate, d.coordinate])],
            floorChanges: [.init(edgeIDs: ["lift"], category: category, fromFloorID: b.floorID, toFloorID: c.floorID,
                fromCoordinate: b.coordinate, toCoordinate: c.coordinate)], distanceMeters: 100, usesEstimatedDistances: false,
            start: .init(actualCoordinate: a.coordinate, routeCoordinate: a.coordinate, floorID: a.floorID, distanceToGraphMeters: 0),
            edgeDistancesMeters: [40, 20, 40])
        return (try RouteGuidancePlan(route: route, graph: graph), route, graph)
    }
}
