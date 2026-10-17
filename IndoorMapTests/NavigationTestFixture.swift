import CryptoKit
import Foundation
@testable import fingerprint_library

enum NavigationTestFixture {
    static let upperID = "00000000-0000-4000-8000-000000000099"
    static let a = [129.003, 36.001]
    static let b = [129.004, 36.002]

    static func directory() throws -> URL {
        let root = try IMDFTestFixture.makeDirectory()
        let files = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        let imdf = root.appendingPathComponent("IMDFData")
        try FileManager.default.createDirectory(at: imdf, withIntermediateDirectories: true)
        for file in files { try FileManager.default.moveItem(at: file, to: imdf.appendingPathComponent(file.lastPathComponent)) }
        let graph: [String: Any] = [
            "type": "FeatureCollection", "schema_version": 1, "layout_version": "test-layout-v1",
            "routing_config": ["hard_search_radius_meters": 25],
            "features": [node("a", point: a), node("b", point: b), [
                "type": "Feature", "id": "edge", "geometry": ["type": "LineString", "coordinates": [a, b]],
                "properties": ["role": "edge", "from": "a", "to": "b", "direction": "directed",
                               "category": "walkway", "accessible": true]
            ]]
        ]
        try write(graph, file: "routing-graph.geojson", at: root)
        try write([
            "schema_version": 1, "dataset_id": "test-demo", "layout_version": "test-layout-v1", "mode": "mock",
            "shelves": [["key": "mock-01", "name": "시연용 목적지", "level_id": IMDFTestFixture.floorID,
                         "element_kind": "unit", "element_id": IMDFTestFixture.unitID, "arrival_node_id": "b"]]
        ], file: "shelves.json", at: root)
        try write(["schema_version": 1, "dataset_id": "test-demo", "layout_version": "test-layout-v1"], file: "dataset.json", at: root)
        try pin(root)
        return root
    }

    static func node(_ id: String, point: [Double]) -> [String: Any] {
        ["type": "Feature", "id": id, "geometry": ["type": "Point", "coordinates": point],
         "properties": ["role": "node", "category": "destination", "name": id,
                        "level_id": IMDFTestFixture.floorID, "level": -1]]
    }

    static func addUpperFloor(_ root: URL) throws {
        try edit("IMDFData/level.geojson", at: root) { json in
            var features = json["features"] as! [[String: Any]]
            var upper = features[0]
            upper["id"] = upperID
            var properties = upper["properties"] as! [String: Any]
            properties["ordinal"] = 0
            upper["properties"] = properties
            features.append(upper)
            json["features"] = features
        }
    }

    static func edit(_ file: String, at root: URL, _ mutation: (inout [String: Any]) -> Void) throws {
        var json = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent(file))) as! [String: Any]
        mutation(&json)
        try write(json, file: file, at: root)
    }

    static func write(_ json: [String: Any], file: String, at root: URL) throws {
        try JSONSerialization.data(withJSONObject: json, options: [.sortedKeys]).write(to: root.appendingPathComponent(file))
    }

    static func pin(_ root: URL) throws {
        func hash(_ file: String) throws -> String {
            SHA256.hash(data: try Data(contentsOf: root.appendingPathComponent(file))).map { String(format: "%02x", $0) }.joined()
        }
        let hashes = try Dictionary(uniqueKeysWithValues: BundledIndoorNavigationLoader.mapFiles.map { ($0, try hash("IMDFData/" + $0)) })
        let graph = try hash("routing-graph.geojson")
        let shelves = try hash("shelves.json")
        try edit("dataset.json", at: root) {
            $0["map_files_sha256"] = hashes
            $0["routing_sha256"] = graph
            $0["shelves_sha256"] = shelves
        }
    }

    static func load(_ root: URL) async throws -> (IndoorMap, IndoorNavigationData) {
        let map = try await BundledIndoorMapLoader().load(directory: root.appendingPathComponent("IMDFData"))
        let data = try await BundledIndoorNavigationLoader().load(directory: root, on: map)
        return (map, data)
    }
}
