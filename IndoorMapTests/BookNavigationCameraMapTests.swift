import MapKit
import Testing
import UIKit
@testable import fingerprint_library

extension IndoorMapSerialTests {
    @MainActor
    struct BookNavigationCameraMapTests {
        private typealias F = NavigationGuidanceTestFixture

        @Test("접근하면 실제 지도도 확대되고 사용자·서가는 안내 UI에 가리지 않는다",
              arguments: [(390.0, 800.0), (844.0, 390.0)], [0.0, 40.0])
        func fitsVisibleArea(size: (Double, Double), heading: Double) throws {
            var parent = try parent()
            parent.viewportInsets = .init(top: min(280, size.1 * 0.35), left: 0, bottom: 90, right: 0)
            let coordinator = IndoorMapKitView.Coordinator(parent: parent)
            let view = coordinator.makeMapView()
            coordinator.update(parent: parent, in: view)
            let window = try host(view, size: CGSize(width: size.0, height: size.1))
            defer { window.isHidden = true; coordinator.detachMapView() }
            let camera = view.camera.copy() as! MKMapCamera
            camera.heading = heading
            view.setCamera(camera, animated: false)
            let destination = F.position(x: 60).coordinate
            var previousWidth = Double.infinity
            for (index, x) in [0.0, 30, 55].enumerated() {
                let user = F.position(x: x).coordinate
                let focus = BookNavigationCameraFocus(floorID: parent.floor.id,
                    coordinates: [user, destination], minimumSpanMeters: 12)
                #expect(coordinator.moveCamera(.init(id: index + 10, target: .navigation(focus)),
                                               in: view, animated: false))
                let viewport = view.bounds.inset(by: parent.viewportInsets)
                for coordinate in [user, destination] {
                    let point = view.convert(coordinate.clCoordinate, toPointTo: view)
                    #expect(viewport.insetBy(dx: 2, dy: 2).contains(point))
                }
                #expect(view.visibleMapRect.width < previousWidth)
                previousWidth = view.visibleMapRect.width
                #expect(abs(view.camera.heading - heading) < 0.01)
                #expect(view.camera.pitch == 0)
                #expect(view.camera.centerCoordinateDistance >= 25)
            }
        }

        @Test("같은 위치에서도 최소 표시 범위를 유지하고 다른 층·잘못된 요청은 거절한다")
        func boundsAndInvalidInput() throws {
            let parent = try parent()
            let coordinator = IndoorMapKitView.Coordinator(parent: parent)
            let view = coordinator.makeMapView()
            coordinator.update(parent: parent, in: view)
            let window = try host(view, size: CGSize(width: 390, height: 800))
            defer { window.isHidden = true; coordinator.detachMapView() }
            let point = F.position(x: 10).coordinate
            let valid = BookNavigationCameraFocus(floorID: parent.floor.id, coordinates: [point, point], minimumSpanMeters: 12)
            #expect(coordinator.moveCamera(.init(id: 2, target: .navigation(valid)), in: view, animated: false))
            #expect(view.visibleMapRect.width.isFinite && view.visibleMapRect.width > 0)
            #expect(view.camera.centerCoordinateDistance >= 25)
            let invalid = [
                BookNavigationCameraFocus(floorID: UUID(), coordinates: [point], minimumSpanMeters: 12),
                .init(floorID: parent.floor.id, coordinates: [], minimumSpanMeters: 12),
                .init(floorID: parent.floor.id, coordinates: [point], minimumSpanMeters: .nan),
                .init(floorID: parent.floor.id, coordinates: [.init(latitude: 91, longitude: 0)], minimumSpanMeters: 12)
            ]
            for focus in invalid {
                #expect(!coordinator.moveCamera(.init(id: 3, target: .navigation(focus)), in: view, animated: false))
            }
        }

        @Test("먼 뒤쪽 경로의 외곽이 같아도 현재 안내 구간을 따라 포커스와 줌이 변한다")
        func focusesCurrentStageOnWindingRoute() throws {
            let session = try F.windingSession()
            let plan = try RouteGuidancePlan(route: session.legs[0], graph: session.graph)
            let floor = try #require(session.map.floors.first)
            var parent = IndoorMapKitView(map: session.map, floor: floor, selectedFeatureID: nil,
                position: nil, showsUserLocation: false, isPlacingOrigin: false,
                cameraRequest: nil, onSelect: { _ in }, onPlaceOrigin: { _ in }, navigationAppearance: true)
            parent.viewportInsets = .init(top: 280, left: 0, bottom: 90, right: 0)
            let coordinator = IndoorMapKitView.Coordinator(parent: parent)
            let view = coordinator.makeMapView()
            coordinator.update(parent: parent, in: view)
            let window = try host(view, size: CGSize(width: 390, height: 800))
            defer { window.isHidden = true; coordinator.detachMapView() }
            var tracking = BookNavigationCameraTracking()
            func move(_ y: Double, id: Int) throws {
                let position = F.position(x: 0, y: y)
                let focus = try #require(tracking.focus(position: position,
                    progress: try plan.progress(for: position, at: F.now), plan: plan, floorID: floor.id))
                #expect(coordinator.moveCamera(.init(id: id, target: .navigation(focus)), in: view, animated: false))
            }
            try move(0, id: 1)
            let firstCenter = view.centerCoordinate
            let firstWidth = view.visibleMapRect.width
            try move(10, id: 2)
            let moved = RoutingGeometry.distanceMeters(
                from: .init(latitude: firstCenter.latitude, longitude: firstCenter.longitude),
                to: .init(latitude: view.centerCoordinate.latitude, longitude: view.centerCoordinate.longitude))
            #expect(moved > 2)
            #expect(view.visibleMapRect.width < firstWidth * 0.9)
        }

        @Test("사용자 제스처만 자동 추적을 중단하고 보류된 자동 카메라 요청을 버린다")
        func detectsManualInteraction() throws {
            var parent = try parent()
            var interactions = 0
            parent.onUserCameraInteraction = { interactions += 1 }
            let coordinator = IndoorMapKitView.Coordinator(parent: parent)
            let view = coordinator.makeMapView()
            coordinator.update(parent: parent, in: view)
            coordinator.mapView(view, regionWillChangeAnimated: true)
            #expect(interactions == 0 && coordinator.pendingCameraRequest != nil)
            let gesture = ActiveCameraGesture()
            view.addGestureRecognizer(gesture)
            gesture.testState = .began
            coordinator.mapView(view, regionWillChangeAnimated: false)
            #expect(interactions == 1)
            #expect(coordinator.pendingCameraRequest == nil)
            #expect(coordinator.lastCameraRequest == parent.cameraRequest)
            coordinator.detachMapView()
        }

        private func parent() throws -> IndoorMapKitView {
            let map = IndoorMapTestData.map()
            let floor = try #require(map.floors.first)
            return IndoorMapKitView(map: map, floor: floor, selectedFeatureID: nil,
                position: nil, showsUserLocation: false, isPlacingOrigin: false,
                cameraRequest: .init(id: 1, target: .floor(floor.id)),
                onSelect: { _ in }, onPlaceOrigin: { _ in }, navigationAppearance: true)
        }

        private func host(_ view: UIView, size: CGSize) throws -> UIWindow {
            let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
            let window = UIWindow(windowScene: scene)
            let controller = UIViewController()
            window.rootViewController = controller
            controller.view.addSubview(view)
            view.frame = CGRect(origin: .zero, size: size)
            window.isHidden = false
            window.layoutIfNeeded()
            view.layoutIfNeeded()
            return window
        }
    }
}

@MainActor
private final class ActiveCameraGesture: UIPanGestureRecognizer {
    var testState: UIGestureRecognizer.State = .possible
    override var state: UIGestureRecognizer.State {
        get { testState }
        set { testState = newValue }
    }
}
