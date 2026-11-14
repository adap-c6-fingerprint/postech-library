import MapKit
import os
import SwiftUI
import Clarity

struct IndoorMapKitView: UIViewRepresentable {
    enum Appearance: Equatable {
        case standard, home, bookDetail

        var usesHomeStyle: Bool { self != .standard }
    }
    static let bookDetailMinimumSpanMeters = 20.0
    static let cameraBoundaryMarginMeters = 30.0
    static let maxZoomOutBuildingRatio = 4.0

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
    var entranceApproach: LibraryEntranceApproach?
    var viewportInsets: UIEdgeInsets = .zero
    var shelfLabels: [IndoorShelfLabel] = []
    var highlightedFeatureIDs: Set<IndoorMapElement.ID> = []
    var routeTurnArrows: [RouteTurnArrow] = []
    var navigationAppearance = false
    var navigationDestination: BookNavigationMapDestination?
    var onUserCameraInteraction: () -> Void = {}
    var onCenterChanged: ((IndoorMapCoordinate, Bool) -> Void)?
    var appearance: Appearance = .standard
    var homeMarkers: [HomeMapMarker] = []
    var onSelectFavoriteMarker: (HomeMapMarker) -> Void = { _ in }
    var detailShelfLabels: [IndoorShelfLabel] = []

