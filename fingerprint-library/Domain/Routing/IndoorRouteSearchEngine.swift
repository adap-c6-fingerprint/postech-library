import Foundation

nonisolated struct IndoorRouteSearchEngine: Sendable {
    func search(_ request: IndoorRouteRequest) throws -> IndoorRouteSearchOutcome {
        try Task.checkCancellation()
        let data = request.navigation
        guard let destination = try? data.shelves.destination(for: request.destination) else {
            throw IndoorRoutingError.invalidDestination
        }
        var index = try RoutingGraphIndex(graph: data.graph, transitionDistances: data.transitionDistances)
        guard let target = index.nodesByID[destination.arrivalNodeID],
            target.floorID == destination.floorID, target.coordinate == destination.arrivalCoordinate
        else {
            throw IndoorRoutingError.invalidDestination
        }
        let start = try RouteStartResolver.resolve(request.start, in: &index)
        let searcher = AStarSearcher(index: index)
        let avoidsStairs = request.preference == .elevatorPreferred && !request.allowsStairFallback
        if let path = try searcher.search(from: start.nodeID, to: target.id, excludingStairs: avoidsStairs) {
            return .route(result(path, start: start, destination: destination, index: index))
        }
        if avoidsStairs,
            try searcher.search(from: start.nodeID, to: target.id, excludingStairs: false) != nil
        {
            return .requiresStairConfirmation
        }
        throw IndoorRoutingError.noRoute
    }

    private func result(
        _ path: [RouteTraversal], start: ResolvedRouteStart,
        destination: ShelfDestination, index: RoutingGraphIndex
    ) -> IndoorRoute {
        var segments: [RoutePolylineSegment] = []
        var changes: [RouteFloorChange] = []
        var previousArc: RouteTraversal?
        for arc in path {
            guard let from = index.nodesByID[arc.fromNodeID], let to = index.nodesByID[arc.toNodeID] else { continue }
            defer { previousArc = arc }
            if from.floorID == to.floorID {
                if let last = segments.last, last.floorID == from.floorID,
                    last.coordinates.last == arc.coordinates.first
                {
                    segments[segments.count - 1] = .init(
                        floorID: from.floorID,
                        coordinates: last.coordinates + arc.coordinates.dropFirst())
                } else {
                    segments.append(.init(floorID: from.floorID, coordinates: arc.coordinates))
                }
            } else {
                // 같은 graph node에서 같은 방향으로 이어지는 엘리베이터는 내리지 않는 탑승이다.
                // 도보 간선이 끼거나 이동 방향이 바뀌면 별도 이동으로 남긴다.
                if arc.category == .elevator, let previousArc, previousArc.category == .elevator,
                    previousArc.toNodeID == from.id,
                    let previousFrom = index.nodesByID[previousArc.fromNodeID], previousFrom.level != from.level,
                    (from.level > previousFrom.level) == (to.level > from.level),
                    let last = changes.last, last.toFloorID == from.floorID {
                    changes[changes.count - 1] = .init(
                        edgeIDs: last.edgeIDs + [arc.edgeID], category: .elevator,
                        fromFloorID: last.fromFloorID, toFloorID: to.floorID,
                        fromCoordinate: last.fromCoordinate, toCoordinate: to.coordinate)
                } else {
                    changes.append(.init(
                        edgeIDs: [arc.edgeID], category: arc.category,
                        fromFloorID: from.floorID, toFloorID: to.floorID,
                        fromCoordinate: from.coordinate, toCoordinate: to.coordinate))
                }
            }
        }
        let realIDs = Set(index.graph.nodes.map(\.id))
        let nodeIDs = ([start.nodeID] + path.map(\.toNodeID)).filter { realIDs.contains($0) }
        return IndoorRoute(
            destination: destination.key, nodeIDs: nodeIDs, edgeIDs: path.map(\.edgeID),
            segments: segments, floorChanges: changes, distanceMeters: path.reduce(0) { $0 + $1.distanceMeters },
            usesEstimatedDistances: path.contains(where: \.isEstimated), start: start.attachment)
    }
}
