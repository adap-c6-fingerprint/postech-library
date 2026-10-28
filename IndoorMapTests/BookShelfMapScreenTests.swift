import ComposableArchitecture
import MapKit
import SwiftUI
import Testing
import UIKit
@testable import fingerprint_library

extension IndoorMapSerialTests {
    @MainActor
    struct BookShelfMapScreenTests {
        @Test("단일 도서와 바구니 3권의 서가 강조·뒤로가기와 재진입을 확인한다")
        func navigatesAndHighlightsHoldingShelf() async throws {
            let map = try await BundledIndoorMapLoader().loadLibrary()
            let labels = try await BundledShelfLabelLoader().loadLibrary(on: map)
            let third = try #require(map.floors.first { $0.ordinal == 2 })
            let book = BookHoldingTestData.book()
            let basket = (0..<3).map(BookHoldingTestData.book)
            var appInitial = AppFeature.State()
            appInitial.indoorMap.map = map
            appInitial.indoorMap.shelfLabels = labels
            appInitial.indoorMap.selectedFloorID = third.id
            appInitial.indoorMap.requestCamera(.initialFloor(third.id))
            let appStore = Store(initialState: appInitial) { AppFeature() }
            var searchInitial = BookSearchFeature.State()
            searchInitial.query = "검색 결과 유지"
            searchInitial.books = [book]
            searchInitial.basketBooks = basket
            searchInitial.hasSearched = true
            let searchStore = Store(initialState: searchInitial) { BookSearchFeature() } withDependencies: {
                $0.bookHoldingsClient.fetch = { recordID in
                    [BookHoldingTestData.holding(Int(String(recordID.suffix(1))) ?? 0)]
                }
                $0.indoorMapClient.load = { map }
                $0.indoorShelfLabelClient = .liveValue
                $0.indoorNavigationClient.load = { _ in throw IndoorNavigationLoadError.notPrepared }
                $0.searchHistoryClient.load = { [] }
                $0.bookFavoritesClient.load = { [] }
            }
            let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
            let window = UIWindow(windowScene: scene)
            let host = UIHostingController(rootView: LibraryMapView(store: appStore, searchStore: searchStore))
            window.rootViewController = host
            window.makeKeyAndVisible()
            defer {
                if searchStore.shelfMap != nil { searchStore.send(.shelfMap(.dismiss)) }
                window.isHidden = true
                window.rootViewController = nil
            }
            try await waitUntil { self.navigation(in: host) != nil }
            let navigation = try #require(navigation(in: host))
            let homeMap = try #require(descendants(of: host.view).compactMap { $0 as? MKMapView }.first)
            try await waitUntil { homeMap.camera.centerCoordinateDistance < 5_000 }
            let homeCamera = homeMap.camera.copy() as! MKMapCamera

            searchStore.send(.directionsButtonTapped(book))
            try await waitUntil {
                navigation.viewControllers.count == 2 && searchStore.shelfMap?.map.shelfLabels.count == 308
            }
            let destination = try #require(navigation.topViewController)
            let view = try #require(descendants(of: destination.view).compactMap { $0 as? MKMapView }.first)
            try await waitUntil { self.highlightedLabels(in: view) == ["S-3F-616-B"] }
            #expect(destination.navigationItem.title == "서가 위치")
            #expect(searchStore.shelfMap?.map.selectedFloorID == third.id)
            #expect(searchStore.shelfMap?.map.isActive == false)
            #expect(view.overlays.contains {
                (view.renderer(for: $0) as? MKOverlayPathRenderer)?.strokeColor == .systemOrange
            })
            try await Task.sleep(for: .seconds(1))
            try checkHighlightPosition(in: view, container: destination.view)
            saveSnapshot(window, name: "3f")

            #expect(descendants(of: destination.view).allSatisfy { !($0 is UISegmentedControl) })
            host.overrideUserInterfaceStyle = .dark
            try await Task.sleep(for: .milliseconds(250))
            #expect(highlightedLabels(in: view) == ["S-3F-616-B"])
            saveSnapshot(window, name: "3f-dark")
            host.overrideUserInterfaceStyle = .unspecified

