import MapKit
import Testing
import UIKit
@testable import fingerprint_library

extension IndoorMapSerialTests {
    @MainActor
    struct MapUserLocationStackingScreenTests {
        @Test("시설·찜과 같은 좌표에서도 사용자 위치가 선택 상태와 관계없이 위에 보인다",
              arguments: [HomeMapMarker.Kind.favorite, .stairs, .elevator], [false, true])
        func userStaysAboveMarkers(kind: HomeMapMarker.Kind, navigationAppearance: Bool) async throws {
            let data = IndoorMapTestData.map()
            let floor = try #require(data.floors.first)
            let position = IndoorPosition(coordinate: IndoorMapTestData.point, floorOrdinal: floor.ordinal,
                horizontalAccuracy: 0, timestamp: IndoorMapTestData.now, source: .sensor, headingDegrees: 0)
            func parent(markers: [HomeMapMarker]) -> IndoorMapKitView {
                IndoorMapKitView(map: data, floor: floor, selectedFeatureID: nil,
                    position: position, showsUserLocation: false, isPlacingOrigin: false, cameraRequest: nil,
                    onSelect: { _ in }, onPlaceOrigin: { _ in }, navigationAppearance: navigationAppearance,
                    navigationBearingRadians: 0, appearance: .home, homeMarkers: markers)
            }
            let coordinator = parent(markers: []).makeCoordinator()
            let map = coordinator.makeMapView()
            map.frame = CGRect(x: 0, y: 0, width: 390, height: 600)
            let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
            let window = UIWindow(windowScene: scene)
            let host = UIViewController()
            window.rootViewController = host
            host.view.addSubview(map)
            window.makeKeyAndVisible()
            defer { coordinator.detachMapView(); window.isHidden = true; window.rootViewController = nil }
            coordinator.update(parent: parent(markers: []), in: map)
            map.setRegion(.init(center: position.coordinate.clCoordinate,
                latitudinalMeters: 100, longitudinalMeters: 100), animated: false)
            try await Task.sleep(for: .milliseconds(500))
            let user = try #require(map.annotations.compactMap { map.view(for: $0) as? MapUserLocationAnnotationView }.first)
            let center = user.convert(CGPoint(x: user.bounds.midX, y: user.bounds.midY), to: window)
            let expected = try pixel(snapshot(window), at: center)
            let marker = HomeMapMarker(id: "overlap", kind: kind, floorID: floor.id,
                coordinate: position.coordinate, title: "겹친 마커")
            coordinator.update(parent: parent(markers: [marker]), in: map)
            try await Task.sleep(for: .milliseconds(250))
            let annotation = try #require(map.annotations.compactMap { $0 as? HomeMapPointAnnotation }.first)
            let icon = try #require(map.view(for: annotation))
            #expect(user.zPriority.rawValue > icon.zPriority.rawValue)
            #expect(user.zPriority.rawValue > icon.selectedZPriority.rawValue)
            #expect(user.selectedZPriority.rawValue > icon.selectedZPriority.rawValue)
            for selected in [false, true] {
                if selected { map.selectAnnotation(annotation, animated: false) }
                try await Task.sleep(for: .milliseconds(200))
                #expect(!user.isHidden && user.alpha > 0)
                let image = snapshot(window)
                let actual = try pixel(image, at: center)
                for index in 0..<3 {
                    #expect(abs(actual[index] - expected[index]) < 0.03,
                        "겹친 마커를 선택해도 현재 위치 원의 픽셀이 보존되어야 합니다")
                }
                try image.pngData()?.write(to: FileManager.default.temporaryDirectory
                    .appendingPathComponent("user-above-\(kind.rawValue)-\(navigationAppearance)-\(selected).png"))
            }
        }

        private func snapshot(_ window: UIWindow) -> UIImage {
            UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
        }

        private func pixel(_ image: UIImage, at point: CGPoint) throws -> [Double] {
            let source = try #require(image.cgImage)
            let pixel = try #require(source.cropping(to: CGRect(x: point.x * image.scale,
                y: point.y * image.scale, width: 1, height: 1)))
            var rgba = [UInt8](repeating: 0, count: 4)
            try rgba.withUnsafeMutableBytes { bytes in
                let context = try #require(CGContext(data: bytes.baseAddress, width: 1, height: 1,
                    bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
                context.draw(pixel, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            }
            return rgba.prefix(3).map { Double($0) / 255 }
        }
    }
}
