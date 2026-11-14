import MapKit
import Testing
@testable import fingerprint_library

@MainActor
struct LibraryEntranceApproachTests {
    @Test func 외부의_다른_층_좌표에서도_블루도트와_출입구_점선을_그리고_갱신한다() async throws {
        let map = try await BundledIndoorMapLoader().loadLibrary()
        let now = Date()
        let sensed = IndoorPosition(coordinate: .init(latitude: 36.0129329, longitude: 129.3256179),
            floorOrdinal: 99, horizontalAccuracy: 5, timestamp: now, source: .sensor)
        let start = try #require(RouteStartPolicy().decide(position: sensed, isAuthorized: true, map: map, now: now).startPosition)
        let floor = try #require(map.floors.first { $0.ordinal == start.floorOrdinal })
        let approach = try #require(LibraryEntranceApproach(position: sensed, entrance: start, map: map))
        func makeParent(position: IndoorPosition, approach: LibraryEntranceApproach?) -> IndoorMapKitView {
            IndoorMapKitView(map: map, floor: floor, selectedFeatureID: nil, position: position,
                showsUserLocation: false, isPlacingOrigin: false, cameraRequest: nil,
                onSelect: { _ in }, onPlaceOrigin: { _ in }, entranceApproach: approach, navigationAppearance: true)
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
        #expect(renderer.lineDashPattern == [5, 6])
        #expect(view.annotations.contains { $0.title == "현재 위치" && abs($0.coordinate.latitude - sensed.coordinate.latitude) < 0.000_000_1 })

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
