import Foundation

nonisolated struct ResolvedRouteStart: Sendable {
    let nodeID: String
    let attachment: RouteStartAttachment
}

nonisolated enum RouteStartResolver {
    static func resolve(_ position: IndoorPosition, in index: inout RoutingGraphIndex) throws -> ResolvedRouteStart {
        let reportedAccuracy = position.source == .manual ? 0 : position.horizontalAccuracy
        guard position.coordinate.isValid, let accuracy = reportedAccuracy,
            accuracy.isFinite, accuracy >= 0
        else { throw IndoorRoutingError.invalidPosition }
        guard let level = position.floorOrdinal else { throw IndoorRoutingError.unknownFloor }
        let nodes = index.graph.nodes.filter { $0.level == level }.sorted { $0.id < $1.id }
        guard let floorID = nodes.first?.floorID else { throw IndoorRoutingError.noRoutingDataForFloor }
        // 위치가 25m 넘게 튀면 통로 위 투영을 믿을 수 없다. 블루닷에서 가장 가까운 노드부터 안내한다.
        guard accuracy <= index.graph.hardSearchRadiusMeters else {
            return try nearestNode(to: position.coordinate, among: nodes, floorID: floorID, in: index)
        }
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
            // 통로에서 25m 넘게 떨어져 있어도 실패하지 않고 가장 가까운 노드부터 안내한다.
            return try nearestNode(to: position.coordinate, among: nodes, floorID: floorID, in: index)
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

    /// 같은 층에서 블루닷과 가장 가까운, 다른 노드로 이어지는 노드를 출발점으로 삼는다.
    /// 거리가 같으면 노드 ID 순서로 골라 결과가 매번 같게 한다.
    private static func nearestNode(
        to coordinate: IndoorMapCoordinate, among nodes: [RouteNode], floorID: UUID, in index: RoutingGraphIndex
    ) throws -> ResolvedRouteStart {
        var best: (node: RouteNode, distance: Double)?
        for node in nodes where !(index.outgoing[node.id] ?? []).isEmpty {
            try Task.checkCancellation()
            let distance = RoutingGeometry.distanceMeters(from: node.coordinate, to: coordinate)
            if best == nil || distance < best!.distance { best = (node, distance) }
        }
        guard let best else { throw IndoorRoutingError.farFromGraph }
        return .init(
            nodeID: best.node.id,
            attachment: .init(
                actualCoordinate: coordinate, routeCoordinate: best.node.coordinate,
                floorID: floorID, distanceToGraphMeters: best.distance))
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
