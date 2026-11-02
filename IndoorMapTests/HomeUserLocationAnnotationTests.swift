import Foundation
import MapKit
import Testing
import UIKit
@testable import fingerprint_library

extension IndoorMapSerialTests {
    @MainActor
    struct HomeUserLocationAnnotationTests {
        @Test("위치 원과 헤드의 원본 에셋을 표시하고 32pt 배경 중심을 실제 좌표에 둔다")
        func usesCenteredGeometry() async throws {
            let marker = HomeUserLocationAnnotationView(annotation: nil, reuseIdentifier: "test")
            marker.configure(headingDegrees: 0, mapHeading: 0)
            marker.layoutIfNeeded()
            let dot = try image(in: marker, id: "user-location-dot-image")
            let heading = try image(in: marker, id: "user-location-heading-image")
            let originalDot = try #require(UIImage(named: "MapUserLocation"))
            let originalHeading = try #require(UIImage(named: "MapUserHeading"))
            #expect(dot.image?.pngData() == originalDot.pngData())
            #expect(heading.image?.pngData() == originalHeading.pngData())
            #expect(heading.image?.renderingMode == .alwaysOriginal)
            #expect(dot.image?.renderingMode == .alwaysOriginal)
            #expect(marker.bounds.size == CGSize(width: 32, height: 32))
            #expect(marker.centerOffset == .zero)
            #expect(dot.center == CGPoint(x: 16, y: 16))
            #expect(dot.bounds.size == CGSize(width: 17, height: 17)) // 중앙 13pt + 바깥 테두리 2pt씩
            #expect(heading.bounds.size == CGSize(width: 15.89314, height: 12.36133))
            #expect(heading.contentMode == .scaleAspectFit)
            #expect(heading.center.x == dot.center.x)
            #expect(abs(heading.frame.maxY - (dot.center.y - dot.bounds.height / 2 - 2)) < 0.000_001)
            let halo = try #require(find(in: marker, id: "user-location-halo"))
            #expect(halo.frame == marker.bounds)

            let canvas = UIView(frame: CGRect(x: 0, y: 0, width: 140, height: 140))
            canvas.backgroundColor = .darkGray
            marker.center = CGPoint(x: 70, y: 70)
            canvas.addSubview(marker)
            let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
            let window = UIWindow(windowScene: scene)
            let host = UIViewController()
            window.rootViewController = host
            host.view.addSubview(canvas)
            window.makeKeyAndVisible()
            defer { window.isHidden = true; window.rootViewController = nil }
            canvas.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(100))
            let format = UIGraphicsImageRendererFormat()
            format.scale = 5
            let preview = UIGraphicsImageRenderer(bounds: canvas.bounds, format: format).image { _ in
                canvas.drawHierarchy(in: canvas.bounds, afterScreenUpdates: true)
            }
            try preview.pngData()?.write(to: FileManager.default.temporaryDirectory.appendingPathComponent("issue227-user-location.png"))
            marker.configure(headingDegrees: nil, mapHeading: 0)
            try await Task.sleep(for: .milliseconds(50))
            let haloPreview = UIGraphicsImageRenderer(bounds: canvas.bounds, format: format).image { _ in
                canvas.drawHierarchy(in: canvas.bounds, afterScreenUpdates: true)
            }
            let reds = try haloReds(in: haloPreview)
            #expect(reds.allSatisfy { $0 > 0.39 }, "32pt 배경이 실제로 표시돼야 한다")
            #expect((reds.max()! - reds.min()!) < 0.04, "배경 중심이 원 중심에서 벗어나면 안 된다")
        }

        @Test("헤드 원본 이미지를 유지하면서 사용자 방향과 지도 회전을 부모에 반영한다",
              arguments: [(0.0, 0.0), (90, 0), (180, 0), (270, 0), (0, 90), (150, 0), (270, 40)])
        func rotatesHeadingOnly(headingDegrees: Double, mapHeading: Double) throws {
            let marker = HomeUserLocationAnnotationView(annotation: nil, reuseIdentifier: "test")
            marker.configure(headingDegrees: headingDegrees, mapHeading: mapHeading)
            marker.layoutIfNeeded()
            let heading = try image(in: marker, id: "user-location-heading-image")
            let dot = try image(in: marker, id: "user-location-dot-image")
            let container = try #require(find(in: marker, id: "user-location-heading-container"))
            let angle = (headingDegrees - mapHeading) * .pi / 180
            #expect(abs(container.transform.a - cos(angle)) < 0.000_001)
            #expect(abs(container.transform.b - sin(angle)) < 0.000_001)
            #expect(dot.transform == .identity)
            #expect(heading.transform == .identity, "원본 이미지에 고정 회전을 덧붙이지 않는다")
            let direction = (headingDegrees - mapHeading) * .pi / 180
            let forward = CGPoint(x: sin(direction), y: -cos(direction))
            let center = heading.convert(CGPoint(x: heading.bounds.midX, y: heading.bounds.midY), to: marker)
            let offset = CGPoint(x: center.x - dot.center.x, y: center.y - dot.center.y)
            #expect(abs(offset.x * forward.y - offset.y * forward.x) < 0.000_001)
            #expect(offset.x * forward.x + offset.y * forward.y > 0)
            #expect(abs(hypot(offset.x, offset.y) - (17.0 / 2 + 2 + 12.36133 / 2)) < 0.000_001)
            marker.configure(headingDegrees: nil, mapHeading: mapHeading)
            #expect(container.isHidden)
            #expect(!heading.isHidden)
            #expect(!dot.isHidden)
        }

        @Test("홈에서는 센서·시뮬레이터 위치를 같은 마커로 표시하고 제자리 방향 변경도 반영한다",
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
            let heading = try #require(find(in: marker, id: "user-location-heading-container"))
            let camera = map.camera.copy() as! MKMapCamera
            camera.heading = 90
            map.setCamera(camera, animated: false)
            coordinator.mapViewDidChangeVisibleRegion(map)
            let angle = (180 - map.camera.heading) * .pi / 180
            #expect(abs(heading.transform.a - cos(angle)) < 0.000_001)
            #expect(abs(heading.transform.b - sin(angle)) < 0.000_001)
        }

        private func image(in marker: UIView, id: String) throws -> UIImageView {
            try #require(find(in: marker, id: id) as? UIImageView)
        }

        private func find(in view: UIView, id: String) -> UIView? {
            if view.accessibilityIdentifier == id { return view }
            return view.subviews.compactMap { find(in: $0, id: id) }.first
        }

        private func haloReds(in image: UIImage) throws -> [Double] {
            let source = try #require(image.cgImage)
            var pixels = [UInt8](repeating: 0, count: source.width * source.height * 4)
            return try pixels.withUnsafeMutableBytes { bytes in
                let context = try #require(CGContext(data: bytes.baseAddress, width: source.width, height: source.height,
                    bitsPerComponent: 8, bytesPerRow: source.width * 4,
                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
                context.draw(source, in: CGRect(x: 0, y: 0, width: source.width, height: source.height))
                return [(58.0, 70.0), (82, 70), (70, 58), (70, 82)].map { x, y in
                    let index = (Int(y * image.scale) * source.width + Int(x * image.scale)) * 4
                    return Double(bytes[index]) / 255
                }
            }
        }
    }
}
