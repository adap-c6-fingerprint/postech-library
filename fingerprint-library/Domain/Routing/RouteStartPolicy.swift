import Foundation

nonisolated enum LibraryZone: Equatable, Sendable {
    case inside, nearOutside, farOutside
}

nonisolated enum RouteStartDecision: Equatable, Sendable {
    case current(IndoorPosition)
    case entrance(IndoorPosition, EntranceReason)
    case locating
    case needsOrigin(Reason)

    enum EntranceReason: Equatable, Sendable {
        case outside
    }

    enum Reason: Equatable, Sendable {
        case notAuthorized, noPosition, unknownFloor, farOutside, noEntrance
    }

    var startPosition: IndoorPosition? {
        switch self {
        case let .current(position), let .entrance(position, _): position
        case .locating, .needsOrigin: nil
        }
    }

    var notice: String? {
        switch self {
        case .entrance(_, .outside):
            "점선을 따라 가까운 주출입구로 이동한 뒤 실내 경로를 이어가세요."
        case .needsOrigin(.unknownFloor):
            "현재 층을 확인하지 못했어요. 지도에서 출발 위치와 층을 직접 정해 주세요."
        case .locating:
            "현재 위치를 확인하고 있어요."
        case .needsOrigin(.noPosition):
            "현재 위치를 확인하지 못했어요. 출발 위치를 직접 정해 주세요."
        case .needsOrigin(.noEntrance):
            "출발 위치를 직접 정해 주세요."
        case .needsOrigin(.farOutside):
            "도서관에서 20m 넘게 떨어져 있어요. 출발 위치를 직접 정해 주세요."
        case .needsOrigin(.notAuthorized), .current: nil
        }
    }
}

nonisolated struct RouteStartPolicy: Sendable {
    var nearOutsideMeters = 20.0

    func decide(position: IndoorPosition?, isAuthorized: Bool, map: IndoorMap, now: Date) -> RouteStartDecision {
        guard isAuthorized else { return .needsOrigin(.notAuthorized) }
        guard let position, position.isRecent(at: now) else { return .locating }
        // Maps without a ground footprint keep their existing routing behavior.
        guard let outline = map.groundFootprint else { return .current(position) }
        switch zone(of: position, outline: outline) {
        case .inside:
            if map.floors.contains(where: { $0.ordinal == position.floorOrdinal }) {
                return .current(position)
            }
            return .needsOrigin(.unknownFloor)
        case .nearOutside:
            return entranceDecision(near: position, in: map, reason: .outside)
        case .farOutside:
            return .needsOrigin(.farOutside)
        }
    }

    func zone(of position: IndoorPosition, outline: IndoorMapGeometry) -> LibraryZone {
        if outline.contains(position.coordinate) { return .inside }
        let distance = outline.distanceToBoundaryMeters(from: position.coordinate)
        // A floor reported outside the footprint belongs to an unknown building.
        return distance <= nearOutsideMeters ? .nearOutside : .farOutside
    }

    private func entranceDecision(
        near position: IndoorPosition, in map: IndoorMap, reason: RouteStartDecision.EntranceReason
    ) -> RouteStartDecision {
        guard let entrance = map.principalEntrances.min(by: {
            RoutingGeometry.distanceMeters(from: $0.coordinate, to: position.coordinate)
                < RoutingGeometry.distanceMeters(from: $1.coordinate, to: position.coordinate)
        }) else { return .needsOrigin(.noEntrance) }
        // This is a fixed route origin; the sensor position remains in shared location state.
        return .entrance(.init(coordinate: entrance.coordinate, floorOrdinal: entrance.floorOrdinal,
                               horizontalAccuracy: nil, timestamp: position.timestamp, source: .manual), reason)
    }
}

nonisolated struct LibraryEntranceApproach: Equatable, Sendable {
    let position: IndoorPosition
    let entrance: IndoorPosition

    init?(position: IndoorPosition, entrance: IndoorPosition, map: IndoorMap) {
        guard position.source == .sensor, position.coordinate.isValid,
              entrance.coordinate.isValid, entrance.floorOrdinal != nil,
              let outline = map.groundFootprint,
              RouteStartPolicy().zone(of: position, outline: outline) == .nearOutside else { return nil }
        self.position = position
        self.entrance = entrance
    }

    var coordinates: [IndoorMapCoordinate] { [position.coordinate, entrance.coordinate] }
}
