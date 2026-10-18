import Foundation

nonisolated struct ResolvedRouteStart: Sendable {
    let nodeID: String
    let attachment: RouteStartAttachment
}

nonisolated enum RouteStartResolver {
    static func resolve(_ position: IndoorPosition, in index: inout RoutingGraphIndex) throws -> ResolvedRouteStart {
        guard position.coordinate.isValid, let accuracy = position.horizontalAccuracy,
            accuracy.isFinite, accuracy >= 0
        else { throw IndoorRoutingError.invalidPosition }
        guard let level = position.floorOrdinal else { throw IndoorRoutingError.unknownFloor }
        let nodes = index.graph.nodes.filter { $0.level == level }.sorted { $0.id < $1.id }
        guard let floorID = nodes.first?.floorID else { throw IndoorRoutingError.unknownFloor }
        guard accuracy <= index.graph.hardSearchRadiusMeters else { throw IndoorRoutingError.invalidPosition }
        if let exact = nodes.first(where: {
            RoutingGeometry.distanceMeters(from: $0.coordinate, to: position.coordinate) < 0.000_001
        }) {
            return .init(
                nodeID: exact.id,
                attachment: .init(
                    actualCoordinate: position.coordinate,
                    routeCoordinate: exact.coordinate, floorID: floorID, distanceToGraphMeters: 0))
        }
        struct Candidate {
            let edge: RouteEdge
            let point: IndoorMapCoordinate
            let segment: Int
            let distance: Double
        }
        var closest: Candidate?
        for edge in index.graph.edges.sorted(by: { $0.id < $1.id }) {
            try Task.checkCancellation()
            guard let from = index.nodesByID[edge.fromNodeID], let to = index.nodesByID[edge.toNodeID],
                from.level == level, to.level == level
            else { continue }
            for offset in 0..<(edge.coordinates.count - 1) {
                try Task.checkCancellation()
                let point = projected(
                    position.coordinate, from: edge.coordinates[offset], to: edge.coordinates[offset + 1])
                let distance = RoutingGeometry.distanceMeters(from: position.coordinate, to: point)
                if closest == nil || distance < closest!.distance {
                    closest = Candidate(edge: edge, point: point, segment: offset, distance: distance)
                }
            }
        }
        guard let closest, closest.distance <= index.graph.hardSearchRadiusMeters else {
            throw IndoorRoutingError.farFromGraph
        }
        let edge = closest.edge
        let attachment = RouteStartAttachment(
            actualCoordinate: position.coordinate,
            routeCoordinate: closest.point, floorID: floorID, distanceToGraphMeters: closest.distance)
        for id in [edge.fromNodeID, edge.toNodeID] {
            if let node = index.nodesByID[id],
                RoutingGeometry.distanceMeters(from: node.coordinate, to: closest.point) < 0.000_001
            {
                return .init(nodeID: id, attachment: attachment)
            }
        }
        var virtualID = "__route_start__"
        while index.nodesByID[virtualID] != nil { virtualID += "_" }
        index.nodesByID[virtualID] = RouteNode(
            id: virtualID, coordinate: closest.point, level: level,
            floorID: floorID, name: nil, category: nil)
        let suffix = [closest.point] + edge.coordinates.dropFirst(closest.segment + 1)
        var arcs = [
            RouteTraversal(
                edgeID: edge.id, fromNodeID: virtualID, toNodeID: edge.toNodeID,
                category: edge.category, coordinates: suffix,
                distanceMeters: RoutingGeometry.polylineLengthMeters(suffix), isEstimated: false)
        ]
        if edge.direction == .undirected {
            let prefix = Array((Array(edge.coordinates.prefix(closest.segment + 1)) + [closest.point]).reversed())
            arcs.append(
                .init(
                    edgeID: edge.id, fromNodeID: virtualID, toNodeID: edge.fromNodeID,
                    category: edge.category, coordinates: prefix,
                    distanceMeters: RoutingGeometry.polylineLengthMeters(prefix), isEstimated: false))
        }
        index.outgoing[virtualID] = arcs
        return .init(nodeID: virtualID, attachment: attachment)
    }

    private static func projected(
        _ point: IndoorMapCoordinate, from a: IndoorMapCoordinate,
        to b: IndoorMapCoordinate
    ) -> IndoorMapCoordinate {
        let scale = cos((a.latitude + b.latitude + point.latitude) / 3 * .pi / 180)
        let x = (b.longitude - a.longitude) * scale
        let y = b.latitude - a.latitude
        let length = x * x + y * y
        guard length > 0 else { return a }
        let fraction = min(
            1, max(0, ((point.longitude - a.longitude) * scale * x + (point.latitude - a.latitude) * y) / length))
        return .init(
            latitude: a.latitude + fraction * y, longitude: a.longitude + fraction * (b.longitude - a.longitude))
    }
}