            navigation.popViewController(animated: false)
            try await waitUntil { searchStore.shelfMap == nil && navigation.viewControllers.count == 1 }
            #expect(searchStore.query == searchInitial.query)
            #expect(searchStore.books == [book])
            #expect(searchStore.basketBooks == basket)
            #expect(appStore.indoorMap == appInitial.indoorMap)
            #expect(abs(homeMap.camera.centerCoordinateDistance - homeCamera.centerCoordinateDistance) < 0.1)

            searchStore.send(.directionsButtonTapped(book))
            try await waitUntil {
                navigation.viewControllers.count == 2 && searchStore.shelfMap?.shelves.count == 1
            }
            #expect(searchStore.shelfMap?.shelves.first?.fixtureNumber == "S-3F-616-B")
            navigation.popViewController(animated: false)
            try await waitUntil { searchStore.shelfMap == nil }

            searchStore.send(.basketDirectionsButtonTapped(Set(basket.map(\.id))))
            try await waitUntil {
                navigation.viewControllers.count == 2 && searchStore.shelfMap?.shelves.count == 3
            }
            let basketDestination = try #require(navigation.topViewController)
            let basketMap = try #require(descendants(of: basketDestination.view).compactMap { $0 as? MKMapView }.first)
            try await waitUntil {
                self.highlightedLabels(in: basketMap) == ["S-3F-616-B", "S-3F-612-B", "S-3F-608-B"]
            }
            try await Task.sleep(for: .seconds(1))
            #expect(searchStore.shelfMap?.books == basket)
            try checkHighlightPosition(in: basketMap, container: basketDestination.view)
            saveSnapshot(window, name: "three-books")
            navigation.popViewController(animated: false)
            try await waitUntil { searchStore.shelfMap == nil }
            #expect(searchStore.basketBooks == basket)
        }

        private func highlightedLabels(in map: MKMapView) -> Set<String> {
            Set(map.annotations.compactMap { annotation in
                guard let annotation = annotation as? IndoorShelfLabelAnnotation,
                      let view = map.view(for: annotation) as? IndoorShelfLabelView,
                      view.accessibilityTraits.contains(.selected), !view.isHidden else { return nil }
                return annotation.label.fixtureNumber
            })
        }

        private func checkHighlightPosition(in map: MKMapView, container: UIView) throws {
            let annotation = try #require(map.annotations.compactMap { $0 as? IndoorShelfLabelAnnotation }
                .first { map.view(for: $0)?.accessibilityTraits.contains(.selected) == true })
            let labelView = try #require(map.view(for: annotation))
            let point = map.convert(annotation.coordinate, toPointTo: map)
            let frame = map.convert(labelView.bounds, from: labelView)
            #expect(abs(frame.midX - point.x) < 1)
            #expect(abs(frame.midY - point.y) < 1)
            #expect(map.bounds.contains(frame))
            let mapFrame = container.convert(map.bounds, from: map)
            // 안내 카드에는 제목·청구기호 기반 안내·서가 버튼이 있어 최소 100pt의 표시 공간이 필요하다.
            #expect(mapFrame.maxY <= container.bounds.maxY - 100,
                    "카메라를 맞추는 지도 영역이 하단 서가 안내 카드와 겹치지 않아야 합니다.")
        }

        private func navigation(in controller: UIViewController) -> UINavigationController? {
            if let navigation = controller as? UINavigationController { return navigation }
            return controller.children.compactMap { navigation(in: $0) }.first
        }

        private func descendants(of view: UIView) -> [UIView] {
            [view] + view.subviews.flatMap { descendants(of: $0) }
        }

        private func waitUntil(_ predicate: () -> Bool) async throws {
            for _ in 0..<100 {
                if predicate() { return }
                try await Task.sleep(for: .milliseconds(50))
            }
            #expect(predicate(), "청구기호 기반 서가 지도 표시 또는 화면 전환 시간이 초과됐습니다.")
        }

        private func saveSnapshot(_ window: UIWindow, name: String) {
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            let path = FileManager.default.temporaryDirectory.appendingPathComponent("book-shelf-map-\(name).png")
            try? image.pngData()?.write(to: path)
            print("청구기호 기반 서가 지도 검증 이미지: \(path.path)")
        }
    }
}
