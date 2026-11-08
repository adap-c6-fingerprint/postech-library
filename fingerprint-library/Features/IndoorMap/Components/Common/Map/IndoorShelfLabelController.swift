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

    func layout(in map: MKMapView, highlighted: Set<IndoorMapElement.ID>) {
        guard !isLayingOut, map.bounds.width > 0, map.bounds.height > 0 else { return }
        isLayingOut = true
        defer { isLayingOut = false }
        guard let nextLevel = resolveLevel(in: map) else { return }
        // 레벨을 만들 때 정한 순서를 유지한다. 겹침을 숨기지 않으므로 프레임별 우선순위 정렬은 필요 없다.
        let candidates = (levels[nextLevel] ?? []).compactMap { annotation -> (IndoorShelfLabelAnnotation, CGPoint)? in
            let point = map.convert(annotation.coordinate, toPointTo: map)
            guard map.bounds.insetBy(dx: -100, dy: -100).contains(point) else { return nil }
            return (annotation, point)
        }
        var chosen: [IndoorShelfLabelAnnotation] = []
        for (annotation, point) in candidates {
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
            let frame = CGRect(x: point.x - width / 2, y: point.y - height / 2,
                               width: width, height: height)
            // 화면에 걸친 부분만 그린다. 겹침이나 화면 경계 때문에 자리를 옮기지 않는다.
            guard map.bounds.intersects(frame) else { continue }
            annotation.layoutAngle = angle
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
