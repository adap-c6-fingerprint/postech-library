import MapKit
import SwiftUI

/// 순수 지도·위치·경로 값을 MapKit에 표시하는 SwiftUI와 UIKit 사이의 어댑터.
///
/// 선택과 카메라 이동 의도는 값·콜백으로 주고받고, MKMapView와 overlay의 수명은 Coordinator가 관리한다.
struct IndoorMapKitView: UIViewRepresentable {
    /// 최초 도면의 확대 배율. 1은 층 전체 맞춤이며, 1.25는 그보다 25% 크게 표시한다.
    /// 층 전환·현재 위치 포커스에는 다시 적용하지 않는다.
    static let initialZoomScale = 1.25

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
    var route: IndoorRoute?
    /// 경로 시트와 상단 위치 버튼을 제외한 영역에 도면·현재 위치를 맞춘다.
    var viewportInsets: UIEdgeInsets = .zero

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

    /// MapKit delegate·제스처를 처리하고 마지막 렌더링 값을 기억해 필요한 부분만 갱신한다.
    final class Coordinator: NSObject, MKMapViewDelegate, UIGestureRecognizerDelegate {
        var parent: IndoorMapKitView
        weak var mapView: MKMapView?
        /// 마지막으로 도형을 그린 지도·층. 위치 갱신마다 전체 도형을 다시 만드는 것을 피한다.
        var renderedMap: IndoorMap?
        var renderedFloorID: UUID?
        var selectedID: IndoorMapElement.ID?
        /// 적용을 마친 요청. 같은 요청의 반복 갱신이 사용자의 수동 이동을 덮어쓰지 않게 한다.
        var lastCameraRequest: IndoorMapCameraRequest?
        /// 화면 부착·크기 결정까지 보류한 최신 카메라 요청.
        private(set) var pendingCameraRequest: IndoorMapCameraRequest?
        private var isApplyingCamera = false
        /// MapKit overlay 객체와 원본 요소를 연결해 색상·선택 스타일을 결정한다.
        private var overlayFeatures: [ObjectIdentifier: IndoorMapElement] = [:]
        private var positionAnnotation: PositionAnnotation?
        private var renderedPosition: IndoorPosition?
        private var renderedShelves: [ShelfDestination] = []
        private var renderedRoute: IndoorRoute?
        private var routeFloorID: UUID?
        private var routeOverlays: [any MKOverlay] = []
        private var routeOverlayIDs = Set<ObjectIdentifier>()
        private var routeTransitionAnnotations: [IndoorRouteTransitionAnnotation] = []

        init(parent: IndoorMapKitView) { self.parent = parent }

        /// 기본 지도·줌 허용 범위·제스처와 배치 콜백을 설정한다.
        ///
        /// 카메라 거리의 최소·최대값은 아래 `setCameraZoomRange`에서 미터 단위로 설정한다.
        /// 이 값은 확대·축소의 제한이며,
        /// 최초 줌은 `initialZoomScale`과 `moveCamera(_:in:animated:)`의 도면 맞춤에서 정한다.
        /// 층 전환은 도형만 갱신하고 카메라는 유지한다.
        /// - Returns: SwiftUI 배치가 끝난 시점을 알려줄 수 있는 ``IndoorMapSurface``.
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

        /// 새 SwiftUI 값과 캐시를 비교해 도면·위치·서가·경로·선택을 갱신한다.
        /// 카메라는 새 요청일 때만 배치 이후 적용하도록 보류한다.
        func update(parent: IndoorMapKitView, in view: MKMapView) {
            self.parent = parent
            if renderedMap != parent.map || renderedFloorID != parent.floor.id {
                render(in: view)
            }
            view.showsUserLocation = parent.showsUserLocation
            updatePosition(in: view)
            updateShelves(in: view)
            updateRoute(in: view)
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

        /// 계산된 경로 중 조회 층의 선·통로 연결점·층 이동 진입 및 출구만 표시한다.
        /// 이 메서드는 경로를 계산하거나 도착을 판정하지 않는다.
        private func updateRoute(in view: MKMapView) {
            guard renderedRoute != parent.route || routeFloorID != parent.floor.id else { return }
            view.removeOverlays(routeOverlays)
            view.removeAnnotations(routeTransitionAnnotations)
            routeOverlays.removeAll()
            routeOverlayIDs.removeAll()
            routeTransitionAnnotations.removeAll()
            renderedRoute = parent.route
            routeFloorID = parent.floor.id
            guard let route = parent.route else { return }
            for segment in route.segments where segment.floorID == parent.floor.id && segment.coordinates.count >= 2 {
                let points = segment.coordinates.map(\.clCoordinate)
                routeOverlays.append(MKPolyline(coordinates: points, count: points.count))
            }
            if route.start.floorID == parent.floor.id {
                routeOverlays.append(MKCircle(center: route.start.routeCoordinate.clCoordinate, radius: 1))
            }
            for change in route.floorChanges {
                if change.fromFloorID == parent.floor.id {
                    routeTransitionAnnotations.append(.init(change: change, isEntry: true))
                }
                if change.toFloorID == parent.floor.id {
                    routeTransitionAnnotations.append(.init(change: change, isEntry: false))
                }
            }
            routeOverlayIDs = Set(routeOverlays.map { ObjectIdentifier($0) })
            view.addOverlays(routeOverlays, level: .aboveLabels)
            view.addAnnotations(routeTransitionAnnotations)
        }

        /// 조회 층의 서가 핀을 갱신하고 선택 색상과 MapKit의 선택 상태를 맞춘다.
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
            for case let annotation as IndoorShelfAnnotation in view.selectedAnnotations
                where annotation.destination.key != parent.selectedShelfKey {
                view.deselectAnnotation(annotation, animated: false)
            }
        }

