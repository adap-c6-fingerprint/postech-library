import Foundation

@testable import fingerprint_library

enum IndoorRoutingTestFactory {
    static let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
    static func node(_ id: String, x: Double = 0, y: Double = 0, level: Int = 0) -> RouteNode {
        RouteNode(
            id: id,
            coordinate: .init(
                latitude: 36 + y / 111_195,
                longitude: 129 + x / (111_195 * cos(36 * .pi / 180))), level: level,
            floorID: UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", level + 10))!, name: id,
            category: nil)
    }
    static func edge(
        _ id: String, _ from: RouteNode, _ to: RouteNode,
        direction: RouteEdgeDirection = .undirected, category: RouteEdgeCategory = .walkway,
        coordinates: [IndoorMapCoordinate]? = nil
    ) -> RouteEdge {
        .init(
            id: id, fromNodeID: from.id, toNodeID: to.id, direction: direction, category: category,
            accessible: category != .stairs && category != .escalator,
            coordinates: coordinates ?? [from.coordinate, to.coordinate], traversalSeconds: nil)
    }
    static func graph(_ nodes: [RouteNode], _ edges: [RouteEdge]) -> RoutingGraph {
        .init(schemaVersion: 1, layoutVersion: "route-test", hardSearchRadiusMeters: 25, nodes: nodes, edges: edges)
    }
    static func request(
        graph: RoutingGraph, start: IndoorMapCoordinate, level: Int = 0, target: String,
        distances: [String: RouteEdgeDistance] = [:], preference: RoutePreference = .shortestDistance
    ) -> IndoorRouteRequest {
        let node = graph.nodes.first { $0.id == target }!
        let key = ShelfKey(datasetID: "route-test", value: "shelf")
        let shelf = ShelfDestination(
            key: key, name: "가상 서가", floorID: node.floorID,
            mapElementID: .init(kind: .unit, sourceID: UUID()), geometry: .point(node.coordinate),
            arrivalNodeID: node.id, arrivalCoordinate: node.coordinate)
        let data = IndoorNavigationData(
            graph: graph,
            shelves: .init(datasetID: key.datasetID, mode: .mock, destinations: [shelf]),
            diagnostics: .init(
                isolatedNodeIDs: [], connectedComponents: [], outsideFloorNodeIDs: [], crossFloorEdgeIDs: []),
            transitionDistances: distances)
        return .init(
            navigation: data,
            start: .init(
                coordinate: start, floorOrdinal: level, horizontalAccuracy: 0, timestamp: now, source: .simulation),
            destination: key, preference: preference)
    }
}
