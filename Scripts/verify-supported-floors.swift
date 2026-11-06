import Foundation

@main
struct VerifySupportedFloors {
    static func main() throws {
        let path = CommandLine.arguments.dropFirst().first
            ?? "fingerprint-library/Resources/IndoorMaps/POSTECHLibrary/IMDFData/level.geojson"
        let document = try JSONDecoder().decode(LevelDocument.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
        let point = IndoorMapCoordinate(latitude: 0, longitude: 0)
        let floors = document.features.map { feature in
            IndoorMapFloor(id: feature.id, ordinal: feature.properties.ordinal,
                           name: feature.properties.name["ko"] ?? "", geometry: .point(point))
        }.sorted { $0.ordinal < $1.ordinal }
        let map = makeMap(floors: floors, point: point)

        // 실제 번들 도면은 모든 층과 원본 ID를 유지하면서 선택 항목만 3·4층으로 제한한다.
        precondition(map.floors.count == 5)
        precondition(map.selectableFloors.map(\.name) == ["3층", "4층"])
        precondition(map.selectableFloors.map(\.id) == floors.filter { [2, 3].contains($0.ordinal) }.map(\.id))
        precondition(map.initialDisplayFloor(reportedOrdinal: 2)?.name == "3층")
        precondition(map.initialDisplayFloor(reportedOrdinal: 3)?.name == "4층")

        // 위치가 없거나 1·2·5층을 보고해도 제공하지 않는 층을 처음 표시하면 안 된다.
        let unsupported: [Int?] = [nil, -1, 0, 1, 4, 99]
        for ordinal in unsupported {
            precondition(map.initialDisplayFloor(reportedOrdinal: ordinal)?.name == "3층")
        }
        precondition(map.floors == floors)

        // 일부 층 자료가 없는 경우에도 존재하는 지원 층만 선택한다.
        let fourthOnly = makeMap(floors: floors.filter { $0.ordinal == 3 }, point: point)
        precondition(fourthOnly.initialDisplayFloor(reportedOrdinal: nil)?.name == "4층")
        let unsupportedOnly = makeMap(floors: floors.filter { $0.ordinal == 0 }, point: point)
        precondition(unsupportedOnly.selectableFloors.isEmpty)
        precondition(unsupportedOnly.initialDisplayFloor(reportedOrdinal: 0) == nil)
        print("PASS: bundled floor IDs, 3F/4F selection, reported-floor fallback, missing floors, original data preserved")
    }

    private static func makeMap(floors: [IndoorMapFloor], point: IndoorMapCoordinate) -> IndoorMap {
        IndoorMap(formatVersion: "test",
                  venue: .init(sourceID: UUID(), kind: .venue, floorID: nil,
                               category: nil, name: nil, geometry: .point(point)),
                  floors: floors, features: [], diagnostics: [])
    }

    private struct LevelDocument: Decodable {
        let features: [Feature]
        struct Feature: Decodable {
            let id: UUID
            let properties: Properties
        }
        struct Properties: Decodable {
            let ordinal: Int
            let name: [String: String]
        }
    }
}
