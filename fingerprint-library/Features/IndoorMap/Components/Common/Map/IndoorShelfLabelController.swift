import MapKit

/// 확대 단계 전환·고정 위치 표시·재사용을 담당한다. 위치 갱신만으로 군집을 다시 계산하지 않는다.
@MainActor
final class IndoorShelfLabelController {
    private var labels: [IndoorShelfLabel] = []
    private var levels: [IndoorShelfLabelLevel: [IndoorShelfLabelAnnotation]] = [:]
    private var displayed = Set<String>()
    private var level: IndoorShelfLabelLevel?
    private var isLayingOut = false

    func update(_ labels: [IndoorShelfLabel], in map: MKMapView) {
        guard self.labels != labels else { return }
        self.labels = labels
        let layout = IndoorShelfLabelLayout(labels: labels)
        levels = Dictionary(uniqueKeysWithValues: IndoorShelfLabelLevel.allCases.map {
            ($0, layout.presentations(at: $0).map(IndoorShelfLabelAnnotation.init))
        })
        map.removeAnnotations(map.annotations.filter { $0 is IndoorShelfLabelAnnotation })
        displayed = []
        level = nil
    }

    private func resolveLevel(in map: MKMapView) -> IndoorShelfLabelLevel? {
        guard map.bounds.width > 0, map.bounds.height > 0 else { return nil }
        let center = CGPoint(x: map.bounds.midX, y: map.bounds.midY)
        let a = MKMapPoint(map.convert(center, toCoordinateFrom: map))
        let b = MKMapPoint(map.convert(CGPoint(x: center.x + 10, y: center.y), toCoordinateFrom: map))
        let scale = a.distance(to: b) / 10
        guard scale.isFinite, scale > 0 else { return nil }
        let next = IndoorShelfLabelLevel.resolve(metersPerPoint: scale, previous: level)
        level = next
        return next
    }

    func layout(in map: MKMapView, highlighted: Set<IndoorMapElement.ID>,
                favorites: Set<IndoorMapElement.ID>) {
        guard !isLayingOut, map.bounds.width > 0, map.bounds.height > 0 else { return }
        isLayingOut = true
        defer { isLayingOut = false }
        let center = CGPoint(x: map.bounds.midX, y: map.bounds.midY)
        guard let nextLevel = resolveLevel(in: map) else { return }
        // 한 면에 하트가 있으면 같은 실물 서가의 A/B 모두 먼저 배치한다.
        let favoriteRows = Set((levels[.number] ?? []).filter { $0.presentation.isHighlighted(by: favorites) }
            .flatMap { $0.presentation.members.map(\.mapElementID) })
        let candidates = (levels[nextLevel] ?? []).compactMap { annotation -> (IndoorShelfLabelAnnotation, CGPoint, CGFloat, CGPoint)? in
            let anchor = map.convert(annotation.coordinate, toPointTo: map)
            let position = annotation.presentation.sidePlacement?.center(in: map, labelSize: annotation.labelSize) ?? anchor
            guard map.bounds.insetBy(dx: -100, dy: -100).contains(position) else { return nil }
            let offset = CGPoint(x: position.x - anchor.x, y: position.y - anchor.y)
            return (annotation, anchor, hypot(position.x - center.x, position.y - center.y), offset)
        }.sorted {
            let left = $0.0.presentation.isHighlighted(by: highlighted) ? 2
                : ($0.0.presentation.isHighlighted(by: favoriteRows) ? 1 : 0)
            let right = $1.0.presentation.isHighlighted(by: highlighted) ? 2
                : ($1.0.presentation.isHighlighted(by: favoriteRows) ? 1 : 0)
            if left != right { return left > right }
            return $0.2 == $1.2 ? $0.0.presentation.id < $1.0.presentation.id : $0.2 < $1.2
        }
        var chosen: [IndoorShelfLabelAnnotation] = []
        for (annotation, point, _, offset) in candidates {
            var angle: CGFloat = 0
            if let (a, b) = annotation.presentation.axis {
                let p = map.convert(a.coordinate, toPointTo: map), q = map.convert(b.coordinate, toPointTo: map)
                angle = atan2(q.y - p.y, q.x - p.x)
                if angle > .pi / 2 { angle -= .pi }
                if angle < -.pi / 2 { angle += .pi }
            }
            let size = annotation.labelSize
            let width = abs(cos(angle)) * size.width + abs(sin(angle)) * size.height
            let height = abs(sin(angle)) * size.width + abs(cos(angle)) * size.height
            let frame = CGRect(x: point.x + offset.x - width / 2, y: point.y + offset.y - height / 2,
                               width: width, height: height)
            // 화면에 걸친 부분만 그린다. 겹침이나 화면 경계 때문에 자리를 옮기지 않는다.
            guard map.bounds.intersects(frame) else { continue }
            annotation.layoutAngle = angle
            annotation.layoutOffset = offset
            chosen.append(annotation)
        }

        let ids = Set(chosen.map { $0.presentation.id })
        if ids != displayed {
            map.removeAnnotations(map.annotations.compactMap { $0 as? IndoorShelfLabelAnnotation }
                .filter { !ids.contains($0.presentation.id) })
            map.addAnnotations(chosen.filter { !displayed.contains($0.presentation.id) })
            displayed = ids
        }
        for annotation in chosen {
            (map.view(for: annotation) as? IndoorShelfLabelView)?.configure(annotation,
                highlighted: annotation.presentation.isHighlighted(by: highlighted))
        }
    }
}
