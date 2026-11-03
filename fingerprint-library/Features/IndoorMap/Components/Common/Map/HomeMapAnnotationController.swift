import MapKit
import UIKit

/// 홈 전용 핀의 갱신을 맡는다. 위치·길안내 갱신으로 같은 핀을 다시 만들지 않는다.
@MainActor
final class HomeMapAnnotationController {
    private var markers: [HomeMapMarker] = []

    func update(_ markers: [HomeMapMarker], in map: MKMapView) {
        guard self.markers != markers else { return }
        self.markers = markers
        let existing = map.annotations.compactMap { $0 as? HomeMapPointAnnotation }
        let byID = Dictionary(uniqueKeysWithValues: existing.map { ($0.marker.id, $0) })
        let next = Dictionary(uniqueKeysWithValues: markers.map { ($0.id, $0) })
        map.removeAnnotations(existing.filter { next[$0.marker.id] != $0.marker })
        map.addAnnotations(markers.filter { byID[$0.id]?.marker != $0 }.map(HomeMapPointAnnotation.init))
    }

    func occupiedRects(in map: MKMapView) -> [CGRect] {
        markers.map {
            let point = map.convert($0.coordinate.clCoordinate, toPointTo: map)
            return CGRect(x: point.x - 19, y: point.y - 19, width: 38, height: 38)
        }
    }

    static func view(for annotation: HomeMapPointAnnotation, in map: MKMapView) -> MKAnnotationView {
        let reuseID = "home-map-icon"
        let view = map.dequeueReusableAnnotationView(withIdentifier: reuseID)
            ?? MKAnnotationView(annotation: annotation, reuseIdentifier: reuseID)
        view.annotation = annotation
        if let name = annotation.marker.kind.assetName {
            view.image = icon(named: name)
        } else {
            view.image = UIImage(systemName: "mappin.circle.fill",
                withConfiguration: UIImage.SymbolConfiguration(pointSize: 28))?
                .withTintColor(.systemCyan, renderingMode: .alwaysOriginal)
        }
        view.centerOffset = .zero
        view.canShowCallout = true
        view.displayPriority = annotation.marker.kind == .favorite ? .required : .defaultHigh
        view.collisionMode = .circle
        view.clusteringIdentifier = nil
        view.isAccessibilityElement = true
        view.accessibilityLabel = annotation.title
        view.accessibilityValue = annotation.subtitle
        view.accessibilityIdentifier = "home-marker-\(annotation.marker.kind.rawValue)"
        return view
    }

    /// 에셋의 픽셀 크기·배율과 관계없이 지도에서는 30pt로 표시한다. 원본 픽셀과 색상은 유지한다.
    private static func icon(named name: String) -> UIImage? {
        guard let image = UIImage(named: name), let pixels = image.cgImage else { return nil }
        return UIImage(cgImage: pixels, scale: CGFloat(pixels.width) / 30, orientation: image.imageOrientation)
            .withRenderingMode(.alwaysOriginal)
    }
}

@MainActor
final class HomeMapPointAnnotation: NSObject, MKAnnotation {
    let marker: HomeMapMarker
    var coordinate: CLLocationCoordinate2D { marker.coordinate.clCoordinate }
    var title: String? { marker.title }
    var subtitle: String? { marker.subtitle }

    init(_ marker: HomeMapMarker) { self.marker = marker }
}
