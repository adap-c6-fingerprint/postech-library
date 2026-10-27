import MapKit
import Testing
import UIKit
@testable import fingerprint_library

@MainActor
struct IndoorMapInitialLayoutTests {
    private let size = CGSize(width: 390, height: 800)

    private func parent(floorIndex: Int = 0, requestID: Int = 1) -> IndoorMapKitView {
        let source = IndoorMapTestData.map()
        // 최대 줌 거리(5,000m)에 제한되지 않는 약 100m 크기의 합성 도면을 사용한다.
        let geometry = IndoorMapGeometry.polygon([IndoorMapTestData.square.map {
            IndoorMapCoordinate(latitude: 36 + ($0.latitude - 36) * 0.1,
                                longitude: 129 + ($0.longitude - 129) * 0.1)
        }])
        let map = IndoorMap(
            formatVersion: source.formatVersion, venue: source.venue,
            floors: source.floors.map {
                IndoorMapFloor(id: $0.id, ordinal: $0.ordinal, name: $0.name, geometry: geometry)
            }, features: [], diagnostics: []
        )
        let floor = map.floors[floorIndex]
        return IndoorMapKitView(
            map: map, floor: floor, selectedFeatureID: nil, position: nil,
            showsUserLocation: false, isPlacingOrigin: false,
            cameraRequest: .init(id: requestID, target: .floor(floor.id)),
            onSelect: { _ in }, onPlaceOrigin: { _ in }
        )
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

    @Test("실제 도서관은 최초 표시와 1~5층 전환 때 각 층의 도형·카메라가 반영된다")
    func rendersLibraryFloors() async throws {
        let map = try await BundledIndoorMapLoader().loadLibrary()
        let first = try #require(map.floors.first)
        var parent = IndoorMapKitView(
            map: map, floor: first, selectedFeatureID: nil, position: nil,
            showsUserLocation: false, isPlacingOrigin: false,
            cameraRequest: .init(id: 1, target: .floor(first.id)),
            onSelect: { _ in }, onPlaceOrigin: { _ in }
        )
        let coordinator = IndoorMapKitView.Coordinator(parent: parent)
        let view = coordinator.makeMapView()
        coordinator.update(parent: parent, in: view)
        let window = try host(view, size: size)
        defer { window.isHidden = true }
        for (index, floor) in map.floors.enumerated() {
            parent = IndoorMapKitView(
                map: map, floor: floor, selectedFeatureID: nil, position: nil,
                showsUserLocation: false, isPlacingOrigin: false,
                cameraRequest: .init(id: index + 2, target: .floor(floor.id)),
                onSelect: { _ in }, onPlaceOrigin: { _ in }
            )
            coordinator.update(parent: parent, in: view)
            view.layoutIfNeeded()
            #expect(coordinator.renderedFloorID == floor.id)
            #expect(coordinator.lastCameraRequest == parent.cameraRequest)
            #expect(view.camera.pitch == 0)
            for point in floor.geometry.coordinates {
                #expect(view.visibleMapRect.contains(MKMapPoint(point.clCoordinate)))
            }
            // 서가·시설이 많은 상층에서도 도면의 실제 도형들이 overlay로 전달돼야 한다.
            if floor.ordinal >= 2 { #expect(view.overlays.count > 400) }
        }
    }

    @Test("처음 받은 층 카메라는 화면 부착·배치 뒤 층 선택 없이 적용된다")
    func initialCameraWaitsForLayout() throws {
        let parent = parent()
        let coordinator = IndoorMapKitView.Coordinator(parent: parent)
        let view = coordinator.makeMapView()
        coordinator.update(parent: parent, in: view)
        #expect(coordinator.lastCameraRequest == nil)
        #expect(coordinator.pendingCameraRequest == parent.cameraRequest)

        // 크기만 있고 아직 window에 붙지 않은 상태에서도 요청을 소비하지 않는다.
        view.frame = CGRect(origin: .zero, size: size)
        view.layoutIfNeeded()
        #expect(coordinator.lastCameraRequest == nil)

        let window = try host(view, size: size)
        defer { window.isHidden = true }
        #expect(coordinator.lastCameraRequest == parent.cameraRequest)
        #expect(coordinator.pendingCameraRequest == nil)
        #expect(!view.overlays.isEmpty)
        #expect(view.camera.pitch == 0)
        for point in parent.floor.geometry.coordinates {
            #expect(view.visibleMapRect.contains(MKMapPoint(point.clCoordinate)))
        }
    }

    @Test("배치 전 여러 요청이 오면 마지막 층으로 표시한다")
    func latestPendingRequestWins() throws {
        let first = parent()
        let latest = parent(floorIndex: 1, requestID: 2)
        let coordinator = IndoorMapKitView.Coordinator(parent: first)
        let view = coordinator.makeMapView()
        coordinator.update(parent: first, in: view)
        coordinator.update(parent: latest, in: view)
        #expect(coordinator.lastCameraRequest == nil)
        #expect(coordinator.pendingCameraRequest == latest.cameraRequest)
        let window = try host(view, size: size)
        defer { window.isHidden = true }
        #expect(coordinator.renderedFloorID == latest.floor.id)
        #expect(coordinator.lastCameraRequest == latest.cameraRequest)
        #expect(coordinator.pendingCameraRequest == nil)
    }

    @Test("패딩보다 작은 임시 크기에서는 보류하고 최종 크기에서 적용한다")
    func waitsForUsableSize() throws {
        let parent = parent()
        let coordinator = IndoorMapKitView.Coordinator(parent: parent)
        let view = coordinator.makeMapView()
        coordinator.update(parent: parent, in: view)
        let window = try host(view, size: CGSize(width: 80, height: 40))
        defer { window.isHidden = true }
        #expect(coordinator.lastCameraRequest == nil)
        #expect(coordinator.pendingCameraRequest == parent.cameraRequest)
        view.frame = CGRect(origin: .zero, size: size)
        view.setNeedsLayout()
        view.layoutIfNeeded()
        #expect(coordinator.lastCameraRequest == parent.cameraRequest)
        #expect(coordinator.pendingCameraRequest == nil)
    }

    @Test("초기 적용 후 같은 상태와 추가 layout은 사용자가 이동한 카메라를 덮어쓰지 않는다")
    func preservesUserCamera() throws {
        let parent = parent()
        let coordinator = IndoorMapKitView.Coordinator(parent: parent)
        let view = coordinator.makeMapView()
        coordinator.update(parent: parent, in: view)
        let window = try host(view, size: size)
        defer { window.isHidden = true }
        let userCenter = CLLocationCoordinate2D(latitude: 36.03, longitude: 129.03)
        view.setCenter(userCenter, animated: false)
        coordinator.update(parent: parent, in: view)
        view.setNeedsLayout()
        view.layoutIfNeeded()
        #expect(coordinator.pendingCameraRequest == nil)
        #expect(abs(view.centerCoordinate.latitude - userCenter.latitude) < 0.00001)
        #expect(abs(view.centerCoordinate.longitude - userCenter.longitude) < 0.00001)
    }

    @Test("현재 위치 포커스는 하단 경로 시트에 가리지 않는 영역의 중심으로 이동한다",
          arguments: [0.0, 320.0, 560.0], [0.0, 60.0])
    func recentersAboveRouteSheet(bottomInset: Double, heading: Double) throws {
        var parent = parent()
        parent.viewportInsets = .init(top: 60, left: 0, bottom: bottomInset, right: 0)
        let coordinator = IndoorMapKitView.Coordinator(parent: parent)
        let view = coordinator.makeMapView()
        coordinator.update(parent: parent, in: view)
        let window = try host(view, size: size)
        defer { window.isHidden = true }
        let camera = view.camera.copy() as! MKMapCamera
        camera.heading = heading
        view.setCamera(camera, animated: false)
        let coordinate = parent.floor.geometry.coordinates[0]
        #expect(coordinator.moveCamera(.init(id: 2, target: .position(coordinate)), in: view, animated: false))
        let point = view.convert(coordinate.clCoordinate, toPointTo: view)
        let viewport = view.bounds.inset(by: parent.viewportInsets)
        #expect(abs(point.x - viewport.midX) < 2)
        #expect(abs(point.y - viewport.midY) < 2)
        #expect(view.camera.pitch == 0)
    }
}
