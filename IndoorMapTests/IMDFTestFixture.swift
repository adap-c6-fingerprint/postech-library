import Foundation

/// 외부 도면을 포함하지 않는 테스트 전용 GeoJSON.
enum IMDFTestFixture {
    static let floorID = "00000000-0000-4000-8000-000000000001"
    static let unitID = "00000000-0000-4000-8000-000000000002"

    static func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let polygon: [String: Any] = [
            "type": "Polygon", "coordinates": [[[129.0, 36.0], [129.01, 36.0], [129.01, 36.01], [129.0, 36.0]]]
        ]
        for (index, kind) in ["level", "unit", "venue", "footprint", "fixture", "opening", "amenity"].enumerated() {
            let id = String(format: "00000000-0000-4000-8000-%012d", index + 1)
            var properties: [String: Any] = ["name": ["ko": "테스트 \(kind)"]]
            var geometry = polygon
            switch kind {
            case "level": properties["ordinal"] = -1
            case "unit", "fixture", "opening": properties["level_id"] = floorID
            case "amenity": properties["unit_ids"] = [unitID]
            default: break
            }
            if kind == "amenity" { geometry = ["type": "Point", "coordinates": [129.001, 36.001]] }
            if kind == "opening" {
                geometry = ["type": "LineString", "coordinates": [[129.0, 36.0], [129.01, 36.0]]]
            }
            let json: [String: Any] = ["type": "FeatureCollection", "features": [[
                "type": "Feature", "feature_type": kind, "id": id,
                "properties": properties, "geometry": geometry
            ]]]
            try JSONSerialization.data(withJSONObject: json).write(
                to: directory.appendingPathComponent("\(kind).geojson")
            )
        }
        try Data(#"{"version":"1.0.0"}"#.utf8).write(to: directory.appendingPathComponent("manifest.json"))
        return directory
    }
}
