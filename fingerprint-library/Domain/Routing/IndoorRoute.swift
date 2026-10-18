import Foundation

nonisolated struct RouteEdgeDistance: Equatable, Sendable {
    enum Source: String, Decodable, Sendable { case measured, estimated }
    let meters: Double
    let source: Source
}

nonisolated enum RoutePreference: String, CaseIterable, Equatable, Sendable {
    case shortestDistance, elevatorPreferred
}

nonisolated struct RoutePolylineSegment: Equatable, Sendable {
    let floorID: UUID
    let coordinates: [IndoorMapCoordinate]
}

nonisolated struct RouteFloorChange: Equatable, Sendable {
    let edgeID: String
    let category: RouteEdgeCategory
    let fromFloorID: UUID
    let toFloorID: UUID
    let fromCoordinate: IndoorMapCoordinate
    let toCoordinate: IndoorMapCoordinate
}

nonisolated struct RouteStartAttachment: Equatable, Sendable {
    let actualCoordinate: IndoorMapCoordinate
    let routeCoordinate: IndoorMapCoordinate
    let floorID: UUID
    /// 통로까지의 직선 간격이다. 보행 가능 경로나 경로의 이동거리에 합산하지 않는다.
    let distanceToGraphMeters: Double
}

nonisolated struct IndoorRoute: Equatable, Sendable {
    let destination: ShelfKey
    let nodeIDs: [String]
    let edgeIDs: [String]
    let segments: [RoutePolylineSegment]
    let floorChanges: [RouteFloorChange]
    let distanceMeters: Double
    let usesEstimatedDistances: Bool
    let start: RouteStartAttachment
    var isAlreadyAtDestination: Bool { edgeIDs.isEmpty }
}

nonisolated struct IndoorRouteRequest: Equatable, Sendable {
    let navigation: IndoorNavigationData
    let start: IndoorPosition
    let destination: ShelfKey
    let preference: RoutePreference
    var allowsStairFallback = false
}

nonisolated enum IndoorRouteSearchOutcome: Equatable, Sendable {
    case route(IndoorRoute)
    case requiresStairConfirmation
}

nonisolated enum IndoorRoutingError: Error, Equatable, Sendable, LocalizedError {
    case invalidGraph, invalidDestination, unknownFloor, invalidPosition, farFromGraph
    case missingTransitionDistances, noRoute

    var errorDescription: String? {
        switch self {
        case .invalidGraph: "길찾기 데이터가 올바르지 않아요. 도면과 노드 데이터를 확인해주세요."
        case .invalidDestination: "이 서가의 도착 지점을 찾을 수 없어요."
        case .unknownFloor: "현재 층을 확인할 수 없어요. 시뮬레이터의 층을 확인해주세요."
        case .invalidPosition: "현재 위치를 확인한 뒤 다시 시도해주세요."
        case .farFromGraph: "현재 위치가 등록된 통로에서 너무 멀어요. 통로로 이동한 뒤 다시 시도해주세요."
        case .missingTransitionDistances: "층간 이동거리 자료가 필요해요."
        case .noRoute: "선택한 서가까지 연결된 경로가 없어요."
        }
    }
}
