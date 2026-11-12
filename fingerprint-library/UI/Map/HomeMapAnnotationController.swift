import MapKit
import UIKit

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
        let view = map.dequeueReusableAnnotationView(withIdentifier: HomeMapAnnotationView.reuseID)
            as? HomeMapAnnotationView
            ?? HomeMapAnnotationView(annotation: annotation, reuseIdentifier: HomeMapAnnotationView.reuseID)
        view.configure(annotation)
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
