import ComposableArchitecture
import CryptoKit
import Foundation
import Testing
@testable import fingerprint_library

extension IndoorMapSerialTests {
    @MainActor
    struct BookRoutePreviewTests {
        @Test("한 권·여러 권 입력을 순서와 원본 식별자 그대로 기본 목적지로 받는다", arguments: [1, 3])
        func preservesReceivedBooks(count: Int) throws {
            let books = (0..<count).map { BookHoldingTestData.book($0) }
            let destination = BookRoutePreviewDestination(books: books)
            let state = try #require(BookRoutePreviewFeature.makeShelfMapState(for: destination))
            #expect(destination.books == books)
            #expect(!destination.isTestMode)
            #expect(state.books == books)
            #expect(state.holdings.isEmpty)
            #expect(state.resolutions.isEmpty)
        }

        @Test("동일한 테스트 책을 전달해도 버튼을 누르기 전에는 목데이터를 주입하지 않는다")
        func doesNotInferTestModeFromBookID() throws {
            let destination = BookRoutePreviewDestination(books: [BookRoutePreviewSample.testItems[0].book])
            let state = try #require(BookRoutePreviewFeature.makeShelfMapState(for: destination))
            #expect(!destination.isTestMode)
            #expect(state.holdings.isEmpty)
        }

        @Test("일반 입력도 소장 조회·해석이 끝나면 모든 도서를 순서대로 경로 요청에 넣는다")
        func preparesReceivedBooksForRouting() async throws {
            let books = (0..<3).map { BookHoldingTestData.book($0) }
            var state = try #require(BookShelfMapFeature.State(books: books))
            #expect(BookRoutePreviewRequest(state: state) == .waiting)
            let map = try await BundledIndoorMapLoader().loadLibrary()
            let labels = try await BundledShelfLabelLoader().loadLibrary(on: map)
            state.map.map = map
            state.map.shelfLabels = labels
            for book in books {
                state.holdings[book.id] = .loaded([BookRoutePreviewSample.holding])
                state.resolutions[book.id] = BookHoldingShelfResolver().resolve(
                    [BookRoutePreviewSample.holding], on: map, labels: labels)
            }
            guard case let .ready(receivedMap, receivedLabels, stops) = BookRoutePreviewRequest(state: state) else {
                Issue.record("조회 완료 후 경로 계산 준비가 되지 않았습니다."); return
            }
            #expect(receivedMap == map && receivedLabels == labels)
            #expect(stops.map(\.book) == books)
            #expect(stops.allSatisfy { $0.shelf.fixtureNumber == "S-3F-564-A" })
            state.holdings[books[1].id] = .loading
            #expect(BookRoutePreviewRequest(state: state) == .waiting)
            state.holdings[books[1].id] = .failed("조회 실패")
            #expect(BookRoutePreviewRequest(state: state) == .failed("조회 실패"))
        }

        @Test("매칭 실패·복수 서가에서는 임의 목적지를 선택하지 않는다")
        func doesNotChooseArbitraryShelf() async throws {
            let book = BookHoldingTestData.book()
            var state = BookShelfMapFeature.State(book: book)
            let map = try await BundledIndoorMapLoader().loadLibrary()
            let labels = try await BundledShelfLabelLoader().loadLibrary(on: map)
            state.map.map = map
            state.map.shelfLabels = labels
            state.holdings[book.id] = .loaded([BookRoutePreviewSample.holding])
            for shelves in [[], Array(labels.prefix(2))] {
                state.resolutions[book.id] = [.init(holding: BookRoutePreviewSample.holding, outcome: .candidates(shelves))]
                guard case .failed = BookRoutePreviewRequest(state: state) else {
                    Issue.record("서가가 확정되지 않았는데 경로를 준비했습니다."); return
                }
            }
        }

