import ComposableArchitecture
import MapKit
import SwiftUI
import Testing
import UIKit
@testable import fingerprint_library

extension IndoorMapSerialTests {
    @MainActor
    struct HomeMapDesignScreenTests {
        @Test("홈·추천의 공통 툴바에서 장바구니 이동 후 화면을 복구한다", arguments: [false, true])
        func opensBasketFromSharedToolbar(isRecommendation: Bool) async throws {
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
            initial.home.departmentName = "반도체공학과"
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
            let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
            let window = UIWindow(windowScene: scene)
            let root = isRecommendation
                ? AnyView(NavigationStack {
                    HomeView(store: store.scope(state: \.home, action: \.home),
                             mapStore: store.scope(state: \.indoorMap, action: \.indoorMap))
                })
                : AnyView(AppView(store: store))
            let host = UIHostingController(rootView: root)
            host.overrideUserInterfaceStyle = .dark
            window.rootViewController = host
            window.makeKeyAndVisible()
            defer { window.isHidden = true; window.rootViewController = nil }
            try await waitUntil { self.navigation(in: host) != nil }
            let navigation = try #require(navigation(in: host))
            try await Task.sleep(for: .seconds(2))
            saveSnapshot(window, name: isRecommendation ? "recommendation" : "home")
            let items = navigation.navigationBar.items ?? []
            let buttons = items.flatMap { $0.trailingItemGroups.flatMap(\.barButtonItems) + ($0.rightBarButtonItems ?? []) }
            let basket = try #require(buttons.first {
                $0.accessibilityIdentifier == "library-top-bar-basket" || $0.accessibilityLabel == "책바구니" || $0.title == "책바구니"
            })
            let action = try #require(basket.action)
            #expect(UIApplication.shared.sendAction(action, to: basket.target, from: basket, for: nil))
            try await waitUntil { isRecommendation ? store.home.basket != nil : store.bookSearch.basket != nil }
            try await waitUntil { navigation.viewControllers.count == 2 }
            navigation.popViewController(animated: false)
            try await waitUntil { isRecommendation ? store.home.basket == nil : store.bookSearch.basket == nil }
            #expect(store.indoorMap.selectedFloorID == floor.id)
            #expect(store.home.recommendedBooks == books)
        }

        private func navigation(in controller: UIViewController) -> UINavigationController? {
            if let value = controller as? UINavigationController { return value }
            return controller.children.compactMap { navigation(in: $0) }.first
        }

        private func waitUntil(_ predicate: () -> Bool) async throws {
            for _ in 0..<100 {
                if predicate() { return }
                try await Task.sleep(for: .milliseconds(50))
            }
            #expect(predicate(), "툴바 표시 또는 화면 전환 시간이 초과됐습니다")
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
