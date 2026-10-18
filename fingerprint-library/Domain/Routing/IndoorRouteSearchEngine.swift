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
        for arc in path {
            guard let from = index.nodesByID[arc.fromNodeID], let to = index.nodesByID[arc.toNodeID] else { continue }
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
                changes.append(
                    .init(
                        edgeID: arc.edgeID, category: arc.category,
                        fromFloorID: from.floorID, toFloorID: to.floorID,
                        fromCoordinate: from.coordinate, toCoordinate: to.coordinate))
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
