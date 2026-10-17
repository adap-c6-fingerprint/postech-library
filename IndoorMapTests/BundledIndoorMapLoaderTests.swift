import CryptoKit
import Foundation
import Testing
@testable import fingerprint_library

struct BundledIndoorMapLoaderTests {
    private static var hasLocalC5: Bool {
        guard let root = Bundle.main.url(forResource: "IndoorMaps", withExtension: nil) else { return false }
        return FileManager.default.fileExists(atPath: root.appendingPathComponent("C5/IMDFData/manifest.json").path)
    }

    @Test("앱 번들의 C5 원본과 층별 지도 요소를 읽는다", .enabled(if: hasLocalC5, "C5 로컬 가져오기 필요"))
    func loadsBundledC5() async throws {
        let map = try await BundledIndoorMapLoader().loadC5()
        #expect(map.formatVersion == "1.0.0")
        #expect(map.venue.name == "융합연구동")
        #expect(map.floors.map(\.ordinal) == [0, 1, 2, 3, 4, 5])
        #expect(map.floors.map(\.name) == ["1층", "2층", "3층", "4층", "5층", "6층"])
        #expect(map.features.filter { $0.kind == .unit }.count == 167)
        #expect(map.features.filter { $0.kind == .fixture }.count == 38)
        #expect(map.features.filter { $0.kind == .opening }.count == 59)
        #expect(map.features.filter { $0.kind == .amenity }.count == 36)
        #expect(map.diagnostics.count == 1)
        #expect(Set(map.features.map(\.id)).count == map.features.count)
        let floorIDs = Set(map.floors.map(\.id))
        #expect(map.features.filter { $0.kind != .footprint }.allSatisfy {
            $0.floorID.map(floorIDs.contains) == true
        })

        // 원본 UUID와 [경도, 위도] 순서가 화면용 모델에서도 유지되는지 확인한다.
        let fixture = try #require(map.features.first {
            $0.kind == .fixture && $0.name == "29"
        })
        #expect(fixture.floorID == UUID(uuidString: "90005828-dce9-49ff-be8c-d392a8254e77"))
        guard case .multiPolygon(let polygons) = fixture.geometry else {
            Issue.record("fixture의 MultiPolygon이 유지되어야 합니다.")
            return
        }
        let point = try #require(polygons.first?.first?.first)
        #expect((129...130).contains(point.longitude))
        #expect((36...37).contains(point.latitude))
    }

    @Test("라이선스를 포함한 13개 리소스가 원본 해시와 일치한다", .enabled(if: hasLocalC5, "C5 로컬 가져오기 필요"))
    func preservesSourceFilesInAppBundle() throws {
        let directory = try sourceDirectory()
        let sourceURL = directory.deletingLastPathComponent().appendingPathComponent("source.json")
        struct Source: Decodable { let files_sha256: [String: String] }
        let source = try JSONDecoder().decode(Source.self, from: Data(contentsOf: sourceURL))
        #expect(source.files_sha256.count == 13)
        for (path, expected) in source.files_sha256 {
            let data = try Data(contentsOf: directory.appendingPathComponent(path))
            let actual = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            #expect(actual == expected, "\(path) 원본 불일치")
        }
    }

    @Test("표시 이름과 지하층 ordinal을 유지하고 amenity의 층을 unit_ids로 찾는다")
    func resolvesAmenityFloor() async throws {
        let directory = try IMDFTestFixture.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let map = try await BundledIndoorMapLoader().load(directory: directory)
        #expect(map.floors.first?.ordinal == -1)
        #expect(map.floors.first?.name == "테스트 level")
        #expect(map.features.first { $0.kind == .amenity }?.floorID == UUID(uuidString: IMDFTestFixture.floorID))
        #expect(map.diagnostics.isEmpty)
    }

    @Test("C5 호환 모드에서도 타입 간 충돌은 보고하고 각 요소를 구분한다")
    func reportsLegacyCollision() async throws {
        let directory = try IMDFTestFixture.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try edit("amenity.geojson", in: directory) { json in
            var features = json["features"] as! [[String: Any]]
            features[0]["id"] = IMDFTestFixture.unitID
            json["features"] = features
        }
        let map = try await BundledIndoorMapLoader().load(directory: directory, policy: .c5Compatibility)
        let unitID = try #require(UUID(uuidString: IMDFTestFixture.unitID))
        #expect(map.diagnostics == [.duplicateSourceID(unitID, featureTypes: ["amenity", "unit"])])
        let collided = map.features.filter { $0.sourceID == unitID }
        #expect(collided.count == 2)
        #expect(Set(collided.map(\.id)).count == 2)
    }

    @Test("MultiPolygon과 내부 ring을 평탄화하지 않는다")
    func preservesPolygonHoles() async throws {
        let directory = try IMDFTestFixture.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let outer: [[Double]] = [[129, 36], [130, 36], [130, 37], [129, 36]]
        let hole: [[Double]] = [[129.1, 36.1], [129.2, 36.1], [129.2, 36.2], [129.1, 36.1]]
        try edit("fixture.geojson", in: directory) { json in
            var features = json["features"] as! [[String: Any]]
            features[0]["geometry"] = ["type": "MultiPolygon", "coordinates": [[outer, hole], [outer]]]
            json["features"] = features
        }
        let map = try await BundledIndoorMapLoader().load(directory: directory)
        let fixture = try #require(map.features.first { $0.kind == .fixture })
        guard case .multiPolygon(let polygons) = fixture.geometry else {
            Issue.record("MultiPolygon이 유지되어야 합니다.")
            return
        }
        #expect(polygons.map(\.count) == [2, 1])
        #expect(polygons[0][1][0] == IndoorMapCoordinate(latitude: 36.1, longitude: 129.1))
    }

    enum Corruption: CaseIterable, Sendable, Equatable {
        case unsupportedVersion, missingFile, invalidJSON, wrongCollection
        case emptyFloors, missingOrdinal, unknownFloor, duplicateID
        case missingGeometry, wrongGeometry, invalidLongitude, invalidLatitude
        case missingCoordinate, unclosedRing, duplicateWithinFile, wrongFeatureType, unknownUnit

        var file: String {
            switch self {
            case .unsupportedVersion: "manifest.json"
            case .missingFile, .wrongCollection: "opening.geojson"
            case .invalidJSON, .duplicateID, .missingGeometry, .duplicateWithinFile, .wrongFeatureType: "fixture.geojson"
            case .emptyFloors, .missingOrdinal, .unclosedRing: "level.geojson"
            case .unknownFloor, .wrongGeometry: "unit.geojson"
            case .invalidLongitude, .invalidLatitude, .missingCoordinate, .unknownUnit: "amenity.geojson"
            }
        }
    }

    @Test("손상된 파일과 오류 위치를 명시한다", arguments: Corruption.allCases)
    func rejectsCorruptedMap(_ corruption: Corruption) async throws {
        let directory = try IMDFTestFixture.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent(corruption.file)
        switch corruption {
        case .missingFile:
            try FileManager.default.removeItem(at: file)
        case .invalidJSON:
            try Data("{".utf8).write(to: file)
        default:
            try edit(corruption.file, in: directory) { json in
                switch corruption {
                case .unsupportedVersion: json["version"] = "2.0.0"
                case .wrongCollection: json["type"] = "Feature"
                case .emptyFloors: json["features"] = []
                default:
                    var features = json["features"] as! [[String: Any]]
                    var properties = features[0]["properties"] as! [String: Any]
                    switch corruption {
                    case .missingOrdinal: properties.removeValue(forKey: "ordinal")
                    case .unknownFloor: properties["level_id"] = UUID().uuidString
                    case .unknownUnit: properties["unit_ids"] = [UUID().uuidString]
                    case .duplicateWithinFile: features.append(features[0])
                    case .wrongFeatureType: features[0]["feature_type"] = "unit"
                    case .duplicateID:
                        // 중복이 다른 파일 사이에 있어도 거부해야 한다.
                        let unit = try readJSON("unit.geojson", in: directory)
                        features[0]["id"] = (unit["features"] as! [[String: Any]])[0]["id"]
                    case .missingGeometry: features[0]["geometry"] = NSNull()
                    case .wrongGeometry:
                        features[0]["geometry"] = ["type": "Point", "coordinates": [129, 36]]
                    case .invalidLongitude, .invalidLatitude, .missingCoordinate:
                        let values: [Double] = switch corruption {
                        case .invalidLongitude: [200, 36]
                        case .invalidLatitude: [129, 120]
                        default: [129]
                        }
                        features[0]["geometry"] = ["type": "Point", "coordinates": values]
                    case .unclosedRing:
                        features[0]["geometry"] = [
                            "type": "Polygon", "coordinates": [[[129, 36], [130, 36], [130, 37], [129, 37]]]
                        ]
                    default: break
                    }
                    features[0]["properties"] = properties
                    json["features"] = features
                }
            }
        }

        do {
            _ = try await BundledIndoorMapLoader().load(directory: directory)
            Issue.record("\(corruption) 데이터를 성공으로 처리했습니다.")
        } catch let error as IndoorMapLoadError {
            switch error {
            case .missingResource(let path):
                #expect(corruption == .missingFile)
                #expect(path == corruption.file)
            case .invalidData(let file, _):
                #expect(corruption != .missingFile)
                #expect(file.contains(corruption.file))
            }
        }
    }

    private func sourceDirectory() throws -> URL {
        let root = try #require(Bundle.main.url(forResource: "IndoorMaps", withExtension: nil))
        return root.appendingPathComponent("C5/IMDFData", isDirectory: true)
    }

    private func readJSON(_ file: String, in directory: URL) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(
            with: Data(contentsOf: directory.appendingPathComponent(file))
        ) as? [String: Any])
    }

    private func edit(
        _ file: String, in directory: URL, mutation: (inout [String: Any]) throws -> Void
    ) throws {
        var json = try readJSON(file, in: directory)
        try mutation(&json)
        let data = try JSONSerialization.data(withJSONObject: json)
        try data.write(to: directory.appendingPathComponent(file))
    }
}
