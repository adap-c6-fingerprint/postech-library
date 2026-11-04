import ComposableArchitecture
import Foundation
import SwiftUI
import Testing
import UIKit
@testable import fingerprint_library

extension IndoorMapSerialTests {
    @MainActor
    struct BookRouteCurrentLocationTests {
        @Test("311-B 레이블이 없어도 전달한 다른 앱 위치에서 경로를 계산한다")
        func routesFromAppPosition() async throws {
            let fixture = try await Fixture.load()
            let start = try fixture.position(level: 2, index: 1)
            let labels = fixture.labels.filter { $0.fixtureNumber != "S-3F-512-B" }
            let session = try await BookRoutePreviewTestRouteLoader().load(
                on: fixture.map, labels: labels, start: start, stops: [fixture.stop])
            #expect(session.start == start)
            #expect(session.route.start.actualCoordinate == start.coordinate)
            #expect(session.map.floors.first { $0.id == session.route.start.floorID }?.ordinal == 2)
            #expect(session.route.floorChanges.isEmpty)
        }

        @Test("번들에 층간 연결이 없으면 다른 층의 출발점을 고정 위치로 바꾸지 않는다")
        func doesNotInventCrossFloorConnection() async throws {
            let fixture = try await Fixture.load()
            let start = try fixture.position(level: 3)
            await #expect(throws: IndoorRoutingError.noRoute) {
                try await fixture.session(from: start)
            }
        }

        @Test("미리보기 뒤 출발을 누르면 이동한 최신 위치로 다시 계산한 세션만 시작한다")
        func recalculatesAtDeparture() async throws {
            let fixture = try await Fixture.load()
            let old = try await fixture.session(from: fixture.position(level: 2))
            let latest = try fixture.position(level: 2, index: 2)
            let updated = try await fixture.session(from: latest)
            var initial = BookRoutePreviewFeature.State()
            initial.previewSession = old
            let store = TestStore(initialState: initial) { BookRoutePreviewFeature() } withDependencies: {
                $0.date.now = latest.timestamp
                $0.bookRoutePreviewClient.load = { _, _, start, _ in
                    #expect(start == latest)
                    return updated
                }
            }
            await store.send(.startRequested(.ready(map: fixture.map, labels: fixture.labels,
                start: latest, stops: [fixture.stop]))) {
                $0.requestID = 1
                $0.previewSession = nil
                $0.isLoadingRoute = true
                $0.startsNavigationWhenLoaded = true
            }
            await store.receive(.routeLoaded(requestID: 1, updated)) {
                $0.isLoadingRoute = false
                $0.startsNavigationWhenLoaded = false
                $0.previewSession = updated
                $0.navigationSession = updated
            }
            #expect(store.state.navigationSession?.start.coordinate != old.start.coordinate)
            await store.send(.navigationStarted) { $0.navigationSession = nil }
            await store.finish()
        }

