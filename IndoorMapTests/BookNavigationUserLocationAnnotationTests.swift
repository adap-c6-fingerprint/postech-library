import MapKit
import Testing
import UIKit
@testable import fingerprint_library

extension IndoorMapSerialTests {
    @MainActor
    struct BookNavigationUserLocationAnnotationTests {
        @Test("Po:book 길안내는 홈과 같은 원본 위치 에셋으로 경로 방향을 표시한다",
              arguments: [IndoorPosition.Source.sensor, .simulation, .manual],
              [Double?](arrayLiteral: -Double.pi / 2, Double.pi / 2, nil, Double.nan))
        func usesSharedAssets(source: IndoorPosition.Source, bearing: Double?) throws {
            #expect(Bundle.main.bundleIdentifier == "com.youngmin.fingerprint-library")
            let map = IndoorMapTestData.map()
            let floor = try #require(map.floors.first)
            let position = IndoorPosition(coordinate: IndoorMapTestData.point, floorOrdinal: floor.ordinal,
                horizontalAccuracy: 0, timestamp: IndoorMapTestData.now, source: source, headingDegrees: 180)
            let parent = IndoorMapKitView(map: map, floor: floor, selectedFeatureID: nil,
                position: position, showsUserLocation: false, isPlacingOrigin: false, cameraRequest: nil,
                onSelect: { _ in }, onPlaceOrigin: { _ in }, navigationAppearance: true,
                navigationBearingRadians: bearing)
            let coordinator = parent.makeCoordinator()
            let view = coordinator.makeMapView()
            defer { coordinator.detachMapView() }
            coordinator.update(parent: parent, in: view)
            let annotation = try #require(view.annotations.first)
            let marker = try #require(coordinator.mapView(view, viewFor: annotation) as? MapUserLocationAnnotationView)
            marker.layoutIfNeeded()
            #expect(marker.accessibilityIdentifier == "book-navigation-position")
            #expect(marker.centerOffset == .zero)
            #expect(marker.bounds.size == CGSize(width: 32, height: 32))
            let dot = try #require(find(in: marker, id: "user-location-dot-image") as? UIImageView)
            let heading = try #require(find(in: marker, id: "user-location-heading-image") as? UIImageView)
            #expect(dot.image?.pngData() == UIImage(named: "MapUserLocation")?.pngData())
            #expect(heading.image?.pngData() == UIImage(named: "MapUserHeading")?.pngData())
            #expect(dot.center == CGPoint(x: 16, y: 16))
            let container = try #require(find(in: marker, id: "user-location-heading-container"))
            if let bearing, bearing.isFinite {
                #expect(!container.isHidden)
                let angle = bearing - view.camera.heading * .pi / 180
                #expect(abs(container.transform.a - cos(angle)) < 0.000_001)
                #expect(abs(container.transform.b - sin(angle)) < 0.000_001)
            } else {
                #expect(container.isHidden)
                #expect(!dot.isHidden)
            }
        }

        private func find(in view: UIView, id: String) -> UIView? {
            if view.accessibilityIdentifier == id { return view }
            return view.subviews.lazy.compactMap { find(in: $0, id: id) }.first
        }
    }
}
