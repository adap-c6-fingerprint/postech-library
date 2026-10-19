import Foundation

nonisolated struct RouteTraversal: Equatable, Sendable {
    let edgeID: String
    let fromNodeID: String
    let toNodeID: String
    let category: RouteEdgeCategory
    let coordinates: [IndoorMapCoordinate]
    let distanceMeters: Double
    let isEstimated: Bool
}

/// Fingerprint의 방향별 adjacency 구성을 이식했다. 비용 단위는 미터로 통일한다.
nonisolated struct RoutingGraphIndex: Sendable {
    let graph: RoutingGraph
    var nodesByID: [String: RouteNode]
    var outgoing: [String: [RouteTraversal]]

    init(graph: RoutingGraph, transitionDistances: [String: RouteEdgeDistance]) throws {
        let ids = graph.nodes.map(\.id) + graph.edges.map(\.id)
        guard graph.schemaVersion == 1, !graph.nodes.isEmpty,
            !graph.layoutVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            graph.hardSearchRadiusMeters.isFinite, graph.hardSearchRadiusMeters > 0,
            ids.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }),
            Set(ids).count == ids.count,
            graph.nodes.allSatisfy({ $0.coordinate.isValid })
        else { throw IndoorRoutingError.invalidGraph }
        self.graph = graph
        nodesByID = Dictionary(uniqueKeysWithValues: graph.nodes.map { ($0.id, $0) })
        outgoing = [:]
        var crossFloorIDs = Set<String>()
        for edge in graph.edges.sorted(by: { $0.id < $1.id }) {
            try Task.checkCancellation()
            guard let from = nodesByID[edge.fromNodeID], let to = nodesByID[edge.toNodeID], from.id != to.id,
                edge.coordinates.count >= 2, edge.coordinates.allSatisfy(\.isValid),
                edge.coordinates.first == from.coordinate, edge.coordinates.last == to.coordinate,
                !(edge.accessible && [.stairs, .escalator].contains(edge.category)),
                edge.traversalSeconds.map({ $0.isFinite && $0 > 0 }) ?? true
            else {
                throw IndoorRoutingError.invalidGraph
            }
            let distance: Double
            let estimated: Bool
            if from.floorID == to.floorID {
                guard from.level == to.level, edge.traversalSeconds == nil else {
                    throw IndoorRoutingError.invalidGraph
                }
                distance = RoutingGeometry.polylineLengthMeters(edge.coordinates)
                estimated = false
            } else {
                guard from.level != to.level, edge.category != .walkway else { throw IndoorRoutingError.invalidGraph }
                crossFloorIDs.insert(edge.id)
                guard let measurement = transitionDistances[edge.id] else {
                    throw IndoorRoutingError.missingTransitionDistances
                }
                distance = measurement.meters
                estimated = measurement.source == .estimated
                // A*의 수평 직선거리 heuristic이 하한이 되도록 한다.
                guard distance >= RoutingGeometry.distanceMeters(from: from.coordinate, to: to.coordinate) else {
                    throw IndoorRoutingError.invalidGraph
                }
            }
            guard distance.isFinite, distance > 0 else { throw IndoorRoutingError.invalidGraph }
            outgoing[from.id, default: []].append(
                .init(
                    edgeID: edge.id, fromNodeID: from.id, toNodeID: to.id,
                    category: edge.category, coordinates: edge.coordinates, distanceMeters: distance,
                    isEstimated: estimated))
            if edge.direction == .undirected {
                outgoing[to.id, default: []].append(
                    .init(
                        edgeID: edge.id, fromNodeID: to.id, toNodeID: from.id,
                        category: edge.category, coordinates: Array(edge.coordinates.reversed()),
                        distanceMeters: distance, isEstimated: estimated))
            }
        }
        guard Set(transitionDistances.keys).isSubset(of: crossFloorIDs) else { throw IndoorRoutingError.invalidGraph }
    }
}
