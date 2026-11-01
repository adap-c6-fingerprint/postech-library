import Foundation
import MapKit
import Testing
import UIKit
@testable import fingerprint_library

extension IndoorMapSerialTests {
    @MainActor
    struct HomeUserLocationAnnotationTests {
        @Test("원본 위치 링과 방향 이미지를 읽고 좌표 중심을 링 가운데에 둔다")
        func usesOriginalArtwork() throws {
            let marker = HomeUserLocationAnnotationView(annotation: nil, reuseIdentifier: "test")
            marker.configure(headingDegrees: 45, mapHeading: 0)
            marker.layoutIfNeeded()
            let dot = try image(in: marker, id: "user-location-dot-image")
            let heading = try image(in: marker, id: "user-location-heading-image")
            #expect(dot.image?.size == CGSize(width: 25, height: 25))
            #expect(heading.image?.size == CGSize(width: 49, height: 39))
            #expect(dot.image?.renderingMode == .alwaysOriginal)
            #expect(marker.bounds.size == CGSize(width: 25, height: 25))
            #expect(marker.centerOffset == .zero)
            #expect(dot.center == CGPoint(x: 12.5, y: 12.5))
            #expect(heading.layer.position == dot.center)
            #expect(heading.layer.anchorPoint == CGPoint(x: 0, y: 1))

            let canvas = UIView(frame: CGRect(x: 0, y: 0, width: 140, height: 140))
            canvas.backgroundColor = .darkGray
            marker.center = CGPoint(x: 70, y: 70)
            canvas.addSubview(marker)
            canvas.layoutIfNeeded()
            let preview = UIGraphicsImageRenderer(bounds: canvas.bounds).image { context in
                canvas.layer.render(in: context.cgContext)
            }
            try preview.pngData()?.write(to: FileManager.default.temporaryDirectory.appendingPathComponent("issue227-user-location.png"))
        }

        @Test("헤드 방향에서 지도 회전과 원본 이미지 방향을 빼고 링 자체는 회전하지 않는다",
              arguments: [(0.0, 0.0), (90, 0), (0, 90), (270, 40)])
        func rotatesHeadingOnly(headingDegrees: Double, mapHeading: Double) throws {
            let marker = HomeUserLocationAnnotationView(annotation: nil, reuseIdentifier: "test")
            marker.configure(headingDegrees: headingDegrees, mapHeading: mapHeading)
            let heading = try image(in: marker, id: "user-location-heading-image")
            let dot = try image(in: marker, id: "user-location-dot-image")
            let angle = (headingDegrees - mapHeading - 45) * .pi / 180
            #expect(abs(heading.transform.a - cos(angle)) < 0.000_001)
            #expect(abs(heading.transform.b - sin(angle)) < 0.000_001)
            #expect(dot.transform == .identity)
            marker.configure(headingDegrees: nil, mapHeading: mapHeading)
            #expect(heading.isHidden)
            #expect(!dot.isHidden)
        }

        @Test("홈에서는 센서·시뮬레이터 위치를 같은 이미지로 표시하고 제자리 방향 변경도 반영한다",
              arguments: [(IndoorPosition.Source.sensor, true), (.sensor, false), (.simulation, true)])
        func updatesHeadingWithoutMovement(source: IndoorPosition.Source, hasFloor: Bool) async throws {
            let data = IndoorMapTestData.map()
            let floor = try #require(data.floors.first)
            func position(_ heading: Double) -> IndoorPosition {
                .init(coordinate: IndoorMapTestData.point, floorOrdinal: hasFloor ? floor.ordinal : nil, horizontalAccuracy: 0,
                      timestamp: IndoorMapTestData.now, source: source, headingDegrees: heading)
            }
            var parent = IndoorMapKitView(map: data, floor: floor, selectedFeatureID: nil,
                position: position(0), showsUserLocation: true, isPlacingOrigin: false, cameraRequest: nil,
                onSelect: { _ in }, onPlaceOrigin: { _ in }, appearance: .home)
            let coordinator = IndoorMapKitView.Coordinator(parent: parent)
            let map = coordinator.makeMapView()
            map.frame = CGRect(x: 0, y: 0, width: 390, height: 800)
            coordinator.update(parent: parent, in: map)
            map.setRegion(.init(center: IndoorMapTestData.point.clCoordinate, latitudinalMeters: 100, longitudinalMeters: 100), animated: false)
            let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
            let window = UIWindow(windowScene: scene)
            let host = UIViewController()
            window.rootViewController = host
            host.view.addSubview(map)
            window.makeKeyAndVisible()
            defer { coordinator.detachMapView(); window.isHidden = true; window.rootViewController = nil }
            map.layoutIfNeeded()
            let annotation = try #require(map.annotations.first { !($0 is MKUserLocation) })
            let deadline = Date().addingTimeInterval(5)
            while map.view(for: annotation) == nil, Date() < deadline { try await Task.sleep(for: .milliseconds(20)) }
            let marker = try #require(map.view(for: annotation) as? HomeUserLocationAnnotationView)
            #expect(!map.showsUserLocation)
            parent = IndoorMapKitView(map: data, floor: floor, selectedFeatureID: nil,
                position: position(180), showsUserLocation: true, isPlacingOrigin: false, cameraRequest: nil,
                onSelect: { _ in }, onPlaceOrigin: { _ in }, appearance: .home)
            coordinator.update(parent: parent, in: map)
            #expect(map.view(for: annotation) === marker)
            #expect(annotation.coordinate.latitude == IndoorMapTestData.point.latitude)
            #expect(annotation.coordinate.longitude == IndoorMapTestData.point.longitude)
            let heading = try image(in: marker, id: "user-location-heading-image")
            let camera = map.camera.copy() as! MKMapCamera
            camera.heading = 90
            map.setCamera(camera, animated: false)
            coordinator.mapViewDidChangeVisibleRegion(map)
            let angle = (180 - map.camera.heading - 45) * .pi / 180
            #expect(abs(heading.transform.a - cos(angle)) < 0.000_001)
            #expect(abs(heading.transform.b - sin(angle)) < 0.000_001)
        }

        private func image(in marker: UIView, id: String) throws -> UIImageView {
            try #require(marker.subviews.first { $0.accessibilityIdentifier == id } as? UIImageView)
        }
    }
}