    var visibleEntranceApproach: LibraryEntranceApproach? {
        entranceApproach?.entrance.floorOrdinal == floor.ordinal ? entranceApproach : nil
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> IndoorMapSurface {
        let signpostState = MapPerformanceSignpost.signposter.beginInterval("MapViewCreate", "\(String(describing: appearance), privacy: .public)")
        defer { MapPerformanceSignpost.signposter.endInterval("MapViewCreate", signpostState) }
        let view = context.coordinator.makeMapView()
        ClaritySDK.unmaskView(view)
        return view
    }

    func updateUIView(_ view: IndoorMapSurface, context: Context) {
        let signpostState = MapPerformanceSignpost.signposter.beginInterval("MapUpdate", "\(String(describing: appearance), privacy: .public)")
        defer { MapPerformanceSignpost.signposter.endInterval("MapUpdate", signpostState) }
        context.coordinator.update(parent: self, in: view)
    }

    static func dismantleUIView(_ view: IndoorMapSurface, coordinator: Coordinator) {
        view.hidesSystemTopEdgeEffect = false
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
        private var highlightedIDs: Set<IndoorMapElement.ID> = []
        private var renderedAppearance: Appearance = .standard
        var lastCameraRequest: IndoorMapCameraRequest?
        private(set) var pendingCameraRequest: IndoorMapCameraRequest?
        private var isApplyingCamera = false
        private var isMakingMapView = false
        private var overlayStyles: [ObjectIdentifier: IndoorOverlayStyle] = [:]
        private var highlightOverlays: [any MKOverlay] = []
        /// 기본 도형에서 빼고 강조 도형으로만 그린 요소. 반투명 강조가 기본 도형 위에 겹쳐 색이 달라지지 않게 한다.
        private var baseExcludedIDs: Set<IndoorMapElement.ID> = []
        private var pendingOverlayRedrawIDs = Set<ObjectIdentifier>()
        private var readyOverlayRenderers: [ObjectIdentifier: MKOverlayRenderer] = [:]
        private var overlayRedrawTask: Task<Void, Never>?
        private var overlayGeneration = 0
        private var positionAnnotation: PositionAnnotation?
        private var renderedPosition: IndoorPosition?
        private var renderedPositionAppearance: Appearance?
        private var renderedPositionNavigationAppearance = false
        private var renderedShelves: [ShelfDestination] = []
        private let shelfLabelController = IndoorShelfLabelController()
        private var renderedDetailShelfLabels: [IndoorShelfLabel] = []
        private let homeAnnotations = HomeMapAnnotationController()
        private var renderedRoute: IndoorRoute?
        private var renderedEntranceApproach: LibraryEntranceApproach?
        private var entranceApproachOverlay: MKPolyline?
        private var renderedTurnArrows: [RouteTurnArrow] = []
        private var renderedNavigationAppearance = false
        private var renderedNavigationDestination: BookNavigationMapDestination?
        private var turnArrowOverlays: [MKPolyline] = []
        private var turnArrowOverlayIDs = Set<ObjectIdentifier>()
        private var routeFloorID: UUID?
        private var routeOverlays: [any MKOverlay] = []
        private var routeOverlayIDs = Set<ObjectIdentifier>()
        private var routeTransitionAnnotations: [IndoorRouteTransitionAnnotation] = []

        init(parent: IndoorMapKitView) { self.parent = parent }

        func makeMapView() -> IndoorMapSurface {
            isMakingMapView = true
            defer { isMakingMapView = false }
            let view = IndoorMapSurface()
            view.hidesSystemTopEdgeEffect = parent.appearance == .bookDetail
            view.delegate = self
            view.overrideUserInterfaceStyle = .dark
            let configuration = MKStandardMapConfiguration(elevationStyle: .flat)
            configuration.pointOfInterestFilter = .excludingAll
            view.preferredConfiguration = configuration
            view.isPitchEnabled = true
            view.isRotateEnabled = true
            view.showsCompass = false
            view.showsScale = false
            view.setCameraZoomRange(MKMapView.CameraZoomRange(minCenterCoordinateDistance: 5, maxCenterCoordinateDistance: 5_000), animated: false)
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
            view.onLayout = { [weak self] view in
                self?.applyPendingCamera(in: view)
                self?.layoutShelfLabels(in: view)
                self?.scheduleOverlayRedraw(in: view)
            }
            mapView = view
            return view
        }

        func update(parent: IndoorMapKitView, in view: MKMapView) {
            self.parent = parent
            (view as? IndoorMapSurface)?.hidesSystemTopEdgeEffect = parent.appearance == .bookDetail
            if renderedMap != parent.map || renderedFloorID != parent.floor.id
                || renderedNavigationAppearance != parent.navigationAppearance
                || renderedAppearance != parent.appearance {
                render(in: view)
            }
            view.overrideUserInterfaceStyle = .dark
            view.showsUserLocation = parent.showsUserLocation && !parent.appearance.usesHomeStyle
            updatePosition(in: view)
            updatePositionMarkerBearing(in: view)
            updateShelves(in: view)
            homeAnnotations.update(parent.appearance.usesHomeStyle
                ? parent.homeMarkers.filter { $0.floorID == parent.floor.id } : [], in: view)
            updateShelfLabels(in: view)
            updateDetailShelfBadges(in: view)
            updateRoute(in: view)
            updateEntranceApproach(in: view)
            if selectedID != parent.selectedFeatureID || highlightedIDs != parent.highlightedFeatureIDs {
                selectedID = parent.selectedFeatureID
                highlightedIDs = parent.highlightedFeatureIDs
                if baseExcludedIDs.isSubset(of: emphasizedIDs) {
                    updateHighlightOverlays(in: view)
                } else {
                    render(in: view)
                }
                layoutShelfLabels(in: view)
            }
            pendingCameraRequest = parent.cameraRequest == lastCameraRequest ? nil : parent.cameraRequest
            if pendingCameraRequest != nil { view.setNeedsLayout() }
        }

        private func updateRoute(in view: MKMapView) {
            guard renderedRoute != parent.route || routeFloorID != parent.floor.id
                || renderedTurnArrows != parent.routeTurnArrows
                || renderedNavigationDestination != parent.navigationDestination else { return }
            view.removeOverlays(routeOverlays)
            view.removeOverlays(turnArrowOverlays)
            view.removeAnnotations(routeTransitionAnnotations)
            view.removeAnnotations(view.annotations.filter {
                $0 is BookNavigationDestinationAnnotation || $0 is BookNavigationStartAnnotation
            })
            routeOverlays.removeAll()
            turnArrowOverlays.removeAll()
            turnArrowOverlayIDs.removeAll()
            routeOverlayIDs.removeAll()
            routeTransitionAnnotations.removeAll()
            renderedRoute = parent.route
            renderedTurnArrows = parent.routeTurnArrows
            renderedNavigationDestination = parent.navigationDestination
            routeFloorID = parent.floor.id
            guard let route = parent.route else { return }
            for segment in route.segments where segment.floorID == parent.floor.id && segment.coordinates.count >= 2 {
                let points = segment.coordinates.map(\.clCoordinate)
                routeOverlays.append(MKPolyline(coordinates: points, count: points.count))
            }
            if route.start.floorID == parent.floor.id, !parent.navigationAppearance {
                routeOverlays.append(MKCircle(center: route.start.routeCoordinate.clCoordinate, radius: 1))
            }
            if parent.navigationAppearance, route.start.floorID == parent.floor.id {
                view.addAnnotation(BookNavigationStartAnnotation(coordinate: route.start.actualCoordinate))
            }
            for change in route.floorChanges {
                let from = parent.map.floors.first { $0.id == change.fromFloorID }?.ordinal
                let to = parent.map.floors.first { $0.id == change.toFloorID }?.ordinal
                let movesUp = from.flatMap { from in to.map { $0 > from } }
                if change.fromFloorID == parent.floor.id {
                    routeTransitionAnnotations.append(.init(change: change, isEntry: true, movesUp: movesUp))
                }
                if change.toFloorID == parent.floor.id {
                    routeTransitionAnnotations.append(.init(change: change, isEntry: false))
                }
            }
            for arrow in parent.routeTurnArrows where arrow.floorID == parent.floor.id
                && arrow.coordinates.count >= 2 && arrow.coordinates.allSatisfy(\.isValid) {
                let points = arrow.coordinates.map(\.clCoordinate)
                turnArrowOverlays.append(MKPolyline(coordinates: points, count: points.count))
            }
            routeOverlayIDs = Set(routeOverlays.map { ObjectIdentifier($0) })
            turnArrowOverlayIDs = Set(turnArrowOverlays.map { ObjectIdentifier($0) })
            view.addOverlays(routeOverlays, level: .aboveLabels)
            view.addOverlays(turnArrowOverlays, level: .aboveLabels)
            view.addAnnotations(routeTransitionAnnotations)
            if let destination = parent.navigationDestination, destination.floorID == parent.floor.id {
                view.addAnnotation(BookNavigationDestinationAnnotation(destination))
            }
        }

        private func updateEntranceApproach(in view: MKMapView) {
            let approach = parent.visibleEntranceApproach
            guard approach?.coordinates != renderedEntranceApproach?.coordinates else { return }
            if let entranceApproachOverlay { view.removeOverlay(entranceApproachOverlay) }
            renderedEntranceApproach = approach
            entranceApproachOverlay = nil
            guard let approach else { return }
            let points = approach.coordinates.map(\.clCoordinate)
            let line = MKPolyline(coordinates: points, count: points.count)
            entranceApproachOverlay = line
            view.addOverlay(line, level: .aboveLabels)
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
            for case let annotation as IndoorShelfAnnotation in view.selectedAnnotations
                where annotation.destination.key != parent.selectedShelfKey {
                view.deselectAnnotation(annotation, animated: false)
            }
        }

        private func updateShelfLabels(in view: MKMapView) {
            let labels = parent.appearance == .bookDetail ? [] : parent.shelfLabels.filter { $0.floorID == parent.floor.id }
            shelfLabelController.update(labels, in: view)
            layoutShelfLabels(in: view)
        }

        private func updateDetailShelfBadges(in view: MKMapView) {
            let labels = parent.detailShelfLabels.filter { $0.floorID == parent.floor.id }
            guard renderedDetailShelfLabels != labels else { return }
            renderedDetailShelfLabels = labels
            view.removeAnnotations(view.annotations.filter { $0 is BookDetailShelfBadge })
            view.addAnnotations(IndoorShelfLabelLayout(labels: labels).numbers.map { BookDetailShelfBadge($0) })
        }

        private func layoutShelfLabels(in view: MKMapView) {
            guard parent.appearance != .bookDetail else { return }
            shelfLabelController.layout(in: view, highlighted: parent.highlightedFeatureIDs)
        }

        func mapView(_ mapView: MKMapView, didAdd views: [MKAnnotationView]) {
            for view in views where view.annotation is MKUserLocation {
                view.zPriority = MapAnnotationPriority.user
                view.selectedZPriority = MapAnnotationPriority.user
            }
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            layoutShelfLabels(in: mapView)
            updatePositionMarkerBearing(in: mapView)
            reportCenter(of: mapView, isSettled: true)
        }

        func mapViewDidChangeVisibleRegion(_ mapView: MKMapView) {
            layoutShelfLabels(in: mapView)
            updatePositionMarkerBearing(in: mapView)
            reportCenter(of: mapView, isSettled: false)
        }

        private func reportCenter(of mapView: MKMapView, isSettled: Bool) {
            guard !isMakingMapView, let onCenterChanged = parent.onCenterChanged else { return }
            let center = mapView.centerCoordinate
            guard CLLocationCoordinate2DIsValid(center) else { return }
            let coordinate = IndoorMapCoordinate(latitude: center.latitude, longitude: center.longitude)
            DispatchQueue.main.async { onCenterChanged(coordinate, isSettled) }
        }

        func mapView(_ mapView: MKMapView, regionWillChangeAnimated animated: Bool) {
            guard parent.navigationAppearance, !isApplyingCamera,
                  Self.hasActiveGesture(in: mapView) else { return }
            lastCameraRequest = parent.cameraRequest
            pendingCameraRequest = nil
            parent.onUserCameraInteraction()
        }

        private static func hasActiveGesture(in view: UIView) -> Bool {
            view.gestureRecognizers?.contains { $0.state == .began || $0.state == .changed } == true
                || view.subviews.contains { hasActiveGesture(in: $0) }
        }

        func mapView(_ mapView: MKMapView, didAdd renderers: [MKOverlayRenderer]) {
            guard mapView === self.mapView else { return }
            for renderer in renderers {
                let id = ObjectIdentifier(renderer.overlay)
                if pendingOverlayRedrawIDs.contains(id) { readyOverlayRenderers[id] = renderer }
            }
            scheduleOverlayRedraw(in: mapView)
        }

        private func scheduleOverlayRedraw(in view: MKMapView) {
            guard overlayRedrawTask == nil, !readyOverlayRenderers.isEmpty,
                  view.window != nil, view.bounds.width > 0, view.bounds.height > 0,
                  pendingCameraRequest == nil, !isApplyingCamera else { return }
            let generation = overlayGeneration
            overlayRedrawTask = Task { @MainActor [weak self, weak view] in
                await Task.yield()
                guard let self, !Task.isCancelled, generation == self.overlayGeneration else { return }
                self.overlayRedrawTask = nil
                guard let view, view === self.mapView, view.window != nil,
                      view.bounds.width > 0, view.bounds.height > 0,
                      self.pendingCameraRequest == nil, !self.isApplyingCamera else { return }
                let renderers = self.readyOverlayRenderers
                self.readyOverlayRenderers.removeAll()
                MapPerformanceSignpost.signposter.emitEvent("OverlayRedraw", "renderers=\(renderers.count, privacy: .public)")
                for (id, renderer) in renderers where self.pendingOverlayRedrawIDs.remove(id) != nil {
                    renderer.setNeedsDisplay()
                }
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
            cancelOverlayRedraw()
            mapView = nil
            pendingCameraRequest = nil
        }

        private func cancelOverlayRedraw() {
            overlayGeneration += 1
            overlayRedrawTask?.cancel()
            overlayRedrawTask = nil
            pendingOverlayRedrawIDs.removeAll()
            readyOverlayRenderers.removeAll()
        }

        func render(in view: MKMapView) {
            let signpostState = MapPerformanceSignpost.signposter.beginInterval(
                "MapRender", "floor=\(self.parent.floor.name, privacy: .public) appearance=\(String(describing: self.parent.appearance), privacy: .public)")
            defer { MapPerformanceSignpost.signposter.endInterval("MapRender", signpostState, "overlays=\(view.overlays.count, privacy: .public)") }
            cancelOverlayRedraw()
            view.removeOverlays(view.overlays)
            renderedEntranceApproach = nil
            entranceApproachOverlay = nil
            view.removeAnnotations(routeTransitionAnnotations)
            routeTransitionAnnotations.removeAll()
            routeOverlays.removeAll()
            routeOverlayIDs.removeAll()
            routeFloorID = nil
            view.removeAnnotations(view.annotations.filter { $0 is FeatureAnnotation })
            overlayStyles.removeAll()
            highlightOverlays.removeAll()
            if renderedMap != parent.map { applyCameraLimits(in: view) }
            renderedMap = parent.map
            renderedFloorID = parent.floor.id
            renderedNavigationAppearance = parent.navigationAppearance
            renderedAppearance = parent.appearance
            selectedID = parent.selectedFeatureID
            highlightedIDs = parent.highlightedFeatureIDs
            baseExcludedIDs = emphasizedIDs
            var batcher = IndoorOverlayBatcher()
            batcher.append(parent.floor.geometry, style: baseStyle(for: nil))
            let features = parent.map.features.filter { $0.floorID == parent.floor.id }
            for feature in Self.orderedOverlayFeatures(features) where !baseExcludedIDs.contains(feature.id) {
                batcher.append(feature.geometry, style: baseStyle(for: feature))
            }
            let overlays = register(batcher.finish())
            pendingOverlayRedrawIDs = Set(overlays.map { ObjectIdentifier($0) })
            view.addOverlays(overlays, level: .aboveRoads)
            updateHighlightOverlays(in: view)
            view.addAnnotations(features.compactMap { feature in
                guard !parent.appearance.usesHomeStyle, feature.kind == .amenity,
                      case .point(let coordinate) = feature.geometry else { return nil }
                return FeatureAnnotation(feature: feature, coordinate: coordinate.clCoordinate)
            })
        }

        private static let overlayKinds: [IndoorMapElement.Kind] = [.unit, .section, .fixture, .opening]

        /// 기존과 같은 그리기 순서(unit → section → fixture → opening, 같은 종류 안에서는 원래 순서)를 만든다.
        private static func orderedOverlayFeatures(_ features: [IndoorMapElement]) -> [IndoorMapElement] {
            overlayKinds.flatMap { kind in features.filter { $0.kind == kind } }
        }

        /// 강조 또는 선택으로 기본과 다르게 그려야 하는 요소.
        private var emphasizedIDs: Set<IndoorMapElement.ID> {
            var ids = highlightedIDs
            if let selectedID { ids.insert(selectedID) }
            return ids
        }

        private func register(_ batches: [(overlay: any MKOverlay, style: IndoorOverlayStyle)]) -> [any MKOverlay] {
            for batch in batches { overlayStyles[ObjectIdentifier(batch.overlay)] = batch.style }
            return batches.map(\.overlay)
        }

        /// 강조·선택된 도형만 기본 도형 위에 따로 그린다. 강조가 바뀌어도 층 전체 도형을 다시 칠하지 않는다.
        private func updateHighlightOverlays(in view: MKMapView) {
            if !highlightOverlays.isEmpty {
                view.removeOverlays(highlightOverlays)
                for overlay in highlightOverlays {
                    let id = ObjectIdentifier(overlay)
                    overlayStyles[id] = nil
                    pendingOverlayRedrawIDs.remove(id)
                    readyOverlayRenderers[id] = nil
                }
                highlightOverlays.removeAll()
            }
            let emphasized = emphasizedIDs
            guard !emphasized.isEmpty else { return }
            var batcher = IndoorOverlayBatcher()
            let features = parent.map.features.filter { $0.floorID == parent.floor.id && emphasized.contains($0.id) }
            for feature in Self.orderedOverlayFeatures(features) {
                let emphasizedStyle = style(for: feature)
                guard baseExcludedIDs.contains(feature.id) || emphasizedStyle != baseStyle(for: feature) else { continue }
                batcher.append(feature.geometry, style: emphasizedStyle)
            }
            highlightOverlays = register(batcher.finish())
            guard !highlightOverlays.isEmpty else { return }
            pendingOverlayRedrawIDs.formUnion(highlightOverlays.map { ObjectIdentifier($0) })
            view.addOverlays(highlightOverlays, level: .aboveRoads)
        }

        private func applyCameraLimits(in view: MKMapView) {
            let buildingRect = parent.map.floors
                .map { MapKitGeometry.mapRect(for: $0.geometry) }
                .reduce(MKMapRect.null) { $0.union($1) }
            guard !buildingRect.isNull, buildingRect.width > 0, buildingRect.height > 0 else { return }
            let pointsPerMeter = MKMapPointsPerMeterAtLatitude(
                MKMapPoint(x: buildingRect.midX, y: buildingRect.midY).coordinate.latitude)
            let margin = IndoorMapKitView.cameraBoundaryMarginMeters * pointsPerMeter
            view.setCameraBoundary(
                MKMapView.CameraBoundary(mapRect: buildingRect.insetBy(dx: -margin, dy: -margin)), animated: false)
            let longestMeters = max(buildingRect.width, buildingRect.height) / pointsPerMeter
            let maxDistance = max(longestMeters * IndoorMapKitView.maxZoomOutBuildingRatio, 100)
            view.setCameraZoomRange(
                MKMapView.CameraZoomRange(minCenterCoordinateDistance: 5, maxCenterCoordinateDistance: maxDistance),
                animated: false)
        }

        func updatePosition(in view: MKMapView) {
            let visible = parent.position.flatMap { position -> IndoorPosition? in
                let isApproachingEntrance = parent.visibleEntranceApproach?.position == position
                guard (position.source != .sensor || parent.navigationAppearance || parent.appearance.usesHomeStyle || isApproachingEntrance),
                      position.floorOrdinal == parent.floor.ordinal
                        || isApproachingEntrance
                        || (parent.appearance == .home && position.source == .sensor && position.floorOrdinal == nil)
                else { return nil }
                return position
            }
            let styleChanged = renderedPositionAppearance != parent.appearance
                || renderedPositionNavigationAppearance != parent.navigationAppearance
            guard visible != renderedPosition || styleChanged else { return }
            renderedPosition = visible
            renderedPositionAppearance = parent.appearance
            renderedPositionNavigationAppearance = parent.navigationAppearance
            if !styleChanged, let visible, let annotation = positionAnnotation, visible.source == annotation.position.source {
                annotation.update(visible)
                return
            }
            if let annotation = positionAnnotation { view.removeAnnotation(annotation) }
            positionAnnotation = visible.map { PositionAnnotation(position: $0) }
            if let annotation = positionAnnotation { view.addAnnotation(annotation) }
        }

        private func updatePositionMarkerBearing(in map: MKMapView) {
            guard let annotation = positionAnnotation,
                  let view = map.view(for: annotation) as? MapUserLocationAnnotationView else { return }
            configurePositionBearing(view, position: annotation.position, in: map)
        }

        private func configurePositionBearing(_ view: MapUserLocationAnnotationView,
                                              position: IndoorPosition, in map: MKMapView) {
            view.configure(headingDegrees: position.headingDegrees, mapHeading: map.camera.heading)
        }

        private var floorFitPadding: UIEdgeInsets {
            UIEdgeInsets(
                top: 24 + parent.viewportInsets.top, left: 80 + parent.viewportInsets.left,
                bottom: 24 + parent.viewportInsets.bottom, right: 24 + parent.viewportInsets.right
            )
        }

        private func center(on coordinate: IndoorMapCoordinate, revealsShelfNumbers: Bool,
                            in view: MKMapView, animated: Bool) -> Bool {
            guard coordinate.isValid else { return false }
            let viewport = view.bounds.inset(by: parent.viewportInsets)
            guard viewport.width > 0, viewport.height > 0 else { return false }
            let startCamera = view.camera.copy() as! MKMapCamera
            let targetCamera = startCamera.copy() as! MKMapCamera
            targetCamera.pitch = 0
            view.setCamera(targetCamera, animated: false)
            if revealsShelfNumbers {
                targetCamera.heading = 0
                view.setCamera(targetCamera, animated: false)
                if let scale = IndoorShelfLabelLevel.metersPerPoint(in: view) {
                    let distance = targetCamera.centerCoordinateDistance
                        * IndoorShelfLabelLevel.numberRevealMetersPerPoint / scale
                    if distance.isFinite, distance > 0 {
                        targetCamera.centerCoordinateDistance = distance
                        view.setCamera(targetCamera, animated: false)
                    }
                }
            }
            let point = view.convert(coordinate.clCoordinate, toPointTo: view)
            let cameraCenter = view.convert(view.centerCoordinate, toPointTo: view)
            let center = CGPoint(
                x: point.x + cameraCenter.x - viewport.midX,
                y: point.y + cameraCenter.y - viewport.midY
            )
            let destination = view.convert(center, toCoordinateFrom: view)
            guard CLLocationCoordinate2DIsValid(destination) else { return true }
            if animated, !UIAccessibility.isReduceMotionEnabled {
                view.setCamera(startCamera, animated: false)
                targetCamera.centerCoordinate = destination
                view.setCamera(targetCamera, animated: true)
            } else {
                view.setCenter(destination, animated: false)
            }
            return true
        }

        @discardableResult
        func moveCamera(_ request: IndoorMapCameraRequest, in view: MKMapView, animated: Bool = true) -> Bool {
            MapPerformanceSignpost.signposter.emitEvent("CameraMove", "id=\(request.id, privacy: .public) target=\(String(String(describing: request.target).prefix(40)), privacy: .public)")
            switch request.target {
            case .navigation(let focus):
                guard focus.floorID == parent.floor.id, !focus.coordinates.isEmpty,
                      focus.coordinates.allSatisfy(\.isValid), focus.minimumSpanMeters.isFinite,
                      focus.minimumSpanMeters > 0 else { return false }
                let padding = UIEdgeInsets(top: 32 + parent.viewportInsets.top, left: 32 + parent.viewportInsets.left,
                                           bottom: 32 + parent.viewportInsets.bottom, right: 32 + parent.viewportInsets.right)
                guard view.bounds.width > padding.left + padding.right,
                      view.bounds.height > padding.top + padding.bottom else { return false }
                if view.camera.pitch != 0 {
                    let camera = view.camera.copy() as! MKMapCamera
                    camera.pitch = 0
                    view.setCamera(camera, animated: false)
                }
                guard let camera = IndoorMapCameraFitter.camera(fitting: focus.coordinates,
                    minimumSpanMeters: focus.minimumSpanMeters, in: view, padding: padding) else { return false }
                view.setCamera(camera, animated: animated && !UIAccessibility.isReduceMotionEnabled)
            case .initialFloor(let id), .floor(let id):
                let padding = floorFitPadding
                guard view.bounds.width > padding.left + padding.right,
                      view.bounds.height > padding.top + padding.bottom,
                      let floor = parent.map.floors.first(where: { $0.id == id }) else { return false }
                let rect = MapKitGeometry.mapRect(for: floor.geometry)
                guard !rect.isNull else { return false }
                let camera = view.camera.copy() as! MKMapCamera
                camera.pitch = 0
                view.setCamera(camera, animated: false)
                view.setVisibleMapRect(rect, edgePadding: padding, animated: false)
                if case .initialFloor = request.target {
                    let floorCenter = MKMapPoint(x: rect.midX, y: rect.midY).coordinate
                    return center(on: .init(latitude: floorCenter.latitude, longitude: floorCenter.longitude),
                                  revealsShelfNumbers: true, in: view, animated: false)
                }
            case .position(let coordinate, let revealsShelfNumbers):
                return center(on: coordinate, revealsShelfNumbers: revealsShelfNumbers, in: view, animated: animated)
            case .route(let route, let ids):
                var rect = parent.map.features.filter { ids.contains($0.id) && $0.floorID == parent.floor.id }
                    .reduce(MKMapRect.null) { $0.union(MapKitGeometry.mapRect(for: $1.geometry)) }
                for segment in route.segments where segment.floorID == parent.floor.id {
                    rect = rect.union(MapKitGeometry.mapRect(for: .lineString(segment.coordinates)))
                }
                if route.start.floorID == parent.floor.id {
                    rect = rect.union(MapKitGeometry.mapRect(for: .point(route.start.actualCoordinate)))
                }
                if let approach = parent.visibleEntranceApproach {
                    rect = rect.union(MapKitGeometry.mapRect(for: .lineString(approach.coordinates)))
                }
                guard !rect.isNull else { return false }
                let padding = UIEdgeInsets(top: 32 + parent.viewportInsets.top, left: 32 + parent.viewportInsets.left,
                                           bottom: 32 + parent.viewportInsets.bottom, right: 32 + parent.viewportInsets.right)
                guard view.bounds.width > padding.left + padding.right,
                      view.bounds.height > padding.top + padding.bottom else { return false }
                let margin = MKMapPointsPerMeterAtLatitude(MKMapPoint(x: rect.midX, y: rect.midY).coordinate.latitude) * 4
                let camera = view.camera.copy() as! MKMapCamera
                camera.pitch = 0
                view.setCamera(camera, animated: false)
                view.setVisibleMapRect(rect.insetBy(dx: -margin, dy: -margin), edgePadding: padding, animated: false)
            case .features(let ids):
                let features = parent.map.features.filter { ids.contains($0.id) && $0.floorID == parent.floor.id }
                guard !features.isEmpty else { return false }
                let rect = features.reduce(MKMapRect.null) { $0.union(MapKitGeometry.mapRect(for: $1.geometry)) }
                guard !rect.isNull else { return false }
                let padding = UIEdgeInsets(top: 32 + parent.viewportInsets.top, left: 32 + parent.viewportInsets.left,
                                           bottom: 32 + parent.viewportInsets.bottom, right: 32 + parent.viewportInsets.right)
                guard view.bounds.width > padding.left + padding.right,
                      view.bounds.height > padding.top + padding.bottom else { return false }
                let margin = MKMapPointsPerMeterAtLatitude(MKMapPoint(x: rect.midX, y: rect.midY).coordinate.latitude) * 8
                let camera = view.camera.copy() as! MKMapCamera
                camera.pitch = 0
                view.setCamera(camera, animated: false)
                if parent.appearance == .bookDetail {
                    guard let camera = IndoorMapCameraFitter.camera(fitting: features.flatMap { $0.geometry.coordinates },
                        minimumSpanMeters: IndoorMapKitView.bookDetailMinimumSpanMeters,
                        in: view, padding: padding) else { return false }
                    view.setCamera(camera, animated: false)
                    return true
                }
                view.setVisibleMapRect(rect.insetBy(dx: -margin, dy: -margin), edgePadding: padding, animated: false)
            }
            return true
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: any MKOverlay) -> MKOverlayRenderer {
            let renderer: MKOverlayPathRenderer
            if let polygon = overlay as? MKPolygon { renderer = MKPolygonRenderer(polygon: polygon) }
            else if let polygons = overlay as? MKMultiPolygon { renderer = MKMultiPolygonRenderer(multiPolygon: polygons) }
            else if let lines = overlay as? MKMultiPolyline { renderer = MKMultiPolylineRenderer(multiPolyline: lines) }
            else if let line = overlay as? MKPolyline {
                if isEntranceApproachOverlay(overlay)
                    || (parent.navigationAppearance && routeOverlayIDs.contains(ObjectIdentifier(overlay))) {
                    let dotted = NavigationDottedRouteRenderer(polyline: line)
                    dotted.shouldRasterize = true
                    renderer = dotted
                } else {
                    renderer = MKPolylineRenderer(polyline: line)
                }
            }
            else if let circle = overlay as? MKCircle { renderer = MKCircleRenderer(circle: circle) }
            else { return MKOverlayRenderer(overlay: overlay) }
            style(renderer, overlay: overlay)
            return renderer
        }

        private func isEntranceApproachOverlay(_ overlay: any MKOverlay) -> Bool {
            guard let entranceApproachOverlay else { return false }
            return overlay === entranceApproachOverlay
        }

        func style(_ renderer: MKOverlayPathRenderer, overlay: any MKOverlay) {
            if turnArrowOverlayIDs.contains(ObjectIdentifier(overlay)) {
                renderer.strokeColor = parent.navigationAppearance ? .white : .systemYellow
                renderer.fillColor = .clear
                renderer.lineWidth = 5
                renderer.lineCap = .round
                renderer.lineJoin = .round
                return
            }
            if routeOverlayIDs.contains(ObjectIdentifier(overlay)) || isEntranceApproachOverlay(overlay) {
                let usesNavigationStyle = parent.navigationAppearance || isEntranceApproachOverlay(overlay)
                renderer.strokeColor = usesNavigationStyle ? BookNavigationPalette.uiAccent : .systemBlue
                renderer.fillColor = renderer.strokeColor?.withAlphaComponent(0.25)
                renderer.lineWidth = overlay is MKPolyline ? (usesNavigationStyle ? 7 : 5) : 2
                renderer.lineCap = .round
                renderer.lineJoin = .round
                if usesNavigationStyle, overlay is MKPolyline {
                    renderer.lineWidth = 5
                    renderer.lineDashPattern = [0, 9]
                }
                return
            }
            (overlayStyles[ObjectIdentifier(overlay)] ?? baseStyle(for: nil)).apply(to: renderer)
        }

        private func baseStyle(for feature: IndoorMapElement?) -> IndoorOverlayStyle {
            style(for: feature, isHighlighted: false, isSelected: false)
        }

        private func style(for feature: IndoorMapElement) -> IndoorOverlayStyle {
            style(for: feature, isHighlighted: highlightedIDs.contains(feature.id), isSelected: feature.id == selectedID)
        }

        private func style(for feature: IndoorMapElement?, isHighlighted: Bool, isSelected: Bool) -> IndoorOverlayStyle {
            var style = IndoorOverlayStyle()
            if parent.navigationAppearance {
                style.strokeColor = UIColor(white: 0.12, alpha: 1)
                style.lineWidth = 0.5
                let shade: CGFloat = feature?.kind == .fixture ? 0.09 : (feature?.category == "walkway" ? 0.22 : 0.17)
                style.fillColor = UIColor(white: shade, alpha: 1)
                IndoorMapPalette.apply(to: &style, feature: feature, floorOrdinal: parent.floor.ordinal)
                if isHighlighted {
                    style.fillColor = BookNavigationPalette.uiAccent
                    style.strokeColor = BookNavigationPalette.uiAccent
                }
                return style
            }
            if parent.appearance.usesHomeStyle {
                style.strokeColor = UIColor(white: 0.12, alpha: 1)
                style.lineWidth = 0.8
                switch feature?.kind {
                case .fixture: style.fillColor = UIColor(white: 0.09, alpha: 1)
                case .unit: style.fillColor = UIColor(white: feature?.category == "walkway" ? 0.23 : 0.29, alpha: 1)
                case .opening:
                    style.fillColor = .clear
                    style.strokeColor = UIColor(white: 0.35, alpha: 1)
                default: style.fillColor = UIColor(white: 0.23, alpha: 1)
                }
                IndoorMapPalette.apply(to: &style, feature: feature, floorOrdinal: parent.floor.ordinal)
                if isHighlighted {
                    style.fillColor = BookNavigationPalette.uiAccent
                    style.strokeColor = BookNavigationPalette.uiAccent
                    style.lineWidth = 3
                }
                return style
            }
            style.lineWidth = feature?.kind == .opening ? 2 : 0.8
            style.strokeColor = .systemGray2
            switch feature?.kind {
            case .fixture: style.fillColor = UIColor(red: 0.83, green: 0.73, blue: 0.57, alpha: 1)
            case .section:
                style.fillColor = UIColor.systemGray5.withAlphaComponent(0.35)
            case .unit:
                style.fillColor = feature?.category == "walkway" ? .systemGray6 : .white
                if feature?.category == "stairs" { style.fillColor = UIColor.systemPurple.withAlphaComponent(0.12) }
                if feature?.category == "elevator" { style.fillColor = UIColor.systemBlue.withAlphaComponent(0.15) }
            case .opening:
                style.strokeColor = .white
            default: style.fillColor = UIColor.systemGray6.withAlphaComponent(0.95)
            }
            IndoorMapPalette.apply(to: &style, feature: feature, floorOrdinal: parent.floor.ordinal)
            if isSelected {
                style.fillColor = UIColor.systemTeal.withAlphaComponent(0.35)
                style.strokeColor = .systemTeal
                style.lineWidth = 2
            }
            return style
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: any MKAnnotation) -> MKAnnotationView? {
            if annotation is MKUserLocation { return nil }
            if let badge = annotation as? BookDetailShelfBadge {
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: BookDetailShelfBadgeView.reuseID)
                    as? BookDetailShelfBadgeView
                    ?? BookDetailShelfBadgeView(annotation: badge, reuseIdentifier: BookDetailShelfBadgeView.reuseID)
                view.configure(badge)
                return view
            }
            if let annotation = annotation as? HomeMapPointAnnotation {
                return HomeMapAnnotationController.view(for: annotation, in: mapView)
            }
            if let annotation = annotation as? PositionAnnotation,
               parent.navigationAppearance || parent.visibleEntranceApproach?.position == annotation.position
                || (parent.appearance.usesHomeStyle && annotation.position.source != .manual) {
                let reuseID = parent.navigationAppearance ? "navigation-position" : "home-user-position"
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: reuseID) as? MapUserLocationAnnotationView
                    ?? MapUserLocationAnnotationView(annotation: annotation, reuseIdentifier: reuseID)
                view.annotation = annotation
                view.accessibilityLabel = annotation.title
                view.accessibilityValue = parent.visibleEntranceApproach != nil
                    ? "도서관 밖 현재 위치, 점선을 따라 주출입구로 이동"
                    : (parent.navigationAppearance ? "기기 방향" : nil)
                view.accessibilityIdentifier = parent.navigationAppearance ? "book-navigation-position"
                    : "user-position"
                configurePositionBearing(view, position: annotation.position, in: mapView)
                return view
            }
            if annotation is BookNavigationDestinationAnnotation || annotation is BookNavigationStartAnnotation {
                let isStart = annotation is BookNavigationStartAnnotation
                let reuseID = isStart ? "navigation-start-pin" : "navigation-end-pin"
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: reuseID)
                    ?? MKAnnotationView(annotation: annotation, reuseIdentifier: reuseID)
                view.annotation = annotation
                view.image = UIImage(named: isStart ? "MapLocationStart" : "MapLocationEnd")
                view.centerOffset = CGPoint(x: 0, y: -16)
                view.displayPriority = .required
                view.zPriority = MapAnnotationPriority.route
                view.selectedZPriority = MapAnnotationPriority.route
                view.collisionMode = .rectangle
                view.clusteringIdentifier = nil
                view.isEnabled = false
                view.isAccessibilityElement = true
                let destinationTitle = (annotation.title ?? nil) ?? "도서"
                view.accessibilityLabel = isStart ? "출발 위치" : "목적지: \(destinationTitle)"
                view.accessibilityIdentifier = isStart ? "book-navigation-start" : "book-navigation-destination"
                return view
            }
            if let annotation = annotation as? IndoorShelfLabelAnnotation {
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: IndoorShelfLabelView.reuseID)
                    as? IndoorShelfLabelView
                    ?? IndoorShelfLabelView(annotation: annotation, reuseIdentifier: IndoorShelfLabelView.reuseID)
                view.configure(annotation, highlighted: annotation.presentation.isHighlighted(by: parent.highlightedFeatureIDs))
                return view
            }
            if let annotation = annotation as? IndoorRouteTransitionAnnotation {
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: "route-transition")
                    ?? MKAnnotationView(annotation: annotation, reuseIdentifier: "route-transition")
                view.annotation = annotation
                if parent.navigationAppearance, annotation.isEntry,
                   [.elevator, .stairs].contains(annotation.category), let movesUp = annotation.movesUp {
                    view.image = MapAnnotationImage.asset(named: movesUp ? "annotation_up" : "annotation_Down")
                } else {
                    view.image = annotation.markerImage
                }
                view.centerOffset = .zero
                view.zPriority = MapAnnotationPriority.route
                view.selectedZPriority = MapAnnotationPriority.route
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
            if let annotation = annotation as? IndoorShelfAnnotation {
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: "virtual-shelf") as? MKMarkerAnnotationView
                    ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: "virtual-shelf")
                view.annotation = annotation
                view.glyphImage = UIImage(systemName: "book.fill")
                view.markerTintColor = annotation.destination.key == parent.selectedShelfKey ? .systemOrange : .systemIndigo
                view.canShowCallout = true
                view.titleVisibility = .visible
                view.displayPriority = .required
                view.zPriority = MapAnnotationPriority.marker
                view.selectedZPriority = MapAnnotationPriority.marker
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
            view.zPriority = MapAnnotationPriority.marker
            view.selectedZPriority = MapAnnotationPriority.marker
            view.clusteringIdentifier = nil
            if let annotation = annotation as? FeatureAnnotation {
                view.glyphImage = UIImage(systemName: Self.symbol(for: annotation.feature.category))
                view.markerTintColor = .systemTeal
                view.accessibilityLabel = annotation.title
            } else if let annotation = annotation as? PositionAnnotation {
                view.glyphImage = UIImage(systemName: annotation.position.source == .replay ? "play.fill" : "mappin")
                view.markerTintColor = annotation.position.source == .replay ? .systemOrange : .systemPurple
                view.displayPriority = .required
                view.zPriority = MapAnnotationPriority.user
                view.selectedZPriority = MapAnnotationPriority.user
                view.accessibilityLabel = annotation.title
            }
            return view
        }

        func mapView(_ mapView: MKMapView, didSelect annotation: any MKAnnotation) {
            if let annotation = annotation as? HomeMapPointAnnotation, annotation.marker.kind == .favorite {
                mapView.deselectAnnotation(annotation, animated: false)
                parent.onSelectFavoriteMarker(annotation.marker)
                return
            }
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

final class IndoorMapSurface: MKMapView {
    var hidesSystemTopEdgeEffect = false {
        didSet {
            guard hidesSystemTopEdgeEffect != oldValue else { return }
            updateSystemTopEdgeEffect()
            setNeedsLayout()
        }
    }
    private var suppressedTopEdgeInteraction: (any UIInteraction)?

    var onLayout: ((IndoorMapSurface) -> Void)?

    override func layoutSubviews() {
        super.layoutSubviews()
        updateSystemTopEdgeEffect()
        onLayout?(self)
    }

    private func updateSystemTopEdgeEffect() {
        if hidesSystemTopEdgeEffect {
            guard let interaction = interactions.first(where: {
                String(describing: type(of: $0)) == "_UIScrollEdgeEffectViewInteraction"
            }) else { return }
            removeInteraction(interaction)
            suppressedTopEdgeInteraction = interaction
        } else if let interaction = suppressedTopEdgeInteraction {
            suppressedTopEdgeInteraction = nil
            addInteraction(interaction)
        }
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
        case .sensor: "현재 위치"
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

final class IndoorShelfAnnotation: NSObject, MKAnnotation {
    let destination: ShelfDestination
    var coordinate: CLLocationCoordinate2D { destination.arrivalCoordinate.clCoordinate }
    var title: String? { destination.name }
    var subtitle: String? { "테스트용 가상 서가" }
    init(destination: ShelfDestination) { self.destination = destination }
}