        @Test("위치가 없거나 층이 없으면 조회 중인 층·고정 서가로 대체하지 않는다")
        func requiresKnownPositionAndFloor() async throws {
            let fixture = try await Fixture.load()
            var state = BookShelfMapFeature.State(book: fixture.stop.book)
            state.map.map = fixture.map
            state.map.shelfLabels = fixture.labels
            state.map.selectedFloorID = fixture.map.floors.first?.id
            state.holdings[fixture.stop.book.id] = .loaded(fixture.stop.holdings)
            state.resolutions[fixture.stop.book.id] = BookHoldingShelfResolver().resolve(
                fixture.stop.holdings, on: fixture.map, labels: fixture.labels)
            #expect(BookRoutePreviewRequest(state: state) == .failed(IndoorRoutingError.invalidPosition.localizedDescription))
            let known = try fixture.position(level: 2)
            let noFloor = IndoorPosition(coordinate: known.coordinate, floorOrdinal: nil,
                horizontalAccuracy: 1, timestamp: known.timestamp, source: .sensor)
            #expect(BookRoutePreviewRequest(state: state, start: noFloor)
                == .failed(IndoorRoutingError.unknownFloor.localizedDescription))
        }

        @Test("만료된 앱 위치로는 경로 Client를 호출하거나 안내를 시작하지 않는다")
        func rejectsExpiredPosition() async throws {
            let fixture = try await Fixture.load()
            let start = try fixture.position(level: 2)
            let store = TestStore(initialState: BookRoutePreviewFeature.State()) {
                BookRoutePreviewFeature()
            } withDependencies: {
                $0.date.now = start.timestamp.addingTimeInterval(31)
                $0.bookRoutePreviewClient.load = { _, _, _, _ in
                    Issue.record("만료된 위치로 경로 계산을 요청했습니다.")
                    throw IndoorRoutingError.invalidPosition
                }
            }
            await store.send(.startRequested(.ready(map: fixture.map, labels: fixture.labels,
                start: start, stops: [fixture.stop]))) {
                $0.requestID = 1
                $0.routeError = IndoorRoutingError.invalidPosition.localizedDescription
            }
            #expect(store.state.navigationSession == nil)
            await store.finish()
        }

        @Test("미리보기 화면은 앱 루트의 위치를 읽고 완료·실패 후 위치 수신마다 재계산하지 않는다", arguments: [false, true])
        func previewUsesRootLocationWithoutContinuousRecalculation(routeFails: Bool) async throws {
            let fixture = try await Fixture.load()
            let start = try fixture.position(level: 2, index: 1)
            let session = try await fixture.session(from: start)
            let received = LockIsolated<[IndoorPosition]>([])
            let holdings = fixture.stop.holdings
            var initial = IndoorMapFeature.State()
            initial.map = fixture.map
            initial.latestPosition = start
            initial.authorization = .authorized(precise: true)
            let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
            let window = UIWindow(windowScene: scene)
            let mapStore = Store(initialState: initial) { IndoorMapFeature() } withDependencies: {
                $0.date = .constant(start.timestamp)
            }
            let routeStore = Store(initialState: BookRoutePreviewFeature.State()) {
                BookRoutePreviewFeature()
            } withDependencies: {
                $0.date = .constant(start.timestamp)
                $0.bookRoutePreviewClient.load = { _, _, position, _ in
                    received.withValue { $0.append(position) }
                    if routeFails { throw IndoorRoutingError.noRoute }
                    return session
                }
            }
            let host = withDependencies {
                $0.date = .constant(start.timestamp)
                $0.indoorMapClient.load = { fixture.map }
                $0.indoorShelfLabelClient.supports = { _ in true }
                $0.indoorShelfLabelClient.load = { _ in fixture.labels }
                $0.bookHoldingsClient.fetch = { _ in holdings }
            } operation: {
                let preview = BookRoutePreviewView(books: [fixture.stop.book], routeStore: routeStore)
                return UIHostingController(rootView: NavigationStack {
                    preview
                }.environment(\.indoorRouteMapStore, mapStore))
            }
            window.rootViewController = host
            window.makeKeyAndVisible()
            defer { window.isHidden = true; window.rootViewController = nil }
            let deadline = Date().addingTimeInterval(5)
            while received.value.isEmpty, Date() < deadline {
                try await Task.sleep(for: .milliseconds(30))
            }
            #expect(received.value == [start])
            try await Task.sleep(for: .milliseconds(100))
            mapStore.send(.locationEvent(.position(try fixture.position(level: 2, index: 2))))
            try await Task.sleep(for: .milliseconds(100))
            #expect(received.value == [start], "미리보기 결과는 위치 갱신만으로 재계산하지 않아야 합니다.")
        }

        @Test("별도 UIKit 상세 시트도 블루닷을 가진 같은 지도 Store를 전달받는다")
        func nativeDetailSheetKeepsSimulationMapStore() async throws {
            let fixture = try await Fixture.load()
            let start = try fixture.position(level: 2, index: 1)
            var mapState = IndoorMapFeature.State()
            mapState.map = fixture.map
            mapState.latestPosition = start
            mapState.authorization = .authorized(precise: true)
            let mapStore = Store(initialState: mapState) { IndoorMapFeature() } withDependencies: {
                $0.date = .constant(start.timestamp)
            }
            var detailState = BookDetailFeature.State(book: fixture.stop.book)
            detailState.hasLoaded = true
            detailState.holdingsState = .loaded(fixture.stop.holdings)
            detailState.relatedBooksState = .loaded([])
            let detailStore = Store(initialState: detailState) { BookDetailFeature() } withDependencies: {
                $0.date = .constant(start.timestamp)
                $0.bookFavoritesClient.load = { [] }
            }
            let controller = BookDetailSheetPresenter.Controller(
                store: detailStore, mapStore: mapStore, presentation: BookDetailSheetPresentation(),
                onDismiss: {}, onFrameChange: { _ in })
            let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
            let window = UIWindow(windowScene: scene)
            window.rootViewController = controller
            window.makeKeyAndVisible()
            defer { controller.tearDown(); window.isHidden = true; window.rootViewController = nil }
            let deadline = Date().addingTimeInterval(5)
            while controller.presentedViewController == nil || controller.transitionCoordinator != nil {
                try #require(Date() < deadline, "네이티브 상세 시트 표시가 완료되지 않았습니다")
                try await Task.sleep(for: .milliseconds(30))
            }
            let sheet = try #require(controller.presentedViewController as? UIHostingController<BookDetailSheet>)
            #expect(sheet.rootView.mapStore === mapStore)
            #expect(sheet.rootView.mapStore.currentPosition == start)
            let moved = try fixture.position(level: 2, index: 2)
            mapStore.send(.locationEvent(.position(moved)))
            #expect(sheet.rootView.mapStore.currentPosition == moved)
            controller.tearDown()
            while sheet.presentingViewController != nil {
                try #require(Date() < deadline, "상세 시트 종료가 완료되지 않았습니다")
                try await Task.sleep(for: .milliseconds(30))
            }
        }

        private struct Fixture {
            let map: IndoorMap
            let labels: [IndoorShelfLabel]
            let graph: RoutingGraph
            let referenceNodeIDs: [String]
            let stop: BookRouteCandidateStop

            @MainActor static func load() async throws -> Self {
                let map = try await BundledIndoorMapLoader().loadLibrary()
                let labels = try await BundledShelfLabelLoader().loadLibrary(on: map)
                let shelf = try #require(labels.first { $0.fixtureNumber == "S-3F-564-A" })
                let reference = try await BookRoutePreviewTestRouteLoader().load(on: map, labels: labels, destination: shelf)
                return .init(map: map, labels: labels, graph: reference.graph, referenceNodeIDs: reference.route.nodeIDs,
                    stop: .init(book: BookHoldingTestData.book(), holdings: [BookRoutePreviewSample.holding], candidateShelves: [shelf]))
            }

            func position(level: Int, index: Int = 0) throws -> IndoorPosition {
                let routeNodes = referenceNodeIDs.compactMap { id in graph.nodes.first { $0.id == id && $0.level == level } }
                let candidates = routeNodes.isEmpty ? graph.nodes.filter { $0.level == level } : routeNodes
                let node = try #require(candidates.dropFirst(index).first)
                return .init(coordinate: node.coordinate, floorOrdinal: level,
                    horizontalAccuracy: 1, timestamp: Date(), source: .simulation)
            }

            func session(from start: IndoorPosition) async throws -> BookNavigationSession {
                try await BookRoutePreviewTestRouteLoader().load(on: map, labels: labels, start: start, stops: [stop])
            }
        }
    }
}
