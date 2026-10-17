import MapKit

extension IndoorMapCoordinate {
    var clCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

/// 내부 ring과 MultiPolygon을 유지한 채 MapKit의 지도 좌표로 변환한다.
enum MapKitGeometry {
    static func overlays(for geometry: IndoorMapGeometry) -> [any MKOverlay] {
        switch geometry {
        case .point: return []
        case .lineString(let points):
            return [MKPolyline(coordinates: points.map(\.clCoordinate), count: points.count)]
        case .polygon(let rings):
            return polygon(rings).map { [$0] } ?? []
        case .multiPolygon(let polygons):
            return polygons.compactMap { polygon($0) }
        }
    }

    static func mapRect(for geometry: IndoorMapGeometry) -> MKMapRect {
        geometry.coordinates.reduce(MKMapRect.null) { rect, coordinate in
            let point = MKMapPoint(coordinate.clCoordinate)
            return rect.union(MKMapRect(x: point.x, y: point.y, width: 0.1, height: 0.1))
        }
    }

    private static func polygon(_ rings: [[IndoorMapCoordinate]]) -> MKPolygon? {
        guard let outer = rings.first else { return nil }
        let holes = rings.dropFirst().map {
            MKPolygon(coordinates: $0.map(\.clCoordinate), count: $0.count)
        }
        return MKPolygon(coordinates: outer.map(\.clCoordinate), count: outer.count, interiorPolygons: holes)
    }
}
