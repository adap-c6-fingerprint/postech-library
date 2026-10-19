import Foundation
import MapKit
import Testing
@testable import fingerprint_library

@MainActor
struct IndoorShelfAnnotationTests {
    @Test("지도 뒤에 늦게 읽힌 서가를 도착 노드 좌표에 표시하고 선택 시 서가 키를 전달한다")
    func displaysAndSelectsMappedDestination() async throws {
        let root = try NavigationTestFixture.directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let (map, navigation) = try await NavigationTestFixture.load(root)
        let floor = try #require(map.floors.first)
        let shelf = try #require(navigation.shelves.destinations.first)
        var selected: ShelfKey?
        var parent = IndoorMapKitView(map: map, floor: floor, selectedFeatureID: nil, position: nil,
            showsUserLocation: false, isPlacingOrigin: false, cameraRequest: nil,
            onSelect: { _ in }, onPlaceOrigin: { _ in })
        let coordinator = parent.makeCoordinator()
        let view = coordinator.makeMapView()
        defer { view.delegate = nil }
        coordinator.update(parent: parent, in: view)
        #expect(view.annotations.compactMap { $0 as? IndoorShelfAnnotation }.isEmpty)

        parent.shelves = navigation.shelves.destinations
        parent.onSelectShelf = { selected = $0 }
        coordinator.update(parent: parent, in: view)
        let pins = view.annotations.compactMap { $0 as? IndoorShelfAnnotation }
        let pin = try #require(pins.first)
        #expect(pins.count == 1)
        #expect(pin.coordinate.latitude == shelf.arrivalCoordinate.latitude)
        #expect(pin.coordinate.longitude == shelf.arrivalCoordinate.longitude)
        #expect(pin.destination.arrivalNodeID == "b")
        coordinator.mapView(view, didSelect: pin)
        #expect(selected == shelf.key)
        coordinator.update(parent: parent, in: view)
        #expect(view.annotations.compactMap { $0 as? IndoorShelfAnnotation }.count == 1)

        let otherFloor = IndoorMapFloor(id: UUID(), ordinal: 10, name: "다른 층", geometry: floor.geometry)
        let other = IndoorMapKitView(map: map, floor: otherFloor, selectedFeatureID: nil, position: nil,
            showsUserLocation: false, isPlacingOrigin: false, cameraRequest: nil,
            onSelect: { _ in }, onPlaceOrigin: { _ in }, shelves: navigation.shelves.destinations)
        coordinator.update(parent: other, in: view)
        #expect(view.annotations.compactMap { $0 as? IndoorShelfAnnotation }.isEmpty)
    }

    @Test("시뮬레이션 점은 native 사용자 위치와 구분하고 이동 시 annotation을 재생성하지 않는다")
    func updatesSimulationDot() throws {
        let map = IndoorMapTestData.map()
        let floor = try #require(map.floors.first { $0.ordinal == 4 })
        func parent(latitude: Double) -> IndoorMapKitView {
            let position = IndoorPosition(coordinate: .init(latitude: latitude, longitude: 129.001),
                floorOrdinal: 4, horizontalAccuracy: 0, timestamp: IndoorMapTestData.now, source: .simulation)
            return IndoorMapKitView(map: map, floor: floor, selectedFeatureID: nil, position: position,
                showsUserLocation: false, isPlacingOrigin: false, cameraRequest: nil,
                onSelect: { _ in }, onPlaceOrigin: { _ in })
        }
        let first = parent(latitude: 36.001)
        let coordinator = first.makeCoordinator()
        let view = coordinator.makeMapView()
        defer { view.delegate = nil }
        coordinator.update(parent: first, in: view)
        let dot = try #require(view.annotations.first { $0.title == "시뮬레이션 위치" })
        #expect(!view.showsUserLocation)
        #expect(coordinator.mapView(view, viewFor: dot)?.accessibilityIdentifier == "simulation-position")
        coordinator.update(parent: parent(latitude: 36.002), in: view)
        let moved = try #require(view.annotations.first { $0.title == "시뮬레이션 위치" })
        let sameAnnotation = (moved as AnyObject) === (dot as AnyObject)
        #expect(sameAnnotation)
        #expect(moved.coordinate.latitude == 36.002)
    }
}
