import ComposableArchitecture
import MapKit
import SwiftUI
import Testing
import UIKit
@testable import fingerprint_library

extension IndoorMapSerialTests {
    @MainActor
    struct IndoorShelfLabelScreenTests {
        @Test("앱 첫 로딩과 3·4층 전환에서 실제 서가 레이블을 표시하고 촬영 순서로 카메라를 옮기지 않는다")
        func displaysLabelsInHome() async throws {
            let map = try await BundledIndoorMapLoader().loadLibrary()
            let third = try #require(map.floors.first { $0.ordinal == 2 })
            let fourth = try #require(map.floors.first { $0.ordinal == 3 })
            var initial = AppFeature.State()
            initial.indoorMap.map = map
            initial.indoorMap.selectedFloorID = third.id
            initial.indoorMap.requestCamera(.initialFloor(third.id))
            let store = Store(initialState: initial) { AppFeature() } withDependencies: {
                $0.indoorShelfLabelClient = .liveValue
                $0.indoorNavigationClient.load = { _ in throw IndoorNavigationLoadError.notPrepared }
                $0.indoorLocationClient.events = { AsyncStream { $0.finish() } }
            }
            let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
            let window = UIWindow(windowScene: scene)
            let host = UIHostingController(rootView: AppView(store: store))
            window.rootViewController = host
            window.makeKeyAndVisible()
            defer {
                window.isHidden = true
                window.rootViewController = nil
                store.send(.indoorMap(.disappeared))
            }
            try await waitUntil { store.indoorMap.shelfLabels.count == 308 && self.mapView(in: host.view) != nil }
            let view = try #require(mapView(in: host.view))
            try await waitUntil { !view.annotations.compactMap { $0 as? IndoorShelfLabelAnnotation }.isEmpty }
            try await waitUntil { self.visibleLabels(in: view) > 0 }
            #expect(store.indoorMap.navigation == nil)
            #expect(store.indoorMap.shelfLabelError == nil)
            try await Task.sleep(for: .milliseconds(250))
            saveSnapshot(window, name: "3f")
            let camera = view.camera.copy() as! MKMapCamera
            store.send(.indoorMap(.floorSelected(fourth.id)))
            try await waitUntil {
                let labels = view.annotations.compactMap { $0 as? IndoorShelfLabelAnnotation }
                return !labels.isEmpty && labels.allSatisfy { $0.label.floorID == fourth.id }
            }
            #expect(abs(view.camera.centerCoordinateDistance - camera.centerCoordinateDistance) < 0.1)
            try await Task.sleep(for: .milliseconds(250))
            saveSnapshot(window, name: "4f")
            let close = view.camera.copy() as! MKMapCamera
            let focus = try #require(store.indoorMap.shelfLabels.first { label in
                guard label.floorID == fourth.id else { return false }
                if case .callNumberRange = label.content { return true }
                return false
            })
            close.centerCoordinate = IndoorShelfLabelAnnotation(focus).coordinate
            close.centerCoordinateDistance *= 0.45
            view.setCamera(close, animated: false)
            // MapKit의 충돌 레이블 페이드가 끝난 상태를 캡처한다.
            try await Task.sleep(for: .seconds(1))
            let frames = view.annotations.compactMap { annotation -> CGRect? in
                guard annotation is IndoorShelfLabelAnnotation, let labelView = view.view(for: annotation),
                      !labelView.isHidden, labelView.alpha > 0 else { return nil }
                return view.convert(labelView.bounds, from: labelView)
            }
            for index in frames.indices {
                for other in frames.indices where other > index {
                    #expect(!frames[index].intersects(frames[other]), "서가 레이블이 겹칩니다.")
                }
            }
            saveSnapshot(window, name: "4f-close")
        }

        private func mapView(in view: UIView) -> MKMapView? {
            if let map = view as? MKMapView { return map }
            return view.subviews.compactMap { mapView(in: $0) }.first
        }

        private func visibleLabels(in view: MKMapView) -> Int {
            view.annotations.compactMap { annotation -> MKAnnotationView? in
                guard annotation is IndoorShelfLabelAnnotation else { return nil }
                return view.view(for: annotation)
            }.filter { !$0.isHidden && $0.superview != nil && $0.alpha > 0 }.count
        }

        private func waitUntil(_ predicate: () -> Bool) async throws {
            for _ in 0..<60 {
                if predicate() { return }
                try await Task.sleep(for: .milliseconds(50))
            }
            #expect(predicate(), "실제 서가 레이블 표시를 기다리는 중 시간이 초과됐습니다.")
        }

        private func saveSnapshot(_ window: UIWindow, name: String) {
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("indoor-shelf-label-\(name).png")
            try? image.pngData()?.write(to: url)
            print("서가 레이블 UI 검증 이미지: \(url.path)")
        }
    }
}
