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

    static func view(for annotation: HomeMapPointAnnotation, in map: MKMapView) -> MKAnnotationView {
        let reuseID = "home-map-icon"
        let view = map.dequeueReusableAnnotationView(withIdentifier: reuseID)
            ?? MKAnnotationView(annotation: annotation, reuseIdentifier: reuseID)
        view.annotation = annotation
        if let name = annotation.marker.kind.assetName {
            view.image = MapAnnotationImage.asset(named: name)
        } else {
            view.image = MapAnnotationImage.symbol(named: "mappin.circle.fill", tintColor: .systemCyan)
        }
        view.bounds = CGRect(origin: .zero, size: MapAnnotationImage.size)
        view.centerOffset = .zero
        view.canShowCallout = true
        view.displayPriority = .required
        view.zPriority = .max
        view.selectedZPriority = .max
        view.collisionMode = .circle
        view.clusteringIdentifier = nil
        view.isAccessibilityElement = true
        view.accessibilityLabel = annotation.title
        view.accessibilityValue = annotation.subtitle
        view.accessibilityIdentifier = "home-marker-\(annotation.marker.kind.rawValue)"
        return view
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