        @Test("테스트 선택은 지정된 세 책으로 교체하고 원본 배열을 보존한다")
        func replacesDestinationsOnlyOnTestSelection() throws {
            let books = (0..<3).map { BookHoldingTestData.book($0) }
            var destination = BookRoutePreviewDestination(books: books)
            destination.useTestMode()
            let state = try #require(BookRoutePreviewFeature.makeShelfMapState(for: destination))
            #expect(destination.isTestMode)
            #expect(destination.books == BookRoutePreviewSample.testItems.map(\.book))
            #expect(state.books == destination.books)
            #expect(state.holdings == Dictionary(uniqueKeysWithValues:
                BookRoutePreviewSample.testItems.map { ($0.book.id, BookShelfMapFeature.HoldingsState.loaded([$0.holding])) }))
            #expect(books.count == 3)
            #expect(books.allSatisfy { $0.id != BookRoutePreviewSample.book.id })
            destination.useTestMode()
            #expect(destination.books.count == 3)
        }

        @Test("빈 입력·중복 ID·조회 상한 초과를 동물농장으로 대체하거나 일부만 선택하지 않는다")
        func keepsInvalidInputWithoutFallback() {
            let book = BookHoldingTestData.book()
            let inputs = [[], [book, book], (0..<4).map { BookHoldingTestData.book($0) }]
            for books in inputs {
                var destination = BookRoutePreviewDestination(books: books)
                #expect(destination.books == books)
                #expect(!destination.isTestMode)
                #expect(BookRoutePreviewFeature.makeShelfMapState(for: destination) == nil)
                destination.useTestMode()
                #expect(BookRoutePreviewFeature.makeShelfMapState(for: destination) != nil)
            }
        }

        @Test("테스트 세 책은 API 조회 없이 각각의 실제 서가에 연결된다")
        func highlightsTestShelves() async throws {
            let items = BookRoutePreviewSample.testItems
            let map = try await BundledIndoorMapLoader().loadLibrary()
            let labels = try await BundledShelfLabelLoader().loadLibrary(on: map)
            var destination = BookRoutePreviewDestination(books: [])
            destination.useTestMode()
            var initial = try #require(BookRoutePreviewFeature.makeShelfMapState(for: destination))
            initial.map.map = map
            initial.map.shelfLabels = labels
            let shelves = items.flatMap { BookHoldingShelfResolver().resolve([$0.holding], on: map, labels: labels).flatMap(\.shelves) }
            #expect(shelves.count == 3)
            let first = try #require(shelves.first)
            let store = TestStore(initialState: initial) { BookShelfMapFeature() } withDependencies: {
                $0.bookHoldingsClient.fetch = { _ in
                    Issue.record("고정 목데이터 화면에서는 실제 소장 조회를 하면 안 됩니다.")
                    return []
                }
            }
            await store.send(.task)
            await store.receive(.map(.retryTapped))
            await store.receive(.resolveLocations) {
                for item in items {
                    $0.resolutions[item.book.id] = BookHoldingShelfResolver().resolve([item.holding], on: map, labels: labels)
                }
                $0.map.selectedFloorID = first.floorID
                $0.map.requestCamera(.features(shelves.map(\.mapElementID)))
            }
            #expect(store.state.books == items.map(\.book))
            #expect(store.state.shelves == shelves)
            #expect(store.state.highlightedFeatureIDs == Set(shelves.map(\.mapElementID)))
            #expect(store.state.map.selectedFloor?.ordinal == 2)
            #expect(store.state.map.route == nil)
            #expect(!store.state.map.isActive)
            await store.finish()
        }

        @Test("첨부 navigation 세 파일을 원본 해시로 번들에 보존하고 목적지 UUID를 대조한다")
        func embedsOriginalNavigationFiles() async throws {
            let root = try #require(Bundle.main.url(forResource: "IndoorMaps", withExtension: nil))
                .appendingPathComponent("POSTECHLibrary")
            let hashes = [
                "navigation.json": "70ebce44d755b4573ed13c6afac2e2077252e9609cdbdba2f6e3900cdf3ecc87",
                "routing-graph.geojson": "2fe17357e151c5824261fdf9c98b54415a366d64188c5bffc26d659cb7d1bfcb",
                "navigation-feature-links.json": "4aef9a279aaf3727d3dab29d17e84d5b9f2d8265e60ac809fc76119d29053052"
            ]
            for (file, hash) in hashes {
                let data = try Data(contentsOf: root.appendingPathComponent(file))
                #expect(SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() == hash)
            }
            func json(_ file: String) throws -> [String: Any] {
                try #require(JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent(file))) as? [String: Any])
            }
            let metadata = try json("navigation.json")
            let links = try json("navigation-feature-links.json")
            let graph = try json("routing-graph.geojson")
            #expect(metadata["layout_version"] as? String == graph["layout_version"] as? String)
            #expect(metadata["layout_version"] as? String == links["layout_version"] as? String)
            #expect(metadata["routing_sha256"] as? String == hashes["routing-graph.geojson"])
            #expect(metadata["feature_links_sha256"] as? String == hashes["navigation-feature-links.json"])
            let features = try #require(links["features"] as? [[String: Any]])
            let matches = features.filter { $0["feature_id"] as? String == "8a71e4fa-9952-42e8-b8ce-513b0b738b1a" }
            #expect(matches.count == 1)
            let link = try #require(matches.first)
            #expect(link["feature_type"] as? String == "fixture")
            let nodes = try #require(graph["features"] as? [[String: Any]])
            let node = try #require(nodes.first { $0["id"] as? String == link["node_id"] as? String })
            let properties = try #require(node["properties"] as? [String: Any])
            #expect(properties["role"] as? String == "node")
            #expect(properties["level_id"] as? String == link["level_id"] as? String)
            let map = try await BundledIndoorMapLoader().loadLibrary()
            let fixture = try #require(map.features.first { $0.name == "S-3F-564-A" })
            #expect(fixture.floorID?.uuidString.lowercased() == link["level_id"] as? String)
            // UUID 연결 검사다. 그래프의 물리 층 번호와 IMDF ordinal의 일치 검사는 별도다.
        }
    }
}
