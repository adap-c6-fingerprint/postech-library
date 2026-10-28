import Foundation

/// 계산된 경로의 표시 정보다. 최단경로·거리·통행 정책은 바꾸지 않는다.
nonisolated struct RoutePreviewGuidance: Equatable, Sendable {
    let walkingSeconds: Double
    let groupTransitionNodes: [RouteNode]

    var walkingMinutes: Double { walkingSeconds / 60 }
    var stepCount: Int { groupTransitionNodes.count + 1 }

    init(route: IndoorRoute, graph: RoutingGraph) throws {
        let seconds = route.distanceMeters * 3_600 / 5_000
        guard route.distanceMeters.isFinite, route.distanceMeters >= 0, seconds.isFinite,
              Set(graph.nodes.map(\.id)).count == graph.nodes.count,
              Set(graph.edges.map(\.id)).count == graph.edges.count else {
            throw IndoorRoutingError.invalidGraph
        }
        let nodes = Dictionary(uniqueKeysWithValues: graph.nodes.map { ($0.id, $0) })
        let edges = Dictionary(uniqueKeysWithValues: graph.edges.map { ($0.id, $0) })
        guard route.nodeIDs.allSatisfy({ nodes[$0] != nil }) else { throw IndoorRoutingError.invalidGraph }

        var current: String?
        let arrivals: [String]
        if route.nodeIDs.count == route.edgeIDs.count + 1 {
            current = route.nodeIDs.first
            arrivals = Array(route.nodeIDs.dropFirst())
        } else if !route.edgeIDs.isEmpty, route.nodeIDs.count == route.edgeIDs.count {
            // 기존 엔진은 통로 중간에 투영한 가상 출발 노드를 nodeIDs에서 제외한다.
            arrivals = route.nodeIDs
        } else {
            throw IndoorRoutingError.invalidGraph
        }

        var transitions: [RouteNode] = []
        var previous: RouteEdge?
        for (index, id) in route.edgeIDs.enumerated() {
            guard let edge = edges[id] else { throw IndoorRoutingError.invalidGraph }
            let arrival = arrivals[index]
            if let current {
                guard (edge.fromNodeID == current && edge.toNodeID == arrival)
                    || (edge.direction == .undirected && edge.toNodeID == current && edge.fromNodeID == arrival) else {
                    throw IndoorRoutingError.invalidGraph
                }
            } else {
                guard edge.toNodeID == arrival || (edge.direction == .undirected && edge.fromNodeID == arrival) else {
                    throw IndoorRoutingError.invalidGraph
                }
            }
            if let previous, previous.groupID != edge.groupID {
                guard let current, let node = nodes[current] else { throw IndoorRoutingError.invalidGraph }
                transitions.append(node)
            }
            previous = edge
            current = arrival
        }
        walkingSeconds = seconds
        groupTransitionNodes = transitions
    }
}
