import ComposableArchitecture
import MapKit
import SwiftUI
import Testing
import UIKit
@testable import fingerprint_library

extension IndoorMapSerialTests {
    @MainActor
    struct HomeMapDesignScreenTests {
        @Test("홈·추천의 카트·찜 상태 전환 후 화면 복구를 확인한다", arguments: [false, true])
        func restoresHomeAfterNavigation(isRecommendation: Bool) async throws {
            let fixture = try await makeFixture()
            let store = fixture.store
            let (window, host) = try makeWindow(store: store, isRecommendation: isRecommendation)
            defer { window.isHidden = true; window.rootViewController = nil }
            try await waitUntil { self.navigation(in: host) != nil }
            let navigation = try #require(navigation(in: host))
            try await Task.sleep(for: .seconds(2))
            saveSnapshot(window, name: isRecommendation ? "recommendation" : "home")
            #expect(navigation.isNavigationBarHidden)
            // 두 탭의 SwiftUI 상단바가 보내는 액션으로 화면 전환과 복귀를 확인한다.
            store.send(isRecommendation ? .home(.basketButtonTapped) : .bookSearch(.basketButtonTapped))
            try await waitUntil { isRecommendation ? store.home.basket != nil : store.bookSearch.basket != nil }
            try await waitUntil { navigation.viewControllers.count == 2 && !navigation.isNavigationBarHidden }
            navigation.popViewController(animated: true)
            try await waitUntil { isRecommendation ? store.home.basket == nil : store.bookSearch.basket == nil }
            try await waitUntil { navigation.transitionCoordinator == nil && navigation.isNavigationBarHidden }
            if !isRecommendation {
                store.send(.bookSearch(.favoritesButtonTapped))
                try await waitUntil { store.bookSearch.favorites != nil }
                try await waitUntil { navigation.viewControllers.count == 2 && !navigation.isNavigationBarHidden }
                navigation.popViewController(animated: true)
                try await waitUntil { store.bookSearch.favorites == nil && navigation.isNavigationBarHidden }
                try await waitUntil { navigation.transitionCoordinator == nil }
                try await Task.sleep(for: .milliseconds(300))
                saveSnapshot(window, name: "home-restored")
            }
            #expect(store.indoorMap.selectedFloorID == fixture.floorID)
            #expect(store.home.recommendedBooks == fixture.books)
        }

        @Test("홈 지도 카메라의 표시 콜백을 선택적으로 측정한다",
              .enabled(if: ProcessInfo.processInfo.environment["HOME_MAP_CAMERA_PROBE"] == "1",
                       "측정하려면 테스트 환경에 HOME_MAP_CAMERA_PROBE=1을 설정한다"))
        func measuresCameraCallbacks() async throws {
            let fixture = try await makeFixture()
            let (window, host) = try makeWindow(store: fixture.store, isRecommendation: false)
            defer { window.isHidden = true; window.rootViewController = nil }
            try await waitUntil { self.findMap(in: host.view) != nil }
            let map = try #require(findMap(in: host.view))
            let probe = HomeMapCameraFrameProbe(map: map)
            probe.start()
            defer { probe.stop() }
            try await Task.sleep(for: .seconds(3))
            print("HOME_MAP_CAMERA_METRICS \(probe.report())")
        }

        private struct Fixture {
            let store: StoreOf<AppFeature>
            let floorID: UUID
            let books: [Book]
        }

        private func makeFixture() async throws -> Fixture {
            let map = try await BundledIndoorMapLoader().loadLibrary()
            let labels = try await BundledShelfLabelLoader().loadLibrary(on: map)
            // 이 검사는 경로 계산을 하지 않는다. 실제 도면과 별개로 준비된 빈 경로 자료를 공급한다.
            let navigationData = IndoorNavigationData(
                graph: .init(schemaVersion: 1, layoutVersion: "ui-test", hardSearchRadiusMeters: 100, nodes: [], edges: []),
                shelves: .init(datasetID: "ui-test", mode: .library, destinations: []),
                diagnostics: .init(isolatedNodeIDs: [], connectedComponents: [], outsideFloorNodeIDs: [], crossFloorEdgeIDs: [])
            )
            let floor = try #require(map.floors.first { $0.ordinal == 2 })
            let books = (0..<4).map(BookHoldingTestData.book)
            var initial = AppFeature.State()
            initial.hasCheckedProfile = true
            initial.hasStartedRecommendationSession = true
            initial.home.recommendedBooks = books
            initial.home.popularBooks = books
            initial.home.$userProfile.withLock {
                $0 = try? UserProfile(
                    affiliationKey: ["POSTECH 학부", "학과 및 학부", "반도체공학과"],
                    departmentName: "반도체공학과", interests: ["수학"]
                )
            }
            initial.indoorMap.map = map
            initial.indoorMap.navigation = navigationData
            initial.indoorMap.shelfLabels = labels
            initial.indoorMap.selectedFloorID = floor.id
            initial.indoorMap.requestCamera(.initialFloor(floor.id))
            let store = Store(initialState: initial) { AppFeature() } withDependencies: {
                $0.indoorLocationClient = .testValue
                $0.bookFavoritesClient.load = { [] }
                $0.searchHistoryClient.load = { [] }
                $0.bookBasketClient.load = { [] }
                $0.bookHoldingsClient.fetch = { _ in [] }
            }
            return Fixture(store: store, floorID: floor.id, books: books)
        }

        private func makeWindow(store: StoreOf<AppFeature>, isRecommendation: Bool) throws -> (UIWindow, UIViewController) {
            let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
            let window = UIWindow(windowScene: scene)
            let root = isRecommendation
                ? AnyView(HomeView(store: store.scope(state: \.home, action: \.home),
                                   mapStore: store.scope(state: \.indoorMap, action: \.indoorMap)))
                : AnyView(AppView(store: store))
            let host = UIHostingController(rootView: root.environment(\.scenePhase, .active))
            host.overrideUserInterfaceStyle = .dark
            window.rootViewController = host
            window.makeKeyAndVisible()
            return (window, host)
        }

        private func navigation(in controller: UIViewController) -> UINavigationController? {
            if let value = controller as? UINavigationController { return value }
            return controller.children.compactMap { navigation(in: $0) }.first
        }

        private func findMap(in view: UIView) -> MKMapView? {
            if let map = view as? MKMapView { return map }
            return view.subviews.compactMap { findMap(in: $0) }.first
        }

        private func waitUntil(_ predicate: () -> Bool) async throws {
            for _ in 0..<100 {
                if predicate() { return }
                try await Task.sleep(for: .milliseconds(50))
            }
            try #require(predicate(), "툴바 표시 또는 화면 전환 시간이 초과됐습니다")
        }

        private func saveSnapshot(_ window: UIWindow, name: String) {
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            try? image.pngData()?.write(to: FileManager.default.temporaryDirectory
                .appendingPathComponent("issue83-\(name).png"))
        }
    }
}
