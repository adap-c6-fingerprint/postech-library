import ComposableArchitecture
import MapKit
import SwiftUI
import Testing
import UIKit

@testable import fingerprint_library

extension IndoorMapSerialTests {
    @MainActor
    struct IndoorRouteScreenTests {
        @Test("실제 navigation push·뒤로가기 동안 위치 구독을 유지하고 지도를 화면 폭에 맞춘다")
        func navigatesWithoutRestartingLocation() async throws {
            let map = try await BundledIndoorMapLoader().loadC5()
            let data = try await BundledIndoorNavigationLoader().loadC5(on: map)
            let shelf = try #require(data.shelves.destinations.first)
            let origin = try #require(
                data.graph.nodes.first {
                    $0.floorID == shelf.floorID && $0.id != shelf.arrivalNodeID
                })
            let position = IndoorPosition(
                coordinate: origin.coordinate, floorOrdinal: origin.level,
                horizontalAccuracy: 0, timestamp: Date(), source: .simulation
            )
            var initial = AppFeature.State()
            initial.indoorMap.map = map
            initial.indoorMap.navigation = data
            initial.indoorMap.selectedFloorID = shelf.floorID
            initial.indoorMap.selectedShelfKey = shelf.key
            initial.indoorMap.latestPosition = position
            initial.indoorMap.authorization = .authorized(precise: true)
            initial.indoorMap.requestCamera(.floor(shelf.floorID))
            let probe = SubscriptionProbe()
            let events = AsyncStream<IndoorLocationEvent>.makeStream()
            defer { events.continuation.finish() }
            let store = Store(initialState: initial) {
                AppFeature()
            } withDependencies: {
                $0.date.now = position.timestamp
                $0.indoorLocationClient.events = {
                    await probe.started()
                    return events.stream
                }
                $0.indoorRouteClient.search = { try IndoorRouteSearchEngine().search($0) }
            }
            let scene = try #require(
                UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
            let window = UIWindow(windowScene: scene)
            let host = UIHostingController(rootView: AppView(store: store))
            window.rootViewController = host
            window.makeKeyAndVisible()
            defer {
                window.isHidden = true
                window.rootViewController = nil
                store.send(.indoorMap(.disappeared))
            }
            try await waitUntil { store.indoorMap.isActive && self.navigation(in: host) != nil }
            let navigation = try #require(navigation(in: host))
            #expect(navigation.viewControllers.count == 1)
            let homeMap = try #require(
                descendants(of: host.view).compactMap { $0 as? MKMapView }.first)
            #expect(abs(homeMap.bounds.width - window.bounds.width) < 1)
            try await waitUntil { homeMap.camera.centerCoordinateDistance < 5_000 }
            try await Task.sleep(for: .milliseconds(250))
            saveSnapshot(window, name: "home")

            store.send(.indoorMap(.routeSettingsTapped))
            try await waitUntil {
                navigation.viewControllers.count == 2 && store.indoorMap.route != nil
            }
            try await Task.sleep(for: .milliseconds(400))
            #expect(store.isRouteSettingsPresented)
            #expect(store.indoorMap.isActive)
            #expect(await probe.count == 1)
            #expect(navigation.topViewController?.navigationItem.title == "경로 설정")
            saveSnapshot(window, name: "route-settings")
            store.send(.indoorMap(.routeSheetExpansionChanged(true)))
            try await Task.sleep(for: .milliseconds(300))
            saveSnapshot(window, name: "route-settings-expanded")

            // native 뒤로가기와 같은 pop을 실행해 SwiftUI binding→TCA 정리까지 확인한다.
            navigation.popViewController(animated: false)
            try await waitUntil { !store.isRouteSettingsPresented && store.indoorMap.route == nil }
            #expect(navigation.viewControllers.count == 1)
            #expect(store.indoorMap.isActive)
            #expect(store.indoorMap.currentPosition == position)
            #expect(!store.indoorMap.isRouteSheetExpanded)
            #expect(await probe.count == 1)
        }

        private actor SubscriptionProbe {
            var count = 0
            func started() { count += 1 }
        }

        private func waitUntil(_ predicate: () -> Bool) async throws {
            for _ in 0..<40 {
                if predicate() { return }
                try await Task.sleep(for: .milliseconds(50))
            }
            #expect(predicate(), "화면 전환 또는 위치 수신을 기다리는 중 시간이 초과됐습니다.")
        }

        private func navigation(in controller: UIViewController) -> UINavigationController? {
            if let controller = controller as? UINavigationController { return controller }
            return controller.children.compactMap { navigation(in: $0) }.first
        }

        private func descendants(of view: UIView) -> [UIView] {
            [view] + view.subviews.flatMap { descendants(of: $0) }
        }

        private func saveSnapshot(_ window: UIWindow, name: String) {
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(
                "indoor-ui-\(name).png")
            try? image.pngData()?.write(to: url)
            print("지도 UI 검증 이미지: \(url.path)")
        }
    }
}
