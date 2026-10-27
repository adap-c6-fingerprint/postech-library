import MapKit

extension IndoorMapCoordinate {
    /// 순수 좌표 모델을 MapKit 경계에서만 Core Location 좌표로 변환한다.
    var clCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

/// 내부 ring과 MultiPolygon을 유지한 채 MapKit의 지도 좌표로 변환한다.
enum MapKitGeometry {
    /// 선은 polyline, 면은 polygon overlay로 변환하고 내부 구멍과 분리된 면을 유지한다.
    /// 점은 시설 annotation으로 표시하므로 이 함수에서는 overlay를 만들지 않는다.
    /// - Parameter geometry: 변환할 도메인 도형.
    /// - Returns: 도형을 그릴 MapKit overlay 목록.
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

    /// 모든 좌표를 포함하는 MapKit 범위를 계산해 층 전체 카메라 맞춤에 사용한다.
    /// 이 범위의 단위는 MapKit 지도 좌표이며, 미터 단위의 카메라 거리와는 다르다.
    static func mapRect(for geometry: IndoorMapGeometry) -> MKMapRect {
        geometry.coordinates.reduce(MKMapRect.null) { rect, coordinate in
            let point = MKMapPoint(coordinate.clCoordinate)
            return rect.union(MKMapRect(x: point.x, y: point.y, width: 0.1, height: 0.1))
        }
    }

    /// 외곽 ring을 본체로, 나머지 ring을 interiorPolygons로 연결한다. 외곽이 없으면 nil이다.
    private static func polygon(_ rings: [[IndoorMapCoordinate]]) -> MKPolygon? {
        guard let outer = rings.first else { return nil }
        let holes = rings.dropFirst().map {
            MKPolygon(coordinates: $0.map(\.clCoordinate), count: $0.count)
        }
        return MKPolygon(coordinates: outer.map(\.clCoordinate), count: outer.count, interiorPolygons: holes)
    }
}
