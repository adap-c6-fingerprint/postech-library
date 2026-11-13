import MapKit

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
        guard let scale = IndoorShelfLabelLevel.metersPerPoint(in: map) else { return nil }
        let next = IndoorShelfLabelLevel.resolve(metersPerPoint: scale, previous: level)
        level = next
        return next
    }

    func layout(in map: MKMapView, highlighted: Set<IndoorMapElement.ID>) {
        guard !isLayingOut, map.bounds.width > 0, map.bounds.height > 0 else { return }
        isLayingOut = true
        defer { isLayingOut = false }
        guard let nextLevel = resolveLevel(in: map) else { return }
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
