import Foundation
import Testing
@testable import fingerprint_library

struct IndoorNavigationTests {
    @Test("방향·원본 ID·좌표를 보존하고 데이터셋 내부 키로 목적지를 찾는다")
    func loadsAndResolves() async throws {
        let root = try NavigationTestFixture.directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let (map, data) = try await NavigationTestFixture.load(root)
        #expect(data.graph.nodes.map(\.id) == ["a", "b"])
        #expect(data.graph.edges.first?.direction == .directed)
        #expect(data.graph.nodes[0].coordinate == .init(latitude: 36.001, longitude: 129.003))
        let key = ShelfKey(datasetID: "test-demo", value: "mock-01")
        let destination = try data.shelves.destination(for: key)
        #expect(data.shelves.mode == .mock)
        #expect(destination.arrivalNodeID == "b")
        #expect(destination.geometry == map.features.first { $0.kind == .unit }?.geometry)
        #expect(destination.floorID == map.floors.first?.id)
        #expect(throws: ShelfDirectory.LookupError.unmappedShelf(.init(datasetID: "library", value: "mock-01"))) {
            try data.shelves.destination(for: .init(datasetID: "library", value: "mock-01"))
        }
        #expect(throws: ShelfDirectory.LookupError.unmappedShelf(.init(datasetID: "test-demo", value: "unknown"))) {
            try data.shelves.destination(for: .init(datasetID: "test-demo", value: "unknown"))
        }
    }

    enum GraphCorruption: CaseIterable, Sendable {
        case version, schema, duplicateID, emptyID, missingFloor, wrongOrdinal, wrongRole
        case wrongGeometry, invalidCoordinate, missingEndpoint, wrongEndpoint, selfLoop
        case wrongDirection, wrongCategory, accessibleStairs, sameFloorSeconds, zeroLength, crossFloorWalkway
    }

    @Test("잘못된 그래프를 탐색 전에 거부한다", arguments: GraphCorruption.allCases)
    func rejectsGraph(_ corruption: GraphCorruption) async throws {
        let root = try NavigationTestFixture.directory()
        defer { try? FileManager.default.removeItem(at: root) }
        if corruption == .crossFloorWalkway { try NavigationTestFixture.addUpperFloor(root) }
        try NavigationTestFixture.edit("routing-graph.geojson", at: root) { json in
            var fs = json["features"] as! [[String: Any]]
            var node = fs[0]["properties"] as! [String: Any]
            var edge = fs[2]["properties"] as! [String: Any]
            switch corruption {
            case .version: json["layout_version"] = "other-layout"
            case .schema: json["schema_version"] = 2
            case .duplicateID: fs[2]["id"] = "a"
            case .emptyID: fs[0]["id"] = " "
            case .missingFloor: node["level_id"] = UUID().uuidString
            case .wrongOrdinal: node["level"] = 99
            case .wrongRole: node["role"] = "shelf"
            case .wrongGeometry: fs[0]["geometry"] = ["type": "LineString", "coordinates": [NavigationTestFixture.a, NavigationTestFixture.b]]
            case .invalidCoordinate: fs[0]["geometry"] = ["type": "Point", "coordinates": [200, 36]]
            case .missingEndpoint: edge["to"] = "missing"
            case .wrongEndpoint: fs[2]["geometry"] = ["type": "LineString", "coordinates": [NavigationTestFixture.b, NavigationTestFixture.a]]
            case .selfLoop: edge["to"] = "a"
            case .wrongDirection: edge["direction"] = "reverse"
            case .wrongCategory: edge["category"] = "teleport"
            case .accessibleStairs: edge["category"] = "stairs"
            case .sameFloorSeconds: edge["traversal_seconds"] = 10
            case .zeroLength:
                fs[1]["geometry"] = fs[0]["geometry"]
                fs[2]["geometry"] = ["type": "LineString", "coordinates": [NavigationTestFixture.a, NavigationTestFixture.a]]
            case .crossFloorWalkway:
                node["level_id"] = NavigationTestFixture.upperID
                node["level"] = 0
            }
            fs[0]["properties"] = node
            fs[2]["properties"] = edge
            json["features"] = fs
        }
        try NavigationTestFixture.pin(root)
        await expectInvalid(root, file: "routing-graph.geojson")
    }

    enum ShelfCorruption: CaseIterable, Sendable {
        case dataset, version, duplicateKey, emptyKey, unknownElement, unknownNode, wrongFloor, wrongKind, noShelves
    }

    @Test("서가 매핑의 데이터셋·층·도형·도착점 불일치를 거부한다", arguments: ShelfCorruption.allCases)
    func rejectsShelves(_ corruption: ShelfCorruption) async throws {
        let root = try NavigationTestFixture.directory()
        defer { try? FileManager.default.removeItem(at: root) }
        try NavigationTestFixture.edit("shelves.json", at: root) { json in
            var shelves = json["shelves"] as! [[String: Any]]
            switch corruption {
            case .dataset: json["dataset_id"] = "library"
            case .version: json["layout_version"] = "other-version"
            case .duplicateKey: shelves.append(shelves[0])
            case .emptyKey: shelves[0]["key"] = " "
            case .unknownElement: shelves[0]["element_id"] = UUID().uuidString
            case .unknownNode: shelves[0]["arrival_node_id"] = "unknown"
            case .wrongFloor: shelves[0]["level_id"] = UUID().uuidString
            case .wrongKind: shelves[0]["element_kind"] = "amenity"
            case .noShelves: shelves = []
            }
            json["shelves"] = shelves
        }
        try NavigationTestFixture.pin(root)
        await expectInvalid(root, file: "shelves.json")
    }

    @Test("변조·교체된 파일은 버전 문자열이 같아도 해시로 거부한다", arguments: ["routing-graph.geojson", "shelves.json", "IMDFData/level.geojson"])
    func rejectsMixedFiles(_ file: String) async throws {
        let root = try NavigationTestFixture.directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent(file)
        var bytes = try Data(contentsOf: url)
        bytes.append(contentsOf: [0x20])
        try bytes.write(to: url)
        await expectInvalid(root, file: file)
    }

    @Test("도면 외부 노드·고립 노드를 보존하고 약한 연결 진단을 제공한다")
    func diagnostics() async throws {
        let root = try NavigationTestFixture.directory()
        defer { try? FileManager.default.removeItem(at: root) }
        try NavigationTestFixture.edit("routing-graph.geojson", at: root) { json in
            var fs = json["features"] as! [[String: Any]]
            fs.append(NavigationTestFixture.node("outside", point: [129.02, 36.02]))
            json["features"] = fs
        }
        try NavigationTestFixture.pin(root)
        let (_, data) = try await NavigationTestFixture.load(root)
        #expect(data.diagnostics.isolatedNodeIDs == ["outside"])
        #expect(data.diagnostics.outsideFloorNodeIDs == ["outside"])
        #expect(data.diagnostics.connectedComponents == [["a", "b"], ["outside"]])
    }

    @Test("층간 비용이 없는 원본을 보존하며 임시 초·거리 값을 생성하지 않는다")
    func preservesUnknownCrossFloorCost() async throws {
        let root = try NavigationTestFixture.directory()
        defer { try? FileManager.default.removeItem(at: root) }
        try NavigationTestFixture.addUpperFloor(root)
        try NavigationTestFixture.edit("routing-graph.geojson", at: root) { json in
            var fs = json["features"] as! [[String: Any]]
            var node = fs[0]["properties"] as! [String: Any]
            node["level"] = 0; node["level_id"] = NavigationTestFixture.upperID
            fs[0]["properties"] = node
            var edge = fs[2]["properties"] as! [String: Any]
            edge["category"] = "elevator"
            fs[2]["properties"] = edge
            json["features"] = fs
        }
        try NavigationTestFixture.pin(root)
        let (_, data) = try await NavigationTestFixture.load(root)
        #expect(data.graph.edges.first?.traversalSeconds == nil)
        #expect(data.diagnostics.crossFloorEdgeIDs == ["edge"])
    }

    @Test("파일 누락을 빈 그래프로 성공 처리하지 않는다")
    func missingGraph() async throws {
        let root = try NavigationTestFixture.directory()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.removeItem(at: root.appendingPathComponent("routing-graph.geojson"))
        let map = try await BundledIndoorMapLoader().load(directory: root.appendingPathComponent("IMDFData"))
        do {
            _ = try await BundledIndoorNavigationLoader().load(directory: root, on: map)
            Issue.record("없는 그래프를 성공으로 처리했습니다.")
        } catch let error as IndoorMapLoadError {
            guard case .missingResource(let path) = error else { Issue.record("missingResource가 필요합니다."); return }
            #expect(path == "routing-graph.geojson")
        }
    }

    @Test("화면 지도와 데이터셋이 다르면 같은 버전이어도 거부한다")
    func rejectsDifferentMap() async throws {
        let root = try NavigationTestFixture.directory()
        defer { try? FileManager.default.removeItem(at: root) }
        await #expect(throws: IndoorMapLoadError.self) {
            try await BundledIndoorNavigationLoader().load(directory: root, on: IndoorMapTestData.map())
        }
    }

    @Test("manifest의 임의 파일 경로를 허용하지 않는다")
    func rejectsUnexpectedMapFiles() async throws {
        let root = try NavigationTestFixture.directory()
        defer { try? FileManager.default.removeItem(at: root) }
        try NavigationTestFixture.edit("dataset.json", at: root) { json in
            var hashes = json["map_files_sha256"] as! [String: String]
            hashes["../other.json"] = String(repeating: "0", count: 64)
            json["map_files_sha256"] = hashes
        }
        await expectInvalid(root, file: "dataset.json")
    }

    private static var hasC5Navigation: Bool {
        guard let url = Bundle.main.url(forResource: "IndoorMaps", withExtension: nil) else { return false }
        return FileManager.default.fileExists(atPath: url.appendingPathComponent("C5/dataset.json").path)
    }

    @Test("실제 C5 번들의 노드·연결·목업 목적지를 함께 검증한다", .enabled(if: hasC5Navigation, "C5 로컬 가져오기 필요"))
    func loadsC5() async throws {
        let map = try await BundledIndoorMapLoader().loadC5()
        let data = try await BundledIndoorNavigationLoader().loadC5(on: map)
        #expect(data.graph.nodes.count == 168)
        #expect(data.graph.edges.count == 178)
        #expect(data.diagnostics.connectedComponents.count == 1)
        #expect(data.diagnostics.isolatedNodeIDs.isEmpty)
        #expect(data.diagnostics.outsideFloorNodeIDs.count == 1)
        #expect(data.diagnostics.crossFloorEdgeIDs.count == 5)
        #expect(data.shelves.datasetID == "c5-demo")
        #expect(data.shelves.mode == .mock)
        #expect(data.shelves.destinations.count == 3)
        #expect(Set(data.shelves.destinations.map(\.floorID)).count >= 2)
        for destination in data.shelves.destinations {
            #expect(data.graph.nodes.contains { $0.id == destination.arrivalNodeID && $0.floorID == destination.floorID })
        }
    }

    private func expectInvalid(_ root: URL, file: String) async {
        do {
            _ = try await NavigationTestFixture.load(root)
            Issue.record("손상된 \(file)을 성공으로 처리했습니다.")
        } catch let error as IndoorMapLoadError {
            guard case .invalidData(let actual, _) = error else {
                Issue.record("invalidData가 필요합니다: \(error)")
                return
            }
            #expect(actual == file)
        } catch { Issue.record("예상하지 못한 오류: \(error)") }
    }
}
