import Foundation
import Testing

@testable import fingerprint_library

@MainActor
struct RoutePreviewGuidanceTests {
    private typealias F = IndoorRoutingTestFactory
    private static let a = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!
    private static let b = UUID(uuidString: "00000000-0000-4000-8000-000000000002")!
    enum Pattern: CaseIterable { case unassigned, same, once, returns, assignmentChanges }

    @Test("연속 엣지의 그룹 전환 횟수 + 1이며 같은 그룹 재진입도 다시 센다", arguments: Pattern.allCases)
    func countsGroupRuns(_ pattern: Pattern) throws {
        let (groups, expected): ([UUID?], [String]) = switch pattern {
        case .unassigned: ([nil, nil, nil], [])
        case .same: ([Self.a, Self.a, Self.a], [])
        case .once: ([Self.a, Self.b, Self.b], ["b"])
        case .returns: ([Self.a, Self.b, Self.a], ["b", "c"])
        case .assignmentChanges: ([nil, Self.a, nil], ["b", "c"])
        }
        let graph = graph(groups)
        let route = try route(graph)
        let guidance = try RoutePreviewGuidance(route: route, graph: graph)
        #expect(guidance.stepCount == expected.count + 1)
        #expect(guidance.groupTransitionNodes.map(\.id) == expected)
        #expect(guidance.groupTransitionNodes.allSatisfy { node in
            graph.nodes.contains(node) && route.nodeIDs.contains(node.id)
        })
        // 그룹 메타데이터 유무는 탐색 결과·비용을 바꾸지 않는다.
        let original = try self.route(self.graph([nil, nil, nil]))
        #expect(route.nodeIDs == original.nodeIDs)
        #expect(route.edgeIDs == original.edgeIDs)
        #expect(route.distanceMeters == original.distanceMeters)
    }

    @Test("시속 5km는 10m당 7.2초다", arguments: [0.0, 10, 100, 5_000])
    func walkingTime(_ meters: Double) throws {
        let graph = graph([Self.a, Self.a, Self.a])
        let result = try replacingDistance(meters, in: route(graph))
        let guidance = try RoutePreviewGuidance(route: result, graph: graph)
        #expect(abs(guidance.walkingSeconds - meters * 0.72) < 0.000_001)
        #expect(abs(guidance.walkingMinutes - meters * 0.012) < 0.000_001)
    }

    @Test("역방향 이동에서도 실제 두 엣지가 만나는 노드를 표시한다")
    func reversePath() throws {
        let graph = graph([Self.a, Self.a, Self.b])
        let result = try route(graph, reverse: true)
        let guidance = try RoutePreviewGuidance(route: result, graph: graph)
        #expect(result.nodeIDs == ["d", "c", "b", "a"])
        #expect(guidance.groupTransitionNodes.map(\.id) == ["c"])
        #expect(guidance.stepCount == 2)
    }

    @Test("통로 중간의 가상 출발점은 가짜 단계를 추가하지 않는다")
    func projectedStart() throws {
        let graph = graph([Self.a, Self.b, Self.b])
        let result = try route(graph, projected: true)
        #expect(result.nodeIDs.count == result.edgeIDs.count)
        let guidance = try RoutePreviewGuidance(route: result, graph: graph)
        #expect(guidance.groupTransitionNodes.map(\.id) == ["b"])
        #expect(guidance.stepCount == 2)
    }

    @Test("출발 노드가 도착이면 0초·전환 없는 1단계다")
    func alreadyAtDestination() throws {
        let graph = graph([Self.a, Self.b, Self.a])
        let request = F.request(graph: graph, start: graph.nodes[0].coordinate, target: "a")
        guard case .route(let result) = try IndoorRouteSearchEngine().search(request) else {
            throw IndoorRoutingError.noRoute
        }
        let guidance = try RoutePreviewGuidance(route: result, graph: graph)
        #expect(guidance.walkingSeconds == 0)
        #expect(guidance.groupTransitionNodes.isEmpty)
        #expect(guidance.stepCount == 1)
    }

    @Test("잘못된 시간과 경로에 없는 엣지는 정상 안내로 표시하지 않는다")
    func rejectsInvalidInputs() throws {
        let graph = graph([Self.a, Self.b, Self.a])
        let result = try route(graph)
        for distance in [-1, Double.nan, .infinity, .greatestFiniteMagnitude] {
            #expect(throws: IndoorRoutingError.invalidGraph) {
                try RoutePreviewGuidance(route: replacingDistance(distance, in: result), graph: graph)
            }
        }
        let missing = F.graph(graph.nodes, Array(graph.edges.dropFirst()))
        #expect(throws: IndoorRoutingError.invalidGraph) { try RoutePreviewGuidance(route: result, graph: missing) }
        let duplicate = F.graph(graph.nodes + [graph.nodes[0]], graph.edges)
        #expect(throws: IndoorRoutingError.invalidGraph) { try RoutePreviewGuidance(route: result, graph: duplicate) }
    }

    private func graph(_ groups: [UUID?]) -> RoutingGraph {
        let nodes = (0..<4).map { F.node(String(UnicodeScalar(97 + $0)!), x: Double($0) * 10) }
        let edges = (0..<3).map { index in
            var edge = F.edge("e\(index)", nodes[index], nodes[index + 1])
            edge.groupID = groups[index]
            return edge
        }
        return F.graph(nodes, edges)
    }

    private func route(_ graph: RoutingGraph, reverse: Bool = false, projected: Bool = false) throws -> IndoorRoute {
        let start = projected ? F.node("projection", x: 5).coordinate : graph.nodes[reverse ? 3 : 0].coordinate
        let request = F.request(graph: graph, start: start, target: reverse ? "a" : "d")
        guard case .route(let route) = try IndoorRouteSearchEngine().search(request) else { throw IndoorRoutingError.noRoute }
        return route
    }

    private func replacingDistance(_ distance: Double, in route: IndoorRoute) -> IndoorRoute {
        .init(destination: route.destination, nodeIDs: route.nodeIDs, edgeIDs: route.edgeIDs, segments: route.segments,
              floorChanges: route.floorChanges, distanceMeters: distance, usesEstimatedDistances: route.usesEstimatedDistances,
              start: route.start)
    }
}
