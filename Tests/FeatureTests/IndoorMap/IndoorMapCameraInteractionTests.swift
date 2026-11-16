import ComposableArchitecture
import MapKit
import Testing
@testable import fingerprint_library

@MainActor
struct IndoorMapCameraInteractionTests {
    @Test(arguments: [false, true])
    func 지도_직접_조작은_출발지_선택과_안내_화면_모두에_전달된다(navigationAppearance: Bool) async throws {
        let map = try await BundledIndoorMapLoader().loadLibrary()
        let floor = try #require(map.floors.first)
        let calls = LockIsolated(0)
        let view = IndoorMapKitView(
            map: map, floor: floor, position: nil, showsUserLocation: false, cameraRequest: nil,
            navigationAppearance: navigationAppearance,
            onUserCameraInteraction: { calls.withValue { $0 += 1 } },
            appearance: navigationAppearance ? .standard : .home)
        let mapView = MKMapView()
        mapView.addGestureRecognizer(ActiveMapGesture(target: nil, action: nil))
        view.makeCoordinator().mapView(mapView, regionWillChangeAnimated: false)
        #expect(calls.value == 1)
    }

    @Test(arguments: [false, true])
    func 초기_카메라_배치는_사용자의_위치_수정으로_전달하지_않는다(navigationAppearance: Bool) async throws {
        let map = try await BundledIndoorMapLoader().loadLibrary()
        let floor = try #require(map.floors.first)
        let calls = LockIsolated(0)
        let view = IndoorMapKitView(
            map: map, floor: floor, position: nil, showsUserLocation: false, cameraRequest: nil,
            navigationAppearance: navigationAppearance,
            onUserCameraInteraction: { calls.withValue { $0 += 1 } },
            appearance: navigationAppearance ? .standard : .home)
        let coordinator = view.makeCoordinator()
        let mapView = MKMapView()
        coordinator.mapView(mapView, regionWillChangeAnimated: true)
        coordinator.mapView(mapView, regionWillChangeAnimated: false)
        #expect(calls.value == 0)
    }

    private final class ActiveMapGesture: UIGestureRecognizer {
        override var state: UIGestureRecognizer.State {
            get { .began }
            set { }
        }
    }
}
