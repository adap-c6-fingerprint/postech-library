import Foundation

/// Fingerprint의 RouteGraph 계약을 바탕으로 지도 층 참조를 추가했다.
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
    /// 원본에 있을 때만 보존한다. 실제 거리나 ETA로 사용하지 않는다.
    let traversalSeconds: Double?
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
    /// 방향·접근성 조건을 적용하기 전의 약한 연결 요소다. 경로 존재 보장이 아니다.
    let connectedComponents: [[String]]
    /// 출입구 등 도면 외부 노드는 보존하되 진단한다.
    let outsideFloorNodeIDs: [String]
    /// 실제 이동거리 탐색을 하기 전에 별도 실측 자료가 필요한 연결이다.
    let crossFloorEdgeIDs: [String]
}
