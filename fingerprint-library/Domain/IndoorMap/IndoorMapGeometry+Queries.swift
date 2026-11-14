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

    func contains(_ point: IndoorMapCoordinate) -> Bool {
        switch self {
        case .polygon(let rings): Self.contains(point, rings: rings)
        case .multiPolygon(let polygons): polygons.contains { Self.contains(point, rings: $0) }
        default: false
        }
    }

    /// Building-scale planar distance to polygon edges, including interior rings.
    func distanceToBoundaryMeters(from point: IndoorMapCoordinate) -> Double {
        let rings: [[IndoorMapCoordinate]] = switch self {
        case let .polygon(rings): rings
        case let .multiPolygon(polygons): polygons.flatMap { $0 }
        case .point, .lineString: []
        }
        let metersPerLatitude = 111_320.0
        let metersPerLongitude = metersPerLatitude * cos(point.latitude * .pi / 180)
        var best = Double.infinity
        for ring in rings {
            for (a, b) in zip(ring, ring.dropFirst()) {
                let ax = (a.longitude - point.longitude) * metersPerLongitude
                let ay = (a.latitude - point.latitude) * metersPerLatitude
                let bx = (b.longitude - point.longitude) * metersPerLongitude
                let by = (b.latitude - point.latitude) * metersPerLatitude
                let dx = bx - ax, dy = by - ay
                let lengthSquared = dx * dx + dy * dy
                let t = lengthSquared > 0 ? min(1, max(0, -(ax * dx + ay * dy) / lengthSquared)) : 0
                best = min(best, hypot(ax + t * dx, ay + t * dy))
            }
        }
        return best
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
