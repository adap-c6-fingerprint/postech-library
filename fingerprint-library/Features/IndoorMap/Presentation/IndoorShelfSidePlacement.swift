import MapKit

/// 각 면의 바깥 모서리에서 시작해 일정한 안쪽 여백으로 표시 위치를 정한다.
struct IndoorShelfSidePlacement {
    let origin: MKMapPoint
    private let along: CGVector
    private let inward: CGVector
    private let length: Double
    private let depth: Double
    private let geometry: IndoorMapGeometry

    init?(label: IndoorShelfLabel, axis: (MKMapPoint, MKMapPoint), shelfCenter: MKMapPoint) {
        let dx = axis.1.x - axis.0.x, dy = axis.1.y - axis.0.y
        let magnitude = hypot(dx, dy)
        guard magnitude > 0 else { return nil }
        let u = CGVector(dx: dx / magnitude, dy: dy / magnitude)
        let rect = MapKitGeometry.mapRect(for: label.geometry)
        let center = MKMapPoint(x: rect.midX, y: rect.midY)
        let normal = CGVector(dx: -u.dy, dy: u.dx)
        let side = (center.x - shelfCenter.x) * normal.dx + (center.y - shelfCenter.y) * normal.dy
        guard abs(side) > 0.000_001 else { return nil }
        let sign: Double = side < 0 ? 1 : -1
        let inward = CGVector(dx: normal.dx * sign, dy: normal.dy * sign)
        let end: Double = label.side == .a ? 1 : -1
        let along = CGVector(dx: u.dx * end, dy: u.dy * end)
        let points = label.geometry.coordinates.map { MKMapPoint($0.clCoordinate) }
        func project(_ point: MKMapPoint, on vector: CGVector) -> Double {
            (point.x - center.x) * vector.dx + (point.y - center.y) * vector.dy
        }
        let xs = points.map { project($0, on: along) }, ys = points.map { project($0, on: inward) }
        guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max(),
              maxX > minX, maxY > minY else { return nil }
        // 꼭짓점 중 바깥쪽 시작 모서리를 선택한다. 지도 회전으로 기준 모서리를 바꾸지 않는다.
        let width = maxX - minX, height = maxY - minY
        func score(_ point: MKMapPoint) -> Double {
            (project(point, on: along) - minX) / width + (project(point, on: inward) - minY) / height
        }
        guard let origin = points.min(by: { score($0) < score($1) }) else { return nil }
        self.origin = origin
        self.along = along
        self.inward = inward
        self.length = maxX - project(origin, on: along)
        self.depth = maxY - project(origin, on: inward)
        self.geometry = label.geometry
    }

    /// 모서리에서 정한 한 자리만 반환한다. 화면 경계·다른 아이콘에 맞춰 재배치하지 않는다.
    func center(in map: MKMapView, labelSize: CGSize) -> CGPoint? {
        let start = map.convert(origin.coordinate, toPointTo: map)
        func projected(_ vector: CGVector, distance: Double) -> CGPoint {
            let point = MKMapPoint(x: origin.x + vector.dx * distance, y: origin.y + vector.dy * distance)
            let end = map.convert(point.coordinate, toPointTo: map)
            return CGPoint(x: end.x - start.x, y: end.y - start.y)
        }
        let edge = projected(along, distance: length), innerEdge = projected(inward, distance: depth)
        let width = hypot(edge.x, edge.y), height = hypot(innerEdge.x, innerEdge.y)
        guard width > 0, height > 0 else { return nil }
        let u = CGPoint(x: edge.x / width, y: edge.y / width)
        let v = CGPoint(x: innerEdge.x / height, y: innerEdge.y / height)
        let x = min(24 + labelSize.width / 2, width / 2)
        let rings: [[IndoorMapCoordinate]]
        switch geometry {
        case .polygon(let polygon): rings = polygon.first.map { [$0] } ?? []
        case .multiPolygon(let polygons): rings = polygons.compactMap(\.first)
        default: return nil
        }
        var intersections: [CGFloat] = []
        for ring in rings {
            let projectedRing = ring.map { coordinate in
                let pixel = map.convert(coordinate.clCoordinate, toPointTo: map)
                let dx = pixel.x - start.x, dy = pixel.y - start.y
                return CGPoint(x: dx * u.x + dy * u.y, y: dx * v.x + dy * v.y)
            }
            for (a, b) in zip(projectedRing, projectedRing.dropFirst()) {
                guard x >= min(a.x, b.x), x <= max(a.x, b.x) else { continue }
                if abs(b.x - a.x) < 0.000_001 {
                    intersections += [a.y, b.y]
                } else {
                    intersections.append(a.y + (b.y - a.y) * (x - a.x) / (b.x - a.x))
                }
            }
        }
        guard let outside = intersections.min(), let inside = intersections.max(), inside > outside else { return nil }
        // 면이 좁아도 A/B를 표시하며 글자 중심은 자기 면 안에 둔다.
        let y = min(outside + 2 + labelSize.height / 2, (outside + inside) / 2)
        return CGPoint(x: start.x + u.x * x + v.x * y, y: start.y + u.y * x + v.y * y)
    }
}
