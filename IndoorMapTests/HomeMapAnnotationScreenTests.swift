import ComposableArchitecture
import Foundation
import MapKit
import SwiftUI
import Testing
import UIKit
@testable import fingerprint_library

extension IndoorMapSerialTests {
    @MainActor
    struct HomeMapAnnotationScreenTests {
        @Test("모든 제공 이미지는 원본 색상의 30pt 아이콘으로 표시한다")
        func originalIcons() throws {
            let map = MKMapView()
            for kind in HomeMapMarker.Kind.allCases {
                let marker = HomeMapMarker(id: kind.rawValue, kind: kind, floorID: IndoorMapTestData.groundID,
                    coordinate: IndoorMapTestData.point, title: "테스트")
                let view = HomeMapAnnotationController.view(for: HomeMapPointAnnotation(marker), in: map)
                let image = try #require(view.image, "어노테이션 이미지 누락: \(kind.assetName ?? kind.rawValue)")
                #expect(image.renderingMode == .alwaysOriginal)
                #expect(image.size == CGSize(width: 30, height: 30))
                #expect(view.bounds.size == CGSize(width: 30, height: 30))
                if let assetName = kind.assetName {
                    let original = try #require(UIImage(named: assetName))
                    #expect(image.cgImage?.width == original.cgImage?.width)
                    #expect(image.cgImage?.height == original.cgImage?.height)
                }
                #expect(view.centerOffset == .zero)
            }
        }

        @Test("홈의 현재 층에만 아이콘을 표시하고 편의시설을 숨겨도 하트는 재생성하지 않는다")
        func filtersFloorAndKeepsFavorite() throws {
            let data = IndoorMapTestData.map()
            let lower = try #require(data.floors.first)
            let upper = try #require(data.floors.last)
            let favorite = HomeMapMarker(id: "favorite", kind: .favorite, floorID: lower.id,
                coordinate: IndoorMapTestData.point, title: "찜한 도서")
            let facility = HomeMapMarker(id: "stairs", kind: .stairs, floorID: lower.id,
                coordinate: IndoorMapTestData.point, title: "계단")
            let otherFloor = HomeMapMarker(id: "elevator", kind: .elevator, floorID: upper.id,
                coordinate: IndoorMapTestData.point, title: "엘리베이터")
            func parent(_ markers: [HomeMapMarker], floor: IndoorMapFloor, appearance: IndoorMapKitView.Appearance = .home) -> IndoorMapKitView {
                IndoorMapKitView(map: data, floor: floor, selectedFeatureID: nil, position: nil,
                    showsUserLocation: false, isPlacingOrigin: false, cameraRequest: nil,
                    onSelect: { _ in }, onPlaceOrigin: { _ in }, appearance: appearance, homeMarkers: markers)
            }
            let all = [favorite, facility, otherFloor]
            let coordinator = IndoorMapKitView.Coordinator(parent: parent(all, floor: lower))
            let map = coordinator.makeMapView()
            defer { coordinator.detachMapView() }
            coordinator.update(parent: parent(all, floor: lower), in: map)
            let original = try #require(map.annotations.compactMap { $0 as? HomeMapPointAnnotation }.first { $0.marker.id == favorite.id })
            #expect(map.annotations.compactMap { $0 as? HomeMapPointAnnotation }.count == 2)
            coordinator.update(parent: parent([favorite, otherFloor], floor: lower), in: map)
            #expect(map.annotations.compactMap { $0 as? HomeMapPointAnnotation }.first === original)
            coordinator.update(parent: parent(all, floor: upper), in: map)
            #expect(map.annotations.compactMap { $0 as? HomeMapPointAnnotation }.map(\.marker.id) == [otherFloor.id])
            coordinator.update(parent: parent(all, floor: upper, appearance: .standard), in: map)
            #expect(map.annotations.compactMap { $0 as? HomeMapPointAnnotation }.isEmpty)
        }

