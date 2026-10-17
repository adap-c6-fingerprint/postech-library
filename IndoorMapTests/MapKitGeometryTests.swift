import MapKit
import Testing
@testable import fingerprint_library

@MainActor
struct MapKitGeometryTests {
    @Test("MapKit Polygon 변환에서 내부 ring과 좌표 순서를 유지한다")
    func polygonConversion() throws {
        let overlays = MapKitGeometry.overlays(for: .polygon([IndoorMapTestData.square, IndoorMapTestData.hole]))
        let polygon = try #require(overlays.first as? MKPolygon)
        #expect(overlays.count == 1)
        #expect(polygon.interiorPolygons?.count == 1)
        #expect(polygon.pointCount == 5)
        let coordinate = polygon.points()[1].coordinate
        #expect(abs(coordinate.longitude - 129.01) < 1e-8)
        #expect(abs(coordinate.latitude - 36) < 1e-8)
    }

    @Test("MultiPolygon은 개별 Polygon으로 표시한다")
    func multiplePolygons() {
        let geometry = IndoorMapGeometry.multiPolygon([[IndoorMapTestData.square], [IndoorMapTestData.square, IndoorMapTestData.hole]])
        let overlays = MapKitGeometry.overlays(for: geometry)
        #expect(overlays.count == 2)
        #expect((overlays[1] as? MKPolygon)?.interiorPolygons?.count == 1)
        let rect = MapKitGeometry.mapRect(for: geometry)
        #expect(!rect.isNull && rect.size.width > 0 && rect.size.height > 0)
        #expect(rect.contains(MKMapPoint(IndoorMapTestData.point.clCoordinate)))
    }

    @Test("층 전체 보기의 기본 카메라는 평면이다")
    func defaultFlatCamera() throws {
        let map = IndoorMapTestData.map()
        let floor = try #require(map.floors.first)
        let parent = IndoorMapKitView(
            map: map, floor: floor, selectedFeatureID: nil, position: nil,
            showsUserLocation: false, isPlacingOrigin: false, cameraRequest: nil,
            onSelect: { _ in }, onPlaceOrigin: { _ in }
        )
        let view = MKMapView(frame: CGRect(x: 0, y: 0, width: 390, height: 800))
        let coordinator = IndoorMapKitView.Coordinator(parent: parent)
        coordinator.moveCamera(.init(id: 1, target: .floor(floor.id)), in: view)
        #expect(view.camera.pitch == 0)
    }
}
