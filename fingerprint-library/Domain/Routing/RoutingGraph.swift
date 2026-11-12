import Foundation

nonisolated struct RouteNode: Identifiable, Equatable, Sendable {
    let id: String
    let coordinate: IndoorMapCoordinate
    let level: Int
    let floorID: UUID
    let name: String?
    let category: String?
}

nonisolated enum RouteEdgeDirection: String, Decodable, Sendable {
    case directed, undirected
}

nonisolated enum RouteEdgeCategory: String, Decodable, Sendable {
    case walkway, stairs, escalator, elevator, ramp
    case platformLift = "platform_lift"
}

nonisolated struct RouteEdge: Identifiable, Equatable, Sendable {
    let id: String
    let fromNodeID: String
    let toNodeID: String
    let direction: RouteEdgeDirection
    let category: RouteEdgeCategory
    let accessible: Bool
    let coordinates: [IndoorMapCoordinate]
    let traversalSeconds: Double?
    var groupID: UUID? = nil
}

nonisolated struct RoutingGraph: Equatable, Sendable {
    let schemaVersion: Int
    let layoutVersion: String
    let hardSearchRadiusMeters: Double
    let nodes: [RouteNode]
    let edges: [RouteEdge]
}

nonisolated struct RoutingGraphDiagnostics: Equatable, Sendable {
    let isolatedNodeIDs: [String]
    let connectedComponents: [[String]]
    let outsideFloorNodeIDs: [String]
    let crossFloorEdgeIDs: [String]
}