        /// 화면에 붙고 유효한 크기를 가진 뒤 최신 보류 요청을 한 번 적용한다.
        /// 적용할 수 없으면 요청을 소비하지 않아 다음 layout에서 다시 처리할 수 있다.
        private func applyPendingCamera(in view: MKMapView) {
            guard !isApplyingCamera, view.window != nil, view.bounds.width > 0, view.bounds.height > 0,
                  let request = pendingCameraRequest else { return }
            isApplyingCamera = true
            defer { isApplyingCamera = false }
            guard moveCamera(request, in: view) else { return }
            lastCameraRequest = request
            pendingCameraRequest = nil
        }

        /// View 제거 시 참조와 보류 요청을 해제해 종료된 화면에 카메라 작업이 남지 않게 한다.
        func detachMapView() {
            mapView = nil
            pendingCameraRequest = nil
        }

        /// 조회 층이 바뀌면 층 외곽·unit·section·fixture·opening과 시설 핀을 다시 구성한다.
        /// 서가·현재 위치·경로 표시는 별도의 갱신 메서드에서 이어서 반영한다.
        func render(in view: MKMapView) {
            view.removeOverlays(view.overlays)
            view.removeAnnotations(routeTransitionAnnotations)
            routeTransitionAnnotations.removeAll()
            routeOverlays.removeAll()
            routeOverlayIDs.removeAll()
            routeFloorID = nil
            view.removeAnnotations(view.annotations.filter { $0 is FeatureAnnotation })
            overlayFeatures.removeAll()
            renderedMap = parent.map
            renderedFloorID = parent.floor.id
            selectedID = parent.selectedFeatureID
            for overlay in MapKitGeometry.overlays(for: parent.floor.geometry) {
                view.addOverlay(overlay, level: .aboveRoads)
            }
            let features = parent.map.features.filter { $0.floorID == parent.floor.id }
            // unit과 section을 먼저 그리고 그 위에 fixture와 opening을 올린다.
            for kind in [IndoorMapElement.Kind.unit, .section, .fixture, .opening] {
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

        /// 조회 층의 합성·재생·수동 위치만 별도 마커로 표시한다.
        /// 센서 위치는 MapKit 기본 사용자 위치에 맡기며 같은 출처의 이동은 기존 annotation을 갱신한다.
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

        /// 최초 확대·층 전체 맞춤 또는 특정 좌표 중심 이동을 명시적으로 적용한다.
        ///
        /// 최초 표시만 도형의 중심을 기준으로 `initialZoomScale`만큼 확대한다.
        /// 층 전체 맞춤은 원본 범위와 padding으로 줌을 계산하고, 위치 이동은 기존 줌을 유지한다.
        /// 요청 적용 시 평면으로 돌리며, 일반 층 전환에서는 이 메서드를 호출하지 않는다.
        /// - Parameters:
        ///   - request: TCA에서 전달한 최초 확대, 층 맞춤 또는 좌표 이동 요청.
        ///   - view: 이동할 MapKit 화면.
        ///   - animated: 좌표 중심 이동의 애니메이션 여부. 층 전체 맞춤은 즉시 적용한다.
        /// - Returns: 요청을 적용했으면 true, 공간·대상·좌표가 유효하지 않아 보류해야 하면 false.
        @discardableResult
        func moveCamera(_ request: IndoorMapCameraRequest, in view: MKMapView, animated: Bool = true) -> Bool {
            switch request.target {
            case .initialFloor(let id), .floor(let id):
                let padding = UIEdgeInsets(
                    top: 24 + parent.viewportInsets.top, left: 80 + parent.viewportInsets.left,
                    bottom: 24 + parent.viewportInsets.bottom, right: 24 + parent.viewportInsets.right
                )
                guard view.bounds.width > padding.left + padding.right,
                      view.bounds.height > padding.top + padding.bottom,
                      let floor = parent.map.floors.first(where: { $0.id == id }) else { return false }
                var rect = MapKitGeometry.mapRect(for: floor.geometry)
                guard !rect.isNull else { return false }
                if case .initialFloor = request.target {
                    let insetRatio = (1 - 1 / IndoorMapKitView.initialZoomScale) / 2
                    rect = rect.insetBy(dx: rect.width * insetRatio, dy: rect.height * insetRatio)
                }
                let camera = view.camera.copy() as! MKMapCamera
                camera.pitch = 0
                view.setCamera(camera, animated: false)
                view.setVisibleMapRect(rect, edgePadding: padding, animated: false)
            case .position(let coordinate):
                guard coordinate.isValid else { return false }
                let viewport = view.bounds.inset(by: parent.viewportInsets)
                guard viewport.width > 0, viewport.height > 0 else { return false }
                // 평면으로 돌린 뒤, 시트에 가리지 않는 화면 중심으로 좌표를 이동한다.
                let flatCamera = view.camera.copy() as! MKMapCamera
                flatCamera.pitch = 0
                view.setCamera(flatCamera, animated: false)
                let point = view.convert(coordinate.clCoordinate, toPointTo: view)
                // MKMapView의 카메라 중심은 safe area에 따라 bounds의 중심과 다를 수 있다.
                let cameraCenter = view.convert(view.centerCoordinate, toPointTo: view)
                let center = CGPoint(
                    x: point.x + cameraCenter.x - viewport.midX,
                    y: point.y + cameraCenter.y - viewport.midY
                )
                view.setCenter(view.convert(center, toCoordinateFrom: view), animated: animated)
            }
            return true
        }

        /// overlay의 도형 종류에 맞는 renderer를 만들고 경로·시설·선택 스타일을 적용한다.
        func mapView(_ mapView: MKMapView, rendererFor overlay: any MKOverlay) -> MKOverlayRenderer {
            let renderer: MKOverlayPathRenderer
            if let polygon = overlay as? MKPolygon { renderer = MKPolygonRenderer(polygon: polygon) }
            else if let line = overlay as? MKPolyline { renderer = MKPolylineRenderer(polyline: line) }
            else if let circle = overlay as? MKCircle { renderer = MKCircleRenderer(circle: circle) }
            else { return MKOverlayRenderer(overlay: overlay) }
            style(renderer, overlay: overlay)
            return renderer
        }

        /// 경로는 파란색으로 구분하고 도면 요소에는 종류별 색상과 선택 강조를 적용한다.
        func style(_ renderer: MKOverlayPathRenderer, overlay: any MKOverlay) {
            if routeOverlayIDs.contains(ObjectIdentifier(overlay)) {
                renderer.strokeColor = .systemBlue
                renderer.fillColor = UIColor.systemBlue.withAlphaComponent(0.25)
                renderer.lineWidth = overlay is MKPolyline ? 5 : 2
                renderer.lineCap = .round
                renderer.lineJoin = .round
                return
            }
            let feature = overlayFeatures[ObjectIdentifier(overlay)]
            renderer.lineWidth = feature?.kind == .opening ? 2 : 0.8
            renderer.strokeColor = .systemGray2
            switch feature?.kind {
            case .fixture: renderer.fillColor = UIColor(red: 0.83, green: 0.73, blue: 0.57, alpha: 1)
            case .section:
                renderer.fillColor = UIColor.systemGray5.withAlphaComponent(0.35)
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

        /// 층 이동·시뮬레이션 위치·서가·일반 시설을 서로 다른 마커로 표시한다.
        /// 기본 사용자 위치는 nil을 반환해 MapKit의 표시를 사용한다.
        func mapView(_ mapView: MKMapView, viewFor annotation: any MKAnnotation) -> MKAnnotationView? {
            if annotation is MKUserLocation { return nil }
            if let annotation = annotation as? IndoorRouteTransitionAnnotation {
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: "route-transition")
                    ?? MKAnnotationView(annotation: annotation, reuseIdentifier: "route-transition")
                view.annotation = annotation
                view.image = annotation.markerImage
                view.centerOffset = .zero
                view.collisionMode = .circle
                view.displayPriority = .required
                view.clusteringIdentifier = nil
                view.isEnabled = false
                view.isAccessibilityElement = true
                view.accessibilityLabel = annotation.title
                view.accessibilityValue = annotation.subtitle
                view.accessibilityIdentifier = "route-transition-\(annotation.category.rawValue)"
                return view
            }
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

        /// 지도 탭을 좌표로 바꾸고 가까운 시설 핀, 포함하는 fixture, unit 순으로 선택 대상을 찾는다.
        /// 수동 출발점 배치 모드에서는 요소 선택 대신 좌표 콜백만 전달한다.
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

        /// annotation 주변의 탭이 지도 바닥 선택으로 중복 처리되지 않도록 제외한다.
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
    /// 유효한 window·크기 여부를 Coordinator가 판단할 수 있도록 배치 이후 호출한다.
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

/// 점 geometry로 제공된 시설의 원본 요소와 MapKit 표시 좌표를 연결한다.
private final class FeatureAnnotation: NSObject, MKAnnotation {
    let feature: IndoorMapElement
    let coordinate: CLLocationCoordinate2D
    var title: String? { feature.name ?? feature.category ?? "시설" }
    init(feature: IndoorMapElement, coordinate: CLLocationCoordinate2D) {
        self.feature = feature
        self.coordinate = coordinate
    }
}

/// 센서의 기본 사용자 위치와 구분해 합성·재생·수동 위치를 표시하는 annotation.
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
