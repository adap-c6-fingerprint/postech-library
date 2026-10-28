import ComposableArchitecture
import MapKit
import os
import SwiftUI
import Testing
import UIKit
@testable import fingerprint_library

extension IndoorMapSerialTests {
    @MainActor
    struct IndoorMapInitialRenderingTests {
        @Test("화면 밖에서 활성화된 renderer는 배치·카메라 적용 후 한 번만 다시 그린다")
        func redrawsAfterUsableLayoutWithoutMovingCamera() async throws {
            let parent = syntheticParent()
            let coordinator = parent.makeCoordinator()
            let view = coordinator.makeMapView()
            // MapKit 이벤트의 순서를 직접 제어한다. 실제 픽셀 표시는 아래 별도 검사에서 확인한다.
            view.delegate = nil
            coordinator.update(parent: parent, in: view)
            let renderer = InitialOverlayRendererSpy(overlay: try #require(view.overlays.first))
            coordinator.mapView(view, didAdd: [renderer])
            await Task.yield()
            #expect(renderer.redrawCount == 0)

            let window = try host(view, size: CGSize(width: 80, height: 40))
            defer { window.isHidden = true; coordinator.detachMapView() }
            await Task.yield()
            #expect(renderer.redrawCount == 0)
            #expect(coordinator.pendingCameraRequest != nil)

            view.frame = CGRect(x: 0, y: 0, width: 390, height: 800)
            view.setNeedsLayout()
            view.layoutIfNeeded()
            try await waitUntil { renderer.redrawCount == 1 }
            #expect(coordinator.pendingCameraRequest == nil)

            let camera = view.camera.copy() as! MKMapCamera
            camera.heading = 35
            camera.centerCoordinateDistance *= 0.8
            view.setCamera(camera, animated: false)
            let expected = view.camera.copy() as! MKMapCamera
            for _ in 0..<3 {
                coordinator.mapView(view, didAdd: [renderer])
                coordinator.mapView(view, regionDidChangeAnimated: false)
                coordinator.update(parent: parent, in: view)
                view.setNeedsLayout()
                view.layoutIfNeeded()
            }
            try await Task.sleep(for: .milliseconds(30))
            #expect(renderer.redrawCount == 1)
            #expect(abs(view.camera.centerCoordinateDistance - expected.centerCoordinateDistance) < 0.1)
            #expect(abs(view.camera.heading - expected.heading) < 0.01)
            #expect(abs(view.centerCoordinate.latitude - expected.centerCoordinate.latitude) < 0.000001)
            #expect(abs(view.centerCoordinate.longitude - expected.centerCoordinate.longitude) < 0.000001)
        }

        @Test("층 전환·화면 해제 이후 이전 renderer의 지연 갱신을 버린다")
        func cancelsObsoleteRedraws() async throws {
            let first = syntheticParent()
            let coordinator = first.makeCoordinator()
            let view = coordinator.makeMapView()
            view.delegate = nil
            coordinator.update(parent: first, in: view)
            let window = try host(view, size: CGSize(width: 390, height: 800))
            defer { window.isHidden = true; coordinator.detachMapView() }
            let old = InitialOverlayRendererSpy(overlay: try #require(view.overlays.first))
            coordinator.mapView(view, didAdd: [old])
            coordinator.update(parent: syntheticParent(floorIndex: 1, requestID: 2), in: view)
            view.layoutIfNeeded()
            let current = InitialOverlayRendererSpy(overlay: try #require(view.overlays.first))
            coordinator.mapView(view, didAdd: [old, current])
            try await waitUntil { current.redrawCount == 1 }
            #expect(old.redrawCount == 0)

            coordinator.update(parent: first, in: view)
            view.layoutIfNeeded()
            let detached = InitialOverlayRendererSpy(overlay: try #require(view.overlays.first))
            coordinator.mapView(view, didAdd: [detached])
            coordinator.detachMapView()
            coordinator.mapView(view, didAdd: [detached])
            try await Task.sleep(for: .milliseconds(30))
            #expect(detached.redrawCount == 0)
        }

        @Test("새 지도 뷰의 3·4층 도형이 줌 없이 첫 화면에 그려진다", arguments: [2, 3], [0, 1, 2])
        func drawsFixturesBeforeInteraction(ordinal: Int, attempt: Int) async throws {
            let map = try await BundledIndoorMapLoader().loadLibrary()
            let floor = try #require(map.floors.first { $0.ordinal == ordinal })
            let labels = try await BundledShelfLabelLoader().loadLibrary(on: map)
            var initial = IndoorMapFeature.State()
            initial.map = map
            initial.selectedFloorID = floor.id
            initial.shelfLabels = labels
            initial.requestCamera(.initialFloor(floor.id))
            let store = Store(initialState: initial) { IndoorMapFeature() }
            let controller = UIHostingController(rootView: IndoorMapView(
                store: store, showsDestinationCard: false, showsCurrentLocationButton: false))
            let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
            let window = UIWindow(windowScene: scene)
            window.overrideUserInterfaceStyle = .light
            window.rootViewController = controller
            window.makeKeyAndVisible()
            defer { window.isHidden = true; window.rootViewController = nil }

            var image: UIImage?
            var coveredFixtures = 0
            var visibleFixtures = 0
            for _ in 0..<60 {
                try await Task.sleep(for: .milliseconds(50))
                guard let view = mapView(in: controller.view) else { continue }
                let labelFrames = view.annotations.compactMap { annotation -> CGRect? in
                    guard let label = view.view(for: annotation), !label.isHidden, label.alpha > 0 else { return nil }
                    return controller.view.convert(label.bounds, from: label).insetBy(dx: -4, dy: -4)
                }
                let points = map.features.compactMap { feature -> CGPoint? in
                    guard feature.kind == .fixture, feature.floorID == floor.id else { return nil }
                    let rect = MapKitGeometry.mapRect(for: feature.geometry)
                    guard !rect.isNull else { return nil }
                    let center = MKMapPoint(x: rect.midX, y: rect.midY).coordinate
                    guard feature.geometry.contains(.init(latitude: center.latitude, longitude: center.longitude)) else {
                        return nil
                    }
                    let point = view.convert(center, toPointTo: controller.view)
                    let sample = CGRect(x: point.x - 3, y: point.y - 3, width: 6, height: 6)
                    guard controller.view.bounds.insetBy(dx: 20, dy: 80).contains(sample),
                          !(point.x < 100 && point.y > controller.view.bounds.midY),
                          !labelFrames.contains(where: { $0.intersects(sample) }) else { return nil }
                    return point
                }
                guard points.count >= 10 else { continue }
                let format = UIGraphicsImageRendererFormat()
                format.scale = 1
                let snapshot = UIGraphicsImageRenderer(bounds: controller.view.bounds, format: format).image { _ in
                    controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
                }
                image = snapshot
                visibleFixtures = points.count
                coveredFixtures = try countVisibleFixtures(in: snapshot, at: points)
                if Double(coveredFixtures) / Double(visibleFixtures) >= 0.95 { break }
            }
            #expect(visibleFixtures >= 10)
            #expect(visibleFixtures > 0 && Double(coveredFixtures) / Double(visibleFixtures) >= 0.95,
                    "서가 번호에 가리지 않은 책장 위치의 95% 이상이 줌 없이 그려져야 합니다: \(coveredFixtures)/\(visibleFixtures)")
            if let image {
                let path = FileManager.default.temporaryDirectory
                    .appending(path: "indoor-initial-\(ordinal + 1)f-\(attempt).png")
                try image.pngData()?.write(to: path)
                print("초기 도형 표시 검증: \(path.path), fixtures: \(coveredFixtures)/\(visibleFixtures)")
            }
        }

        private func syntheticParent(floorIndex: Int = 0, requestID: Int = 1) -> IndoorMapKitView {
            let source = IndoorMapTestData.map()
            let geometry = IndoorMapGeometry.polygon([IndoorMapTestData.square.map {
                IndoorMapCoordinate(latitude: 36 + ($0.latitude - 36) * 0.1,
                                    longitude: 129 + ($0.longitude - 129) * 0.1)
            }])
            let map = IndoorMap(formatVersion: source.formatVersion, venue: source.venue,
                                floors: source.floors.map {
                IndoorMapFloor(id: $0.id, ordinal: $0.ordinal, name: $0.name, geometry: geometry)
            }, features: [], diagnostics: [])
            let floor = map.floors[floorIndex]
            return IndoorMapKitView(map: map, floor: floor, selectedFeatureID: nil, position: nil,
                                    showsUserLocation: false, isPlacingOrigin: false,
                                    cameraRequest: .init(id: requestID, target: .floor(floor.id)),
                                    onSelect: { _ in }, onPlaceOrigin: { _ in })
        }

        private func host(_ view: UIView, size: CGSize) throws -> UIWindow {
            let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
            let window = UIWindow(windowScene: scene)
            let controller = UIViewController()
            window.rootViewController = controller
            controller.view.addSubview(view)
            view.frame = CGRect(origin: .zero, size: size)
            window.makeKeyAndVisible()
            window.layoutIfNeeded()
            view.layoutIfNeeded()
            return window
        }

        private func waitUntil(_ predicate: () -> Bool) async throws {
            for _ in 0..<100 {
                if predicate() { return }
                try await Task.sleep(for: .milliseconds(10))
            }
            #expect(predicate(), "초기 도형 재그리기가 실행되지 않았습니다.")
        }

        private func mapView(in view: UIView) -> MKMapView? {
            if let map = view as? MKMapView { return map }
            return view.subviews.compactMap { mapView(in: $0) }.first
        }

        private func countVisibleFixtures(in image: UIImage, at points: [CGPoint]) throws -> Int {
            let cgImage = try #require(image.cgImage)
            // 각 책장 중심 근처를 RGBA로 읽는다. 작은 영역을 잘라 이미지 전체의 Y축 방향에 의존하지 않는다.
            var pixels = [UInt8](repeating: 0, count: 5 * 5 * 4)
            return try pixels.withUnsafeMutableBytes { buffer in
                let context = try #require(CGContext(data: buffer.baseAddress, width: 5, height: 5,
                    bitsPerComponent: 8, bytesPerRow: 5 * 4, space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
                let bytes = buffer.bindMemory(to: UInt8.self)
                return points.count { point in
                    guard let crop = cgImage.cropping(to: CGRect(x: point.x - 2, y: point.y - 2, width: 5, height: 5)) else {
                        return false
                    }
                    context.clear(CGRect(x: 0, y: 0, width: 5, height: 5))
                    context.draw(crop, in: CGRect(x: 0, y: 0, width: 5, height: 5))
                    return stride(from: 0, to: 100, by: 4).contains { index in
                        let red = Int(bytes[index]), green = Int(bytes[index + 1]), blue = Int(bytes[index + 2])
                        return red > 180 && red < 240 && green > 145 && green < 210
                            && blue > 100 && blue < 180 && red - green > 15 && green - blue > 20
                    }
                }
            }
        }
    }
}

private final class InitialOverlayRendererSpy: MKOverlayRenderer, @unchecked Sendable {
    private let redraws = OSAllocatedUnfairLock(initialState: 0)
    var redrawCount: Int { redraws.withLock { $0 } }

    override func setNeedsDisplay() {
        redraws.withLock { $0 += 1 }
        super.setNeedsDisplay()
    }
}
