import MapKit
import SwiftUI

struct IndoorMapKitView: UIViewRepresentable {
    let map: IndoorMap
    let floor: IndoorMapFloor
    let selectedFeatureID: IndoorMapElement.ID?
    let position: IndoorPosition?
    let showsUserLocation: Bool
    let isPlacingOrigin: Bool
    let cameraRequest: IndoorMapCameraRequest?
    let onSelect: (IndoorMapElement.ID?) -> Void
    let onPlaceOrigin: (IndoorMapCoordinate) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> MKMapView {
        let view = MKMapView()
        view.delegate = context.coordinator
        let configuration = MKStandardMapConfiguration(elevationStyle: .flat)
        configuration.pointOfInterestFilter = .excludingAll
        view.preferredConfiguration = configuration
        view.isPitchEnabled = true
        view.isRotateEnabled = true
        view.showsCompass = true
        view.showsScale = true
        view.setCameraZoomRange(MKMapView.CameraZoomRange(minCenterCoordinateDistance: 25, maxCenterCoordinateDistance: 5_000), animated: false)
        view.accessibilityIdentifier = "indoor-map"
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tapped(_:)))
        tap.cancelsTouchesInView = false
        tap.delegate = context.coordinator
        view.addGestureRecognizer(tap)
        let longPress = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.longPressed(_:)))
        longPress.minimumPressDuration = 0.6
        longPress.cancelsTouchesInView = false
        longPress.delegate = context.coordinator
        view.addGestureRecognizer(longPress)
        context.coordinator.mapView = view
        return view
    }

    func updateUIView(_ view: MKMapView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        if coordinator.renderedMap != map || coordinator.renderedFloorID != floor.id {
            coordinator.render(in: view)
        }
        view.showsUserLocation = showsUserLocation
        coordinator.updatePosition(in: view)
        if coordinator.selectedID != selectedFeatureID {
            coordinator.selectedID = selectedFeatureID
            for overlay in view.overlays {
                if let renderer = view.renderer(for: overlay) as? MKOverlayPathRenderer {
                    coordinator.style(renderer, overlay: overlay)
                }
            }
        }
        if let request = cameraRequest, coordinator.lastCameraRequest != request {
            coordinator.lastCameraRequest = request
            coordinator.moveCamera(request, in: view)
        }
    }

    static func dismantleUIView(_ view: MKMapView, coordinator: Coordinator) {
        view.showsUserLocation = false
        view.delegate = nil
        coordinator.mapView = nil
    }

    final class Coordinator: NSObject, MKMapViewDelegate, UIGestureRecognizerDelegate {
        var parent: IndoorMapKitView
        weak var mapView: MKMapView?
        var renderedMap: IndoorMap?
        var renderedFloorID: UUID?
        var selectedID: IndoorMapElement.ID?
        var lastCameraRequest: IndoorMapCameraRequest?
        private var overlayFeatures: [ObjectIdentifier: IndoorMapElement] = [:]
        private var positionAnnotation: PositionAnnotation?
        private var renderedPosition: IndoorPosition?

        init(parent: IndoorMapKitView) { self.parent = parent }

        func render(in view: MKMapView) {
            view.removeOverlays(view.overlays)
            view.removeAnnotations(view.annotations.filter { $0 is FeatureAnnotation })
            overlayFeatures.removeAll()
            renderedMap = parent.map
            renderedFloorID = parent.floor.id
            selectedID = parent.selectedFeatureID
            for overlay in MapKitGeometry.overlays(for: parent.floor.geometry) {
                view.addOverlay(overlay, level: .aboveRoads)
            }
            let features = parent.map.features.filter { $0.floorID == parent.floor.id }
            // 넓은 구역부터 그리고 그 위에 fixture와 opening을 올린다.
            for kind in [IndoorMapElement.Kind.unit, .fixture, .opening] {
                for feature in features where feature.kind == kind {
                    for overlay in MapKitGeometry.overlays(for: feature.geometry) {
                        overlayFeatures[ObjectIdentifier(overlay)] = feature
                        view.addOverlay(overlay, level: .aboveRoads)
                    }
                }
            }
            view.addAnnotations(features.compactMap { feature in
                guard feature.kind == .amenity, case .point(let coordinate) = feature.geometry else { return nil }
                return FeatureAnnotation(feature: feature, coordinate: coordinate.clCoordinate)
            })
        }

        func updatePosition(in view: MKMapView) {
            let visible = parent.position.flatMap { position -> IndoorPosition? in
                guard position.source != .sensor, position.floorOrdinal == parent.floor.ordinal else { return nil }
                return position
            }
            guard visible != renderedPosition else { return }
            renderedPosition = visible
            if let annotation = positionAnnotation { view.removeAnnotation(annotation) }
            positionAnnotation = visible.map { PositionAnnotation(position: $0) }
            if let annotation = positionAnnotation { view.addAnnotation(annotation) }
        }

        func moveCamera(_ request: IndoorMapCameraRequest, in view: MKMapView) {
            switch request.target {
            case .floor(let id):
                guard let floor = parent.map.floors.first(where: { $0.id == id }) else { return }
                let rect = MapKitGeometry.mapRect(for: floor.geometry)
                guard !rect.isNull else { return }
                view.setVisibleMapRect(rect, edgePadding: UIEdgeInsets(top: 55, left: 50, bottom: 190, right: 35), animated: false)
                let camera = view.camera.copy() as! MKMapCamera
                camera.pitch = 0
                view.setCamera(camera, animated: false)
            case .position(let coordinate):
                view.setCenter(coordinate.clCoordinate, animated: true)
            }
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: any MKOverlay) -> MKOverlayRenderer {
            let renderer: MKOverlayPathRenderer
            if let polygon = overlay as? MKPolygon { renderer = MKPolygonRenderer(polygon: polygon) }
            else if let line = overlay as? MKPolyline { renderer = MKPolylineRenderer(polyline: line) }
            else { return MKOverlayRenderer(overlay: overlay) }
            style(renderer, overlay: overlay)
            return renderer
        }

        func style(_ renderer: MKOverlayPathRenderer, overlay: any MKOverlay) {
            let feature = overlayFeatures[ObjectIdentifier(overlay)]
            renderer.lineWidth = feature?.kind == .opening ? 2 : 0.8
            renderer.strokeColor = .systemGray2
            switch feature?.kind {
            case .fixture: renderer.fillColor = UIColor(red: 0.83, green: 0.73, blue: 0.57, alpha: 1)
            case .unit:
                renderer.fillColor = feature?.category == "walkway" ? .systemGray6 : .white
                if feature?.category == "stairs" { renderer.fillColor = UIColor.systemPurple.withAlphaComponent(0.12) }
                if feature?.category == "elevator" { renderer.fillColor = UIColor.systemBlue.withAlphaComponent(0.15) }
            case .opening:
                renderer.strokeColor = .white
            default: renderer.fillColor = UIColor.systemGray6.withAlphaComponent(0.95)
            }
            if let feature, feature.id == selectedID {
                renderer.fillColor = UIColor.systemTeal.withAlphaComponent(0.35)
                renderer.strokeColor = .systemTeal
                renderer.lineWidth = 2
            }
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: any MKAnnotation) -> MKAnnotationView? {
            if annotation is MKUserLocation { return nil }
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: "indoor-marker") as? MKMarkerAnnotationView
                ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: "indoor-marker")
            view.annotation = annotation
            view.canShowCallout = false
            view.titleVisibility = .hidden
            view.displayPriority = .defaultLow
            view.clusteringIdentifier = nil
            if let annotation = annotation as? FeatureAnnotation {
                view.glyphImage = UIImage(systemName: Self.symbol(for: annotation.feature.category))
                view.markerTintColor = .systemTeal
                view.accessibilityLabel = annotation.title
            } else if let annotation = annotation as? PositionAnnotation {
                view.glyphImage = UIImage(systemName: annotation.position.source == .replay ? "play.fill" : "mappin")
                view.markerTintColor = annotation.position.source == .replay ? .systemOrange : .systemPurple
                view.displayPriority = .required
                view.accessibilityLabel = annotation.title
            }
            return view
        }

        func mapView(_ mapView: MKMapView, didSelect annotation: any MKAnnotation) {
            guard let annotation = annotation as? FeatureAnnotation else { return }
            if parent.isPlacingOrigin {
                parent.onPlaceOrigin(IndoorMapCoordinate(latitude: annotation.coordinate.latitude, longitude: annotation.coordinate.longitude))
            } else {
                parent.onSelect(annotation.feature.id)
            }
            mapView.deselectAnnotation(annotation, animated: false)
        }

        @objc func tapped(_ gesture: UITapGestureRecognizer) {
            guard let view = mapView else { return }
            let location = gesture.location(in: view)
            let value = view.convert(location, toCoordinateFrom: view)
            let coordinate = IndoorMapCoordinate(latitude: value.latitude, longitude: value.longitude)
            if parent.isPlacingOrigin {
                parent.onPlaceOrigin(coordinate)
            } else {
                let features = parent.map.features.filter { $0.floorID == parent.floor.id }
                // annotation의 지도 기준점도 터치 대상으로 인정한다.
                // 핀 아래를 눌렀을 때 배경 unit이 선택되는 것을 방지한다.
                let amenities = features.compactMap { feature -> (IndoorMapElement, CGFloat)? in
                    guard feature.kind == .amenity, case .point(let point) = feature.geometry else { return nil }
                    let projected = view.convert(point.clCoordinate, toPointTo: view)
                    let distance = hypot(projected.x - location.x, projected.y - location.y)
                    return distance <= 22 ? (feature, distance) : nil
                }
                let selected = amenities.min { $0.1 < $1.1 }?.0
                    ?? features.first { $0.kind == .fixture && $0.geometry.contains(coordinate) }
                    ?? features.first { $0.kind == .unit && $0.geometry.contains(coordinate) }
                parent.onSelect(selected?.id)
            }
        }

        @objc func longPressed(_ gesture: UILongPressGestureRecognizer) {
            guard gesture.state == .began, let view = mapView else { return }
            let value = view.convert(gesture.location(in: view), toCoordinateFrom: view)
            parent.onPlaceOrigin(IndoorMapCoordinate(latitude: value.latitude, longitude: value.longitude))
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool { true }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            var view = touch.view
            while let current = view {
                if current is MKAnnotationView { return false }
                view = current.superview
            }
            // MapKit이 annotation 주변의 터치 영역을 별도 뷰로 전달할 때도
            // 시설 선택과 지도 바닥 탭이 한 번에 처리되지 않게 한다.
            if let mapView {
                let point = touch.location(in: mapView)
                for annotation in mapView.annotations {
                    guard let annotationView = mapView.view(for: annotation) else { continue }
                    let bounds = annotationView.convert(annotationView.bounds, to: mapView).insetBy(dx: -6, dy: -6)
                    if bounds.contains(point) { return false }
                }
            }
            return true
        }

        private static func symbol(for category: String?) -> String {
            switch category {
            case "stairs": "stairs"
            case "elevator": "arrow.up.arrow.down"
            case "restroom", "restroom.male", "restroom.female": "figure.stand"
            case "restroom.wheelchair": "figure.roll"
            case "breakarea": "cup.and.saucer.fill"
            case "information": "info"
            default: "mappin"
            }
        }
    }
}

private final class FeatureAnnotation: NSObject, MKAnnotation {
    let feature: IndoorMapElement
    let coordinate: CLLocationCoordinate2D
    var title: String? { feature.name ?? feature.category ?? "시설" }
    init(feature: IndoorMapElement, coordinate: CLLocationCoordinate2D) {
        self.feature = feature
        self.coordinate = coordinate
    }
}

private final class PositionAnnotation: NSObject, MKAnnotation {
    let position: IndoorPosition
    var coordinate: CLLocationCoordinate2D { position.coordinate.clCoordinate }
    var title: String? { position.source == .replay ? "테스트 재생 위치" : "수동 출발점" }
    init(position: IndoorPosition) { self.position = position }
}
