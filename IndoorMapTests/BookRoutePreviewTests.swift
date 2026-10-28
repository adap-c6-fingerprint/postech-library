import ComposableArchitecture
import CryptoKit
import Foundation
import Testing
@testable import fingerprint_library

extension IndoorMapSerialTests {
    @MainActor
    struct BookRoutePreviewTests {
        @Test("동물농장 목데이터는 API 조회 없이 실제 3층 337-A fixture 하나에 연결된다")
        func highlightsOnlyAnimalFarmShelf() async throws {
            let book = BookRoutePreviewSample.book
            #expect(book.id == "primo:alma991003794555103286")
            #expect(book.controlNumber == book.id)
            #expect(BookHoldingsClient.recordID(for: book) == BookRoutePreviewSample.recordID)
            let map = try await BundledIndoorMapLoader().loadLibrary()
            let labels = try await BundledShelfLabelLoader().loadLibrary(on: map)
            var initial = BookShelfMapFeature.State(book: book)
            initial.holdings[book.id] = .loaded([BookRoutePreviewSample.holding])
            initial.map.map = map
            initial.map.shelfLabels = labels
            let shelf = try #require(labels.first { $0.fixtureNumber == "S-3F-564-A" })
            #expect(shelf.realNumber == "337")
            #expect(shelf.mapElementID.sourceID == UUID(uuidString: "8a71e4fa-9952-42e8-b8ce-513b0b738b1a"))
            let store = TestStore(initialState: initial) { BookShelfMapFeature() } withDependencies: {
                $0.bookHoldingsClient.fetch = { _ in
                    Issue.record("고정 목데이터 화면에서는 실제 소장 조회를 하면 안 됩니다.")
                    return []
                }
            }
            await store.send(.task)
            await store.receive(.map(.retryTapped))
            await store.receive(.resolveLocations) {
                $0.resolutions[book.id] = BookHoldingShelfResolver().resolve(
                    [BookRoutePreviewSample.holding], on: map, labels: labels
                )
                $0.map.selectedFloorID = shelf.floorID
                $0.map.requestCamera(.features([shelf.mapElementID]))
            }
            #expect(store.state.books == [book])
            #expect(store.state.shelves == [shelf])
            #expect(store.state.highlightedFeatureIDs == [shelf.mapElementID])
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
