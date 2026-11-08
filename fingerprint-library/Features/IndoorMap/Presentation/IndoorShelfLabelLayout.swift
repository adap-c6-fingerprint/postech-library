import MapKit

/// 서가 원본은 유지하고 지도에 보이는 상세도만 바꾼다.
enum IndoorShelfLabelLevel: String, CaseIterable {
    case group, number

    static func resolve(metersPerPoint: Double, previous: Self?) -> Self {
        let groupBoundary = previous == .group ? 0.09 : (previous == nil ? 0.10 : 0.11)
        return metersPerPoint > groupBoundary ? .group : .number
    }
}

struct IndoorShelfLabelPresentation {
    let id: String
    let level: IndoorShelfLabelLevel
    let members: [IndoorShelfLabel]
    let text: String
    let point: MKMapPoint
    let axis: (MKMapPoint, MKMapPoint)?

    var coordinate: CLLocationCoordinate2D { point.coordinate }
    var floorID: UUID { members[0].floorID }
    func isHighlighted(by ids: Set<IndoorMapElement.ID>) -> Bool {
        members.contains { ids.contains($0.mapElementID) }
    }

    /// 여러 조각으로 구성된 도형도 전체 길이의 주축에 맞춰 서가 번호를 표시한다.
    static func shelfAxis(_ geometry: IndoorMapGeometry) -> (MKMapPoint, MKMapPoint)? {
        var points: [MKMapPoint] = []
        for coordinate in geometry.coordinates {
            let point = MKMapPoint(coordinate.clCoordinate)
            if !points.contains(where: { $0.x == point.x && $0.y == point.y }) { points.append(point) }
        }
        guard points.count > 1 else { return nil }
        let x: Double = points.reduce(0.0) { $0 + $1.x } / Double(points.count)
        let y: Double = points.reduce(0.0) { $0 + $1.y } / Double(points.count)
        var xx = 0.0, yy = 0.0, xy = 0.0
        for point in points {
            let dx = point.x - x, dy = point.y - y
            xx += dx * dx; yy += dy * dy; xy += dx * dy
        }
        guard xx + yy > 0 else { return nil }
        let angle = atan2(2 * xy, xx - yy) / 2
        var dx = cos(angle), dy = sin(angle)
        if abs(dx) >= abs(dy) ? dx < 0 : dy < 0 { dx = -dx; dy = -dy }
        let positions = points.map { ($0.x - x) * dx + ($0.y - y) * dy }
        guard let first = positions.min(), let last = positions.max(), last > first else { return nil }
        return (.init(x: x + first * dx, y: y + first * dy), .init(x: x + last * dx, y: y + last * dy))
    }
}

/// 같은 fixture의 A/B만 합치고, 가까운 실제 서가 중심을 연결해 층별 군집을 만든다.
struct IndoorShelfLabelLayout {
    let numbers: [IndoorShelfLabelPresentation]
    let groups: [IndoorShelfLabelPresentation]

    init(labels: [IndoorShelfLabel]) {
        let paired = Dictionary(grouping: labels) { "\($0.floorID)-\($0.fixtureNumber.dropLast(2))" }
        let numberModels: [IndoorShelfLabelPresentation] = paired.sorted { $0.key < $1.key }.map { id, members in
            let sorted = members.sorted { $0.side.rawValue < $1.side.rawValue }
            let rect = sorted.reduce(MKMapRect.null) { $0.union(MapKitGeometry.mapRect(for: $1.geometry)) }
            return .init(id: "number-\(id)", level: .number, members: sorted, text: sorted[0].realNumber,
                         point: .init(x: rect.midX, y: rect.midY),
                         axis: IndoorShelfLabelPresentation.shelfAxis(sorted[0].geometry))
        }
        numbers = numberModels
        var remaining = Set(numberModels.indices)
        var clustered: [IndoorShelfLabelPresentation] = []
        while let seed = remaining.min() {
            remaining.remove(seed)
            var component = [seed], queue = [seed]
            while let current = queue.popLast() {
                let neighbors = remaining.filter {
                    numberModels[$0].floorID == numberModels[current].floorID
                        && numberModels[$0].point.distance(to: numberModels[current].point) <= 2.8
                }
                for neighbor in neighbors.sorted() {
                    remaining.remove(neighbor)
                    component.append(neighbor)
                    queue.append(neighbor)
                }
            }
            let shelves = component.sorted().map { numberModels[$0] }
            let members = shelves.flatMap(\.members)
            let x = shelves.map(\.point.x).reduce(0, +) / Double(shelves.count)
            let y = shelves.map(\.point.y).reduce(0, +) / Double(shelves.count)
            let numeric = shelves.map(\.text).filter { Int($0) != nil }
            let named = shelves.map(\.text).filter { Int($0) == nil }
            let text = [numeric, named].filter { !$0.isEmpty }.map { values -> String in
                let sorted = values.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
                return sorted.first == sorted.last ? sorted[0] : "\(sorted[0])~\(sorted[sorted.count - 1])"
            }.joined(separator: "\n")
            clustered.append(.init(id: "group-\(shelves[0].id)", level: .group, members: members,
                                   text: text, point: .init(x: x, y: y), axis: nil))
        }
        groups = clustered
    }

    func presentations(at level: IndoorShelfLabelLevel) -> [IndoorShelfLabelPresentation] {
        switch level {
        case .group: groups
        case .number: numbers
        }
    }
}