        @Test("찜 변경은 외부 요청 없이 로컬 위치를 표시하며 장바구니만 담은 책은 표시하지 않는다")
        func favoritesReachHomeMap() async throws {
            let map = try await BundledIndoorMapLoader().loadLibrary()
            let labels = try await BundledShelfLabelLoader().loadLibrary(on: map)
            let floor = try #require(map.floors.first { $0.ordinal == 2 })
            let keyStore = LockIsolated<Set<[String?]>>([])
            let requests = LockIsolated(0)
            let suite = "local-home-map-\(UUID())"
            defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
            let locations = BookLocationCacheClient.userDefaults(suiteName: suite)
            let book = BookHoldingTestData.book(0)
            var initial = AppFeature.State()
            initial.hasCheckedProfile = true
            initial.hasStartedRecommendationSession = true
            initial.indoorMap.map = map
            initial.indoorMap.selectedFloorID = floor.id
            initial.indoorMap.shelfLabels = labels
            initial.bookSearch.basketBooks = [book]
            let store = Store(initialState: initial) { AppFeature() } withDependencies: {
                $0.date.now = IndoorMapTestData.now
                $0.indoorLocationClient = .testValue
                $0.bookFavoritesClient.load = { keyStore.value }
                $0.bookFavoritesClient.save = { keyStore.setValue($0) }
                $0.searchHistoryClient.load = { [] }
                $0.bookBasketClient.load = { [] }
                $0.bookLocationCacheClient = locations
                $0.bookHoldingsClient.fetch = { _ in requests.withValue { $0 += 1 }; return [] }
                $0.bookSearchClient.search = { _, _ in requests.withValue { $0 += 1 }; return [] }
                $0.httpClient = HTTPClient(load: { _ in requests.withValue { $0 += 1 }; throw URLError(.notConnectedToInternet) })
                $0.indoorNavigationClient.load = { _ in
                    .init(graph: .init(schemaVersion: 1, layoutVersion: "ui-test", hardSearchRadiusMeters: 100, nodes: [], edges: []),
                          shelves: .init(datasetID: "ui-test", mode: .library, destinations: []),
                          diagnostics: .init(isolatedNodeIDs: [], connectedComponents: [], outsideFloorNodeIDs: [], crossFloorEdgeIDs: []))
                }
            }
            let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
            let window = UIWindow(windowScene: scene)
            let host = UIHostingController(rootView: AppView(store: store))
            host.overrideUserInterfaceStyle = .dark
            window.rootViewController = host
            window.makeKeyAndVisible()
            defer { window.isHidden = true; window.rootViewController = nil }
            try await waitUntil { self.map(in: host.view) != nil }
            let surface = try #require(self.map(in: host.view))
            let basic = surface.annotations.compactMap { $0 as? HomeMapPointAnnotation }
            #expect(basic.contains { $0.marker.kind == .stairs })
            #expect(basic.contains { $0.marker.kind == .elevator })
            #expect(basic.allSatisfy { [.stairs, .elevator].contains($0.marker.kind) })
            #expect(requests.value == 0)
            store.send(.bookSearch(.favoriteButtonTapped(book)))
            try await waitUntil { store.indoorMap.homeAnnotations.favoriteKeys.contains(book.recordKey) }
            #expect(!surface.annotations.compactMap { $0 as? HomeMapPointAnnotation }.contains { $0.marker.kind == .favorite })
            #expect(requests.value == 0)
            // 일반 상세 화면이 이미 받은 응답을 로컬에 보관하는 경로다. 찜으로 조회를 시작하지 않는다.
            let detail = Store(initialState: BookDetailFeature.State(book: book)) { BookDetailFeature() } withDependencies: {
                $0.bookLocationCacheClient = locations
            }
            detail.send(.holdingsLoaded([BookHoldingTestData.holding()]))
            try await waitUntil { surface.annotations.compactMap { $0 as? HomeMapPointAnnotation }.contains { $0.marker.kind == .favorite } }
            #expect(requests.value == 0)
            store.send(.indoorMap(.homeAnnotations(.amenitiesTapped)))
            try await waitUntil { surface.annotations.compactMap { $0 as? HomeMapPointAnnotation }.contains { $0.marker.kind == .toilet } }
            // 표시한 서가와 시설을 한 화면에 담아 실제 지도 합성을 확인한다.
            var rect = MKMapRect.null
            for annotation in surface.annotations.compactMap({ $0 as? HomeMapPointAnnotation }) {
                let point = MKMapPoint(annotation.coordinate)
                rect = rect.union(.init(x: point.x, y: point.y, width: 0.1, height: 0.1))
            }
            surface.setVisibleMapRect(rect, edgePadding: .init(top: 300, left: 85, bottom: 150, right: 40), animated: false)
            try await Task.sleep(for: .seconds(1))
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            try image.pngData()?.write(to: FileManager.default.temporaryDirectory.appendingPathComponent("issue229-home-annotations.png"))
            store.send(.indoorMap(.homeAnnotations(.amenitiesTapped)))
            try await waitUntil {
                surface.annotations.compactMap { $0 as? HomeMapPointAnnotation }.allSatisfy {
                    [.favorite, .stairs, .elevator].contains($0.marker.kind)
                }
            }
            #expect(surface.annotations.compactMap { $0 as? HomeMapPointAnnotation }.contains { $0.marker.kind == .stairs })
            #expect(surface.annotations.compactMap { $0 as? HomeMapPointAnnotation }.contains { $0.marker.kind == .favorite })
            #expect(requests.value == 0)
            store.send(.bookSearch(.favoriteButtonTapped(book)))
            try await waitUntil { !surface.annotations.compactMap { $0 as? HomeMapPointAnnotation }.contains { $0.marker.kind == .favorite } }
            #expect(surface.annotations.compactMap { $0 as? HomeMapPointAnnotation }.contains { $0.marker.kind == .elevator })
            #expect(store.indoorMap.homeAnnotations.holdings.isEmpty)
            #expect(requests.value == 0)
        }

        private func map(in view: UIView) -> MKMapView? {
            if let map = view as? MKMapView { return map }
            return view.subviews.compactMap { map(in: $0) }.first
        }

        private func waitUntil(_ predicate: () -> Bool) async throws {
            let deadline = Date().addingTimeInterval(5)
            while !predicate(), Date() < deadline { try await Task.sleep(for: .milliseconds(30)) }
            #expect(predicate(), "지도 어노테이션 갱신 시간이 초과됐습니다")
        }
    }
}
