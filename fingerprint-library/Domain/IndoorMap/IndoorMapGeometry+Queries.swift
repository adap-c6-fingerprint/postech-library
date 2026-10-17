import Foundation

nonisolated extension IndoorMapCoordinate {
    var isValid: Bool {
        latitude.isFinite && longitude.isFinite
            && (-90...90).contains(latitude) && (-180...180).contains(longitude)
    }
}

nonisolated extension IndoorMapGeometry {
    var coordinates: [IndoorMapCoordinate] {
        switch self {
        case .point(let point): [point]
        case .lineString(let points): points
        case .polygon(let rings): rings.flatMap { $0 }
        case .multiPolygon(let polygons): polygons.flatMap { $0.flatMap { $0 } }
        }
    }

    /// 작은 WGS 84 실내 도형에 사용한다. 외곽 경계는 포함하고 내부 ring은 제외한다.
    func contains(_ point: IndoorMapCoordinate) -> Bool {
        switch self {
        case .polygon(let rings): Self.contains(point, rings: rings)
        case .multiPolygon(let polygons): polygons.contains { Self.contains(point, rings: $0) }
        default: false
        }
    }

    private static func contains(_ point: IndoorMapCoordinate, rings: [[IndoorMapCoordinate]]) -> Bool {
        guard let exterior = rings.first, ringContains(point, ring: exterior) else { return false }
        return !rings.dropFirst().contains { ringContains(point, ring: $0) }
    }

    private static func ringContains(_ point: IndoorMapCoordinate, ring: [IndoorMapCoordinate]) -> Bool {
        guard ring.count >= 4 else { return false }
        var inside = false
        for (a, b) in zip(ring, ring.dropFirst()) {
            let cross = (point.longitude - a.longitude) * (b.latitude - a.latitude)
                - (point.latitude - a.latitude) * (b.longitude - a.longitude)
            let onBounds = (min(a.longitude, b.longitude)...max(a.longitude, b.longitude)).contains(point.longitude)
                && (min(a.latitude, b.latitude)...max(a.latitude, b.latitude)).contains(point.latitude)
            if abs(cross) < 1e-14 && onBounds { return true }
            if (a.latitude > point.latitude) != (b.latitude > point.latitude) {
                let crossing = (b.longitude - a.longitude) * (point.latitude - a.latitude)
                    / (b.latitude - a.latitude) + a.longitude
                if point.longitude < crossing { inside.toggle() }
            }
        }
        return inside
    }
}
