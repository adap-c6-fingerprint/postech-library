import CryptoKit
import Foundation
import Testing

@testable import fingerprint_library

struct IndoorRouteDistanceDataTests {
    private func fixture() throws -> URL {
        let root = try NavigationTestFixture.directory()
        try NavigationTestFixture.addUpperFloor(root)
        try NavigationTestFixture.edit("routing-graph.geojson", at: root) { object in
            var features = object["features"] as! [[String: Any]]
            var upper = NavigationTestFixture.node("upper", point: NavigationTestFixture.b)
            var properties = upper["properties"] as! [String: Any]
            properties["level_id"] = NavigationTestFixture.upperID
            properties["level"] = 0
            upper["properties"] = properties
            features.append(upper)
            features.append([
                "type": "Feature", "id": "lift",
                "geometry": ["type": "LineString", "coordinates": [NavigationTestFixture.b, NavigationTestFixture.b]],
                "properties": [
                    "role": "edge", "from": "b", "to": "upper", "direction": "undirected", "category": "elevator",
                    "accessible": true,
                ],
            ])
            object["features"] = features
        }
        try NavigationTestFixture.write(
            [
                "schema_version": 1, "dataset_id": "test-demo", "layout_version": "test-layout-v1",
                "edges": [["edge_id": "lift", "meters": 3.5, "source": "estimated", "basis": "시연용 가정"]],
            ],
            file: "cross-floor-distances.json", at: root)
        try NavigationTestFixture.pin(root)
        try pinDistance(root)
        return root
    }
    private func pinDistance(_ root: URL) throws {
        let bytes = try Data(contentsOf: root.appendingPathComponent("cross-floor-distances.json"))
        let hash = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        try NavigationTestFixture.edit("dataset.json", at: root) { $0["cross_floor_distances_sha256"] = hash }
    }
    @Test("층간 추정값은 버전·해시가 일치하는 별도 자료로 읽는다")
    func loadsPinnedEstimates() async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let (_, data) = try await NavigationTestFixture.load(root)
        #expect(data.transitionDistances == ["lift": .init(meters: 3.5, source: .estimated)])
    }
    @Test(
        "변조·다른 버전·중복·누락·음수·알 수 없는 출처를 거부한다",
        arguments: ["hash", "layout", "duplicate", "missing", "negative", "source"])
    func rejectsMismatchedDistances(_ kind: String) async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        try NavigationTestFixture.edit("cross-floor-distances.json", at: root) { object in
            var entries = object["edges"] as! [[String: Any]]
            switch kind {
            case "layout": object["layout_version"] = "different"
            case "duplicate": entries.append(entries[0])
            case "missing": entries = []
            case "negative": entries[0]["meters"] = -1
            case "source": entries[0]["source"] = "unknown"
            default: entries[0]["meters"] = 100
            }
            object["edges"] = entries
        }
        if kind != "hash" { try pinDistance(root) }
        do {
            _ = try await NavigationTestFixture.load(root)
            Issue.record("잘못된 거리 자료를 수용했습니다: \(kind)")
        } catch is IndoorMapLoadError {}
    }

    @Test("수평 직선거리보다 짧은 층간 거리는 탐색 전에 로딩 단계에서 거부한다")
    func rejectsImpossibleTransitionAtLoad() async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        try NavigationTestFixture.edit("routing-graph.geojson", at: root) { object in
            var features = object["features"] as! [[String: Any]]
            let upper = features.firstIndex { $0["id"] as? String == "upper" }!
            features[upper]["geometry"] = ["type": "Point", "coordinates": NavigationTestFixture.a]
            let lift = features.firstIndex { $0["id"] as? String == "lift" }!
            features[lift]["geometry"] = [
                "type": "LineString", "coordinates": [NavigationTestFixture.b, NavigationTestFixture.a]
            ]
            object["features"] = features
        }
        try NavigationTestFixture.pin(root)
        do {
            _ = try await NavigationTestFixture.load(root)
            Issue.record("수평 직선거리보다 짧은 층간 거리 자료를 수용했습니다.")
        } catch let IndoorMapLoadError.invalidData(file, reason) {
            #expect(file == "cross-floor-distances.json")
            #expect(reason.contains("수평 직선거리"))
        }
    }
}
