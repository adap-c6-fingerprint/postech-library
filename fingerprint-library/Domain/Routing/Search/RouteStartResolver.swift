import Foundation

nonisolated struct ResolvedRouteStart: Sendable {
    let nodeID: String
    let attachment: RouteStartAttachment
}

nonisolated enum RouteStartResolver {
    static let maximumFallbackMeters = 50.0

    static func resolve(_ position: IndoorPosition, in index: inout RoutingGraphIndex) throws -> ResolvedRouteStart {
        let reportedAccuracy = position.source == .manual ? 0 : position.horizontalAccuracy
        guard position.coordinate.isValid, let accuracy = reportedAccuracy,
            accuracy.isFinite, accuracy >= 0
        else { throw IndoorRoutingError.invalidPosition }
        guard let level = position.floorOrdinal else { throw IndoorRoutingError.unknownFloor }
        let nodes = index.graph.nodes.filter { $0.level == level }.sorted { $0.id < $1.id }
        guard let floorID = nodes.first?.floorID else { throw IndoorRoutingError.noRoutingDataForFloor }
        // Start at an existing node on the reported floor, never at a virtual point on an edge.
        return try nearestNode(to: position.coordinate, among: nodes, floorID: floorID, in: index)
    }

    private static func nearestNode(
        to coordinate: IndoorMapCoordinate, among nodes: [RouteNode], floorID: UUID, in index: RoutingGraphIndex
    ) throws -> ResolvedRouteStart {
        var best: (node: RouteNode, distance: Double)?
        for node in nodes where !(index.outgoing[node.id] ?? []).isEmpty {
            try Task.checkCancellation()
            let distance = RoutingGeometry.distanceMeters(from: node.coordinate, to: coordinate)
            if best == nil || distance < best!.distance { best = (node, distance) }
        }
        guard let best, best.distance <= maximumFallbackMeters else { throw IndoorRoutingError.farFromGraph }
        return .init(
            nodeID: best.node.id,
            attachment: .init(
                actualCoordinate: coordinate, routeCoordinate: best.node.coordinate,
                floorID: floorID, distanceToGraphMeters: best.distance))
    }

}
