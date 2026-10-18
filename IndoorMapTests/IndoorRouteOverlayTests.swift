import Foundation
import MapKit
import Testing

@testable import fingerprint_library

@MainActor
struct IndoorRouteOverlayTests {
    @Test("경로 닫기로 서가 선택이 해제되면 native 핀도 해제해 같은 핀을 다시 선택할 수 있다")
    func deselectsNativePin() throws {
        typealias F = IndoorRoutingTestFactory
        let a = F.node("a"), b = F.node("b", x: 20)
        let request = F.request(graph: F.graph([a, b], [F.edge("ab", a, b)]), start: a.coordinate, target: b.id)
        let original = IndoorMapTestData.map()
        let floor = IndoorMapFloor(id: b.floorID, ordinal: b.level, name: "층", geometry: original.floors[0].geometry)
        let map = IndoorMap(formatVersion: "1", venue: original.venue, floors: [floor], features: [], diagnostics: [])
        var parent = IndoorMapKitView(map: map, floor: floor, selectedFeatureID: nil, position: nil,
            showsUserLocation: false, isPlacingOrigin: false, cameraRequest: nil,
            onSelect: { _ in }, onPlaceOrigin: { _ in }, shelves: request.navigation.shelves.destinations,
            selectedShelfKey: request.destination)
        let coordinator = parent.makeCoordinator()
        let view = coordinator.makeMapView()
        defer { view.delegate = nil }
        coordinator.update(parent: parent, in: view)
        let pin = try #require(view.annotations.compactMap { $0 as? IndoorShelfAnnotation }.first)
        view.selectAnnotation(pin, animated: false)
        #expect(view.selectedAnnotations.count == 1)
        parent.selectedShelfKey = nil
        coordinator.update(parent: parent, in: view)
        #expect(view.selectedAnnotations.isEmpty)
    }

    @Test("경로를 현재 조회 층에만 표시하고 층 전환·경로 해제 시 기존 overlay를 정리한다")
    func rendersPerFloor() throws {
        typealias F = IndoorRoutingTestFactory
        let a = F.node("a")
        let b = F.node("b", x: 100)
        let c = F.node("c", x: 100, level: 1)
        let d = F.node("d", x: 200, level: 1)
        let request = F.request(
            graph: F.graph(
                [a, b, c, d], [F.edge("ab", a, b), F.edge("bc", b, c, category: .elevator), F.edge("cd", c, d)]),
            start: a.coordinate, target: d.id, distances: ["bc": .init(meters: 3.5, source: .estimated)])
        guard case .route(let route) = try IndoorRouteSearchEngine().search(request) else {
            throw IndoorRoutingError.noRoute
        }
        let original = IndoorMapTestData.map()
        let floors = [a, c].map {
            IndoorMapFloor(id: $0.floorID, ordinal: $0.level, name: "층", geometry: original.floors[0].geometry)
        }
        let map = IndoorMap(formatVersion: "1", venue: original.venue, floors: floors, features: [], diagnostics: [])
        func parent(_ floor: Int, route: IndoorRoute?) -> IndoorMapKitView {
            IndoorMapKitView(
                map: map, floor: floors[floor], selectedFeatureID: nil, position: nil, showsUserLocation: false,
                isPlacingOrigin: false, cameraRequest: nil, onSelect: { _ in }, onPlaceOrigin: { _ in }, route: route)
        }
        let first = parent(0, route: route)
        let coordinator = first.makeCoordinator()
        let view = coordinator.makeMapView()
        defer { view.delegate = nil }
        coordinator.update(parent: first, in: view)
        let lower = try #require(view.overlays.compactMap { $0 as? MKPolyline }.first)
        #expect(view.overlays.compactMap { $0 as? MKPolyline }.count == 1)
        #expect(lower.pointCount == 2)
        #expect(abs(lower.points()[0].coordinate.longitude - a.coordinate.longitude) < 0.000_001)
        coordinator.update(parent: parent(1, route: route), in: view)
        let upper = try #require(view.overlays.compactMap { $0 as? MKPolyline }.first)
        #expect(view.overlays.compactMap { $0 as? MKPolyline }.count == 1)
        #expect(abs(upper.points()[0].coordinate.longitude - c.coordinate.longitude) < 0.000_001)
        #expect(view.overlays.compactMap { $0 as? MKCircle }.count == 1)
        coordinator.update(parent: parent(1, route: nil), in: view)
        #expect(view.overlays.compactMap { $0 as? MKPolyline }.isEmpty)
        #expect(view.overlays.compactMap { $0 as? MKCircle }.isEmpty)
    }
}
