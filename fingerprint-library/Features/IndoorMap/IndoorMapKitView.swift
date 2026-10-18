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
    var shelves: [ShelfDestination] = []
    var selectedShelfKey: ShelfKey?
    var onSelectShelf: (ShelfKey?) -> Void = { _ in }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> IndoorMapSurface {
        context.coordinator.makeMapView()
    }

    func updateUIView(_ view: IndoorMapSurface, context: Context) {
        context.coordinator.update(parent: self, in: view)
    }

    static func dismantleUIView(_ view: IndoorMapSurface, coordinator: Coordinator) {
        view.showsUserLocation = false
        view.onLayout = nil
        view.delegate = nil
        coordinator.detachMapView()
    }

    final class Coordinator: NSObject, MKMapViewDelegate, UIGestureRecognizerDelegate {
        var parent: IndoorMapKitView
        weak var mapView: MKMapView?
        var renderedMap: IndoorMap?
        var renderedFloorID: UUID?
        var selectedID: IndoorMapElement.ID?
        var lastCameraRequest: IndoorMapCameraRequest?
        private(set) var pendingCameraRequest: IndoorMapCameraRequest?
        private var isApplyingCamera = false
        private var overlayFeatures: [ObjectIdentifier: IndoorMapElement] = [:]
        private var positionAnnotation: PositionAnnotation?
        private var renderedPosition: IndoorPosition?
        private var renderedShelves: [ShelfDestination] = []

        init(parent: IndoorMapKitView) { self.parent = parent }

        func makeMapView() -> IndoorMapSurface {
            let view = IndoorMapSurface()
            view.delegate = self
            let configuration = MKStandardMapConfiguration(elevationStyle: .flat)
            configuration.pointOfInterestFilter = .excludingAll
            view.preferredConfiguration = configuration
            view.isPitchEnabled = true
            view.isRotateEnabled = true
            view.showsCompass = false
            view.showsScale = false
            view.setCameraZoomRange(MKMapView.CameraZoomRange(minCenterCoordinateDistance: 25, maxCenterCoordinateDistance: 5_000), animated: false)
            view.accessibilityIdentifier = "indoor-map"
            let tap = UITapGestureRecognizer(target: self, action: #selector(tapped(_:)))
            tap.cancelsTouchesInView = false
            tap.delegate = self
            view.addGestureRecognizer(tap)
            let longPress = UILongPressGestureRecognizer(target: self, action: #selector(longPressed(_:)))
            longPress.minimumPressDuration = 0.6
            longPress.cancelsTouchesInView = false
            longPress.delegate = self
            view.addGestureRecognizer(longPress)
            view.onLayout = { [weak self] view in self?.applyPendingCamera(in: view) }
            mapView = view
            return view
        }

        func update(parent: IndoorMapKitView, in view: MKMapView) {
            self.parent = parent
            if renderedMap != parent.map || renderedFloorID != parent.floor.id {
                render(in: view)
            }
            view.showsUserLocation = parent.showsUserLocation
            updatePosition(in: view)
            updateShelves(in: view)
            if selectedID != parent.selectedFeatureID {
                selectedID = parent.selectedFeatureID
                for overlay in view.overlays {
                    if let renderer = view.renderer(for: overlay) as? MKOverlayPathRenderer {
                        style(renderer, overlay: overlay)
                    }
                }
            }
            pendingCameraRequest = parent.cameraRequest == lastCameraRequest ? nil : parent.cameraRequest
            if pendingCameraRequest != nil { view.setNeedsLayout() }
        }

        private func updateShelves(in view: MKMapView) {
            let shelves = parent.shelves.filter { $0.floorID == parent.floor.id }
            if renderedShelves != shelves {
                view.removeAnnotations(view.annotations.filter { $0 is IndoorShelfAnnotation })
                renderedShelves = shelves
                view.addAnnotations(shelves.map { IndoorShelfAnnotation(destination: $0) })
            }
            for case let annotation as IndoorShelfAnnotation in view.annotations {
                (view.view(for: annotation) as? MKMarkerAnnotationView)?.markerTintColor =
                    annotation.destination.key == parent.selectedShelfKey ? .systemOrange : .systemIndigo
            }
        }

        private func applyPendingCamera(in view: MKMapView) {
            guard !isApplyingCamera, view.window != nil, view.bounds.width > 0, view.bounds.height > 0,
                  let request = pendingCameraRequest else { return }
            isApplyingCamera = true
            defer { isApplyingCamera = false }
            guard moveCamera(request, in: view) else { return }
            lastCameraRequest = request
            pendingCameraRequest = nil
        }

        func detachMapView() {
            mapView = nil
            pendingCameraRequest = nil
        }

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
            if let visible, let annotation = positionAnnotation, visible.source == annotation.position.source {
                annotation.update(visible)
                return
            }
            if let annotation = positionAnnotation { view.removeAnnotation(annotation) }
            positionAnnotation = visible.map { PositionAnnotation(position: $0) }
            if let annotation = positionAnnotation { view.addAnnotation(annotation) }
        }

        @discardableResult
        func moveCamera(_ request: IndoorMapCameraRequest, in view: MKMapView) -> Bool {
            switch request.target {
            case .floor(let id):
                let padding = UIEdgeInsets(top: 24, left: 80, bottom: 24, right: 24)
                guard view.bounds.width > padding.left + padding.right,
                      view.bounds.height > padding.top + padding.bottom,
                      let floor = parent.map.floors.first(where: { $0.id == id }) else { return false }
                let rect = MapKitGeometry.mapRect(for: floor.geometry)
                guard !rect.isNull else { return false }
                let camera = view.camera.copy() as! MKMapCamera
                camera.pitch = 0
                view.setCamera(camera, animated: false)
                view.setVisibleMapRect(rect, edgePadding: padding, animated: false)
            case .position(let coordinate):
                guard coordinate.isValid else { return false }
                view.setCenter(coordinate.clCoordinate, animated: true)
            }
            return true
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
            if let annotation = annotation as? PositionAnnotation, annotation.position.source == .simulation {
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: "simulation-dot")
                    ?? MKAnnotationView(annotation: annotation, reuseIdentifier: "simulation-dot")
                view.annotation = annotation
                view.frame.size = CGSize(width: 30, height: 30)
                view.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.18)
                view.layer.cornerRadius = 15
                if view.subviews.isEmpty {
                    let dot = UIView(frame: CGRect(x: 7, y: 7, width: 16, height: 16))
                    dot.backgroundColor = .systemBlue
                    dot.layer.cornerRadius = 8
                    dot.layer.borderWidth = 2
                    dot.layer.borderColor = UIColor.white.cgColor
                    view.addSubview(dot)
                }
                view.displayPriority = .required
                view.isEnabled = false
                view.isAccessibilityElement = true
                view.accessibilityLabel = "시뮬레이션 위치"
                view.accessibilityIdentifier = "simulation-position"
                return view
            }
            if let annotation = annotation as? IndoorShelfAnnotation {
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: "virtual-shelf") as? MKMarkerAnnotationView
                    ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: "virtual-shelf")
                view.annotation = annotation
                view.glyphImage = UIImage(systemName: "books.vertical.fill")
                view.markerTintColor = annotation.destination.key == parent.selectedShelfKey ? .systemOrange : .systemIndigo
                view.canShowCallout = true
                view.titleVisibility = .visible
                view.displayPriority = .required
                view.clusteringIdentifier = nil
                view.accessibilityLabel = annotation.title
                view.accessibilityValue = annotation.subtitle
                view.accessibilityIdentifier = "shelf-\(annotation.destination.key.value)"
                return view
            }
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
            if let annotation = annotation as? IndoorShelfAnnotation {
                parent.onSelectShelf(annotation.destination.key)
                return
            }
            guard let annotation = annotation as? FeatureAnnotation else { return }
            if parent.isPlacingOrigin {
                parent.onPlaceOrigin(IndoorMapCoordinate(latitude: annotation.coordinate.latitude, longitude: annotation.coordinate.longitude))
            } else {
                parent.onSelect(annotation.feature.id)
            }
            mapView.deselectAnnotation(annotation, animated: false)
        }

        func mapView(_ mapView: MKMapView, didDeselect annotation: any MKAnnotation) {
            if let annotation = annotation as? IndoorShelfAnnotation,
               parent.selectedShelfKey == annotation.destination.key { parent.onSelectShelf(nil) }
        }

        @objc func tapped(_ gesture: UITapGestureRecognizer) {
            guard let view = mapView else { return }
            let location = gesture.location(in: view)
            let value = view.convert(location, toCoordinateFrom: view)
            let coordinate = IndoorMapCoordinate(latitude: value.latitude, longitude: value.longitude)
            if parent.isPlacingOrigin {
                parent.onPlaceOrigin(coordinate)
            } else {
                parent.onSelectShelf(nil)
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

/// SwiftUI의 배치가 끝나 실제 화면 크기를 사용할 수 있을 때 보류한 카메라 요청을 적용한다.
final class IndoorMapSurface: MKMapView {
    var onLayout: ((IndoorMapSurface) -> Void)?

    override func layoutSubviews() {
        super.layoutSubviews()
        onLayout?(self)
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil { setNeedsLayout() }
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
    private(set) var position: IndoorPosition
    @objc dynamic var coordinate: CLLocationCoordinate2D
    var title: String? {
        switch position.source {
        case .simulation: "시뮬레이션 위치"
        case .replay: "테스트 재생 위치"
        default: "수동 출발점"
        }
    }
    init(position: IndoorPosition) {
        self.position = position
        coordinate = position.coordinate.clCoordinate
    }
    func update(_ position: IndoorPosition) {
        self.position = position
        if coordinate.latitude != position.coordinate.latitude || coordinate.longitude != position.coordinate.longitude {
            coordinate = position.coordinate.clCoordinate
        }
    }
}

/// 서가 핀은 시연용 목적지의 표시다. 경로 입력은 annotation 객체가 아닌 서가 키·도착 노드로 전달한다.
final class IndoorShelfAnnotation: NSObject, MKAnnotation {
    let destination: ShelfDestination
    var coordinate: CLLocationCoordinate2D { destination.arrivalCoordinate.clCoordinate }
    var title: String? { destination.name }
    var subtitle: String? { "테스트용 가상 서가" }
    init(destination: ShelfDestination) { self.destination = destination }
}
