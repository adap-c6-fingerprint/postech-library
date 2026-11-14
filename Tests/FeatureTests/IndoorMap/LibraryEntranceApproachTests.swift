import MapKit
import Testing
import UIKit
@testable import fingerprint_library

@MainActor
struct LibraryEntranceApproachTests {
    @Test func 외부의_다른_층_좌표에서도_블루도트와_출입구_점선을_그리고_갱신한다() async throws {
        let map = try await BundledIndoorMapLoader().loadLibrary()
        let now = Date()
        let sensed = IndoorPosition(coordinate: .init(latitude: 36.0129329, longitude: 129.3256179),
            floorOrdinal: 99, horizontalAccuracy: 5, timestamp: now, source: .sensor, headingDegrees: 45)
        let start = try #require(RouteStartPolicy().decide(position: sensed, isAuthorized: true, map: map, now: now).startPosition)
        let floor = try #require(map.floors.first { $0.ordinal == start.floorOrdinal })
        let approach = try #require(LibraryEntranceApproach(position: sensed, entrance: start, map: map))
        func makeParent(position: IndoorPosition, approach: LibraryEntranceApproach?) -> IndoorMapKitView {
            IndoorMapKitView(map: map, floor: floor, position: position,
                showsUserLocation: false, cameraRequest: nil,
                entranceApproach: approach, navigationAppearance: true)
        }
        var parent = makeParent(position: sensed, approach: approach)
        let coordinator = parent.makeCoordinator()
        let view = coordinator.makeMapView()
        view.frame = .init(x: 0, y: 0, width: 402, height: 874)
        coordinator.update(parent: parent, in: view)

        let line = try #require(view.overlays.compactMap { $0 as? MKPolyline }.first)
        #expect(line.pointCount == 2)
        #expect(abs(line.points()[0].coordinate.latitude - sensed.coordinate.latitude) < 0.000_000_1)
        #expect(abs(line.points()[1].coordinate.longitude - start.coordinate.longitude) < 0.000_000_1)
        let renderer = try #require(coordinator.mapView(view, rendererFor: line) as? MKPolylineRenderer)
        #expect(renderer is NavigationDottedRouteRenderer)
        #expect(renderer.lineDashPattern == [0, 9])
        #expect(renderer.strokeColor == BookNavigationPalette.uiAccent)
        #expect(view.annotations.contains { $0.title == "현재 위치" && abs($0.coordinate.latitude - sensed.coordinate.latitude) < 0.000_000_1 })

        func marker() throws -> (UIImageView, UIImageView, UIView) {
            let annotation = try #require(view.annotations.first { $0.title == "현재 위치" })
            let marker = try #require(coordinator.mapView(view, viewFor: annotation) as? MapUserLocationAnnotationView)
            let dot = try #require(marker.subviews.first { $0.accessibilityIdentifier == "user-location-dot-image" } as? UIImageView)
            let container = try #require(marker.subviews.first { $0.accessibilityIdentifier == "user-location-heading-container" })
            let heading = try #require(container.subviews.first { $0.accessibilityIdentifier == "user-location-heading-image" } as? UIImageView)
            return (dot, heading, container)
        }
        let (dot, heading, container) = try marker()
        let expectedDot = try #require(UIImage(named: "MapUserLocation"))
        let expectedHeading = try #require(UIImage(named: "MapUserHeading"))
        #expect(dot.image?.pngData() == expectedDot.pngData())
        #expect(heading.image?.pngData() == expectedHeading.pngData())
        #expect(!dot.isHidden)
        #expect(!container.isHidden)
        let initialAngle = (45 - view.camera.heading) * .pi / 180
        #expect(abs(container.transform.a - cos(initialAngle)) < 0.000_001)
        #expect(abs(container.transform.b - sin(initialAngle)) < 0.000_001)

        let turned = IndoorPosition(coordinate: sensed.coordinate, floorOrdinal: sensed.floorOrdinal,
            horizontalAccuracy: sensed.horizontalAccuracy, timestamp: sensed.timestamp,
            source: .sensor, headingDegrees: 135)
        parent = makeParent(position: turned, approach: .init(position: turned, entrance: start, map: map))
        coordinator.update(parent: parent, in: view)
        #expect(view.overlays.contains { $0 === line })
        let (_, _, turnedContainer) = try marker()
        let turnedAngle = (135 - view.camera.heading) * .pi / 180
        #expect(abs(turnedContainer.transform.a - cos(turnedAngle)) < 0.000_001)
        #expect(abs(turnedContainer.transform.b - sin(turnedAngle)) < 0.000_001)

        let rotatedCamera = view.camera.copy() as! MKMapCamera
        rotatedCamera.heading = 30
        view.setCamera(rotatedCamera, animated: false)
        let (_, _, rotatedContainer) = try marker()
        #expect(abs(view.camera.heading - 30) < 0.000_001)
        let rotatedAngle = (135 - view.camera.heading) * .pi / 180
        #expect(abs(rotatedContainer.transform.a - cos(rotatedAngle)) < 0.000_001)
        #expect(abs(rotatedContainer.transform.b - sin(rotatedAngle)) < 0.000_001)

        let moved = IndoorPosition(coordinate: .init(latitude: 36.0129340, longitude: 129.3256200),
            floorOrdinal: 4, horizontalAccuracy: 5, timestamp: now, source: .sensor)
        parent = makeParent(position: moved, approach: .init(position: moved, entrance: start, map: map))
        coordinator.update(parent: parent, in: view)
        #expect(!view.overlays.contains { $0 === line })
        #expect(view.overlays.compactMap { $0 as? MKPolyline }.count == 1)
        #expect(view.annotations.contains { $0.title == "현재 위치" && abs($0.coordinate.latitude - moved.coordinate.latitude) < 0.000_000_1 })

        parent.entranceApproach = nil
        coordinator.update(parent: parent, in: view)
        #expect(view.overlays.compactMap { $0 as? MKPolyline }.isEmpty)
        #expect(!view.annotations.contains { $0.title == "현재 위치" && abs($0.coordinate.latitude - moved.coordinate.latitude) < 0.000_000_1 })
        coordinator.detachMapView()
    }
}
