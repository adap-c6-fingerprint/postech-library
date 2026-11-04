import MapKit
import Testing
import UIKit
@testable import fingerprint_library

extension IndoorMapSerialTests {
    @MainActor
    struct BookNavigationMapStyleTests {
        @Test("실시간 안내만 점선·출발 핀을 쓰고, 도착 핀은 현재 책의 층에만 표시한다")
        func navigationOnlyStyling() throws {
            let fixture = try BookNavigationTimelineTests().makePlan()
            let map = map(for: fixture.graph)
            let book = BookHoldingTestData.book()
            func parent(floor: Int, navigation: Bool) -> IndoorMapKitView {
                .init(map: map, floor: map.floors[floor], selectedFeatureID: nil,
                    position: nil, showsUserLocation: false, isPlacingOrigin: false, cameraRequest: nil,
                    onSelect: { _ in }, onPlaceOrigin: { _ in }, route: fixture.route,
                    navigationAppearance: navigation,
                    navigationDestination: navigation ? .init(book: book, coordinate: fixture.graph.nodes[3].coordinate,
                        floorID: map.floors[1].id) : nil)
            }
            let initial = parent(floor: 0, navigation: true)
            let coordinator = IndoorMapKitView.Coordinator(parent: initial)
            let view = coordinator.makeMapView()
            defer { coordinator.detachMapView() }
            coordinator.update(parent: initial, in: view)
            let start = try #require(view.annotations.first { $0 is BookNavigationStartAnnotation })
            let startView = try #require(coordinator.mapView(view, viewFor: start))
            let startAsset = try #require(UIImage(named: "MapLocationStart"))
            #expect(try #require(startView.image).pngData() == startAsset.pngData())
            #expect(startView.centerOffset.y == -16)
            #expect(!view.annotations.contains { $0 is BookNavigationDestinationAnnotation })
            let line = try #require(view.overlays.compactMap { $0 as? MKPolyline }.first)
            let renderer = try #require(coordinator.mapView(view, rendererFor: line) as? MKPolylineRenderer)
            #expect(renderer.lineDashPattern?.map(\.doubleValue) == [0, 9])
            let entry = try #require(view.annotations.compactMap { $0 as? IndoorRouteTransitionAnnotation }.first)
            #expect(entry.movesUp == true)
            #expect(coordinator.mapView(view, viewFor: entry)?.image?.pngData()
                == MapAnnotationImage.asset(named: "annotation_up")?.pngData())
            coordinator.update(parent: parent(floor: 1, navigation: true), in: view)
            #expect(!view.annotations.contains { $0 is BookNavigationStartAnnotation })
            let end = try #require(view.annotations.first { $0 is BookNavigationDestinationAnnotation })
            let endAsset = try #require(UIImage(named: "MapLocationEnd"))
            #expect(try #require(coordinator.mapView(view, viewFor: end)?.image).pngData() == endAsset.pngData())
            coordinator.update(parent: parent(floor: 0, navigation: false), in: view)
            #expect(!view.annotations.contains { $0 is BookNavigationStartAnnotation || $0 is BookNavigationDestinationAnnotation })
            let previewLine = try #require(view.overlays.compactMap { $0 as? MKPolyline }.first)
            #expect((coordinator.mapView(view, rendererFor: previewLine) as? MKPolylineRenderer)?.lineDashPattern == nil)
        }

        @Test("하행 계단 진입은 Down 에셋으로 구분한다")
        func downwardEntry() throws {
            let fixture = try BookNavigationTimelineTests().makePlan(category: .stairs)
            let original = try #require(fixture.route.floorChanges.first)
            let change = RouteFloorChange(edgeIDs: original.edgeIDs, category: .stairs,
                fromFloorID: original.toFloorID, toFloorID: original.fromFloorID,
                fromCoordinate: original.toCoordinate, toCoordinate: original.fromCoordinate)
            let annotation = IndoorRouteTransitionAnnotation(change: change, isEntry: true, movesUp: false)
            let map = map(for: fixture.graph)
            let parent = IndoorMapKitView(map: map, floor: map.floors[1], selectedFeatureID: nil,
                position: nil, showsUserLocation: false, isPlacingOrigin: false, cameraRequest: nil,
                onSelect: { _ in }, onPlaceOrigin: { _ in }, navigationAppearance: true)
            let coordinator = IndoorMapKitView.Coordinator(parent: parent)
            let view = coordinator.makeMapView()
            defer { coordinator.detachMapView() }
            #expect(coordinator.mapView(view, viewFor: annotation)?.image?.pngData()
                == MapAnnotationImage.asset(named: "annotation_Down")?.pngData())
        }

        private func map(for graph: RoutingGraph) -> IndoorMap {
            let a = graph.nodes[0], b = graph.nodes[2]
            return .init(formatVersion: "test", venue: .init(sourceID: UUID(), kind: .venue, floorID: nil,
                category: nil, name: "도서관", geometry: .point(a.coordinate)),
                floors: [a, b].map { .init(id: $0.floorID, ordinal: $0.level, name: "\($0.level + 1)층", geometry: .point($0.coordinate)) },
                features: [], diagnostics: [])
        }
    }
}
