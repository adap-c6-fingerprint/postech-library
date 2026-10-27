import Foundation
import Testing
@testable import fingerprint_library

struct IndoorNavigationMapFilesTests {
    private func fixture(amenity: Bool, section: Bool) throws -> URL {
        let root = try NavigationTestFixture.directory()
        if !amenity {
            try FileManager.default.removeItem(at: root.appendingPathComponent("IMDFData/amenity.geojson"))
        }
        if section {
            let file = root.appendingPathComponent("IMDFData/unit.geojson")
            var collection = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any]
            var feature = (collection["features"] as! [[String: Any]])[0]
            feature["id"] = "00000000-0000-4000-8000-000000000100"
            feature["feature_type"] = "section"
            collection["features"] = [feature]
            try NavigationTestFixture.write(collection, file: "IMDFData/section.geojson", at: root)
        }
        try NavigationTestFixture.pin(root)
        return root
    }

    @Test("선택 amenity·section의 모든 조합을 해시로 고정해 읽는다", arguments: [false, true], [false, true])
    func loadsOptionalMapFiles(amenity: Bool, section: Bool) async throws {
        let root = try fixture(amenity: amenity, section: section)
        defer { try? FileManager.default.removeItem(at: root) }
        let (map, navigation) = try await NavigationTestFixture.load(root)
        #expect(map.features.contains { $0.kind == .amenity } == amenity)
        #expect(map.features.contains { $0.kind == .section } == section)
        #expect(navigation.graph.nodes.count == 2)
    }

    @Test("해시 고정 후 추가된 선택 파일은 빈 컬렉션이어도 거부한다",
          arguments: ["amenity.geojson", "section.geojson"])
    func rejectsAddedOptionalFile(_ file: String) async throws {
        let root = try fixture(amenity: file != "amenity.geojson", section: false)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data(#"{"type":"FeatureCollection","features":[]}"#.utf8)
            .write(to: root.appendingPathComponent("IMDFData/" + file))
        await expectInvalid(root, file: "dataset.json")
    }

    enum Mutation: CaseIterable, Sendable { case contents, removal, unpinned }

    @Test("선택 파일의 변경·삭제·해시 누락을 거부한다",
          arguments: ["amenity.geojson", "section.geojson"], Mutation.allCases)
    func rejectsChangedOptionalFile(_ file: String, mutation: Mutation) async throws {
        let root = try fixture(amenity: true, section: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("IMDFData/" + file)
        switch mutation {
        case .contents:
            var data = try Data(contentsOf: url)
            data.append(0x20)
            try data.write(to: url)
        case .removal:
            try FileManager.default.removeItem(at: url)
        case .unpinned:
            try removeHash(file, at: root)
        }
        await expectInvalid(root, file: mutation == .contents ? "IMDFData/" + file : "dataset.json")
    }

    @Test("필수 지도 파일의 해시 누락을 거부한다", arguments: [
        "manifest.json", "venue.geojson", "level.geojson", "footprint.geojson",
        "unit.geojson", "fixture.geojson", "opening.geojson"
    ])
    func rejectsMissingRequiredHash(_ file: String) async throws {
        let root = try fixture(amenity: true, section: false)
        defer { try? FileManager.default.removeItem(at: root) }
        try removeHash(file, at: root)
        await expectInvalid(root, file: "dataset.json")
    }

    private func removeHash(_ file: String, at root: URL) throws {
        try NavigationTestFixture.edit("dataset.json", at: root) {
            var hashes = $0["map_files_sha256"] as! [String: String]
            hashes.removeValue(forKey: file)
            $0["map_files_sha256"] = hashes
        }
    }

    private func expectInvalid(_ root: URL, file: String) async {
        do {
            _ = try await NavigationTestFixture.load(root)
            Issue.record("고정되지 않은 \(file)을 정상 데이터셋으로 처리했습니다.")
        } catch let error as IndoorMapLoadError {
            guard case .invalidData(let actual, _) = error else {
                Issue.record("invalidData가 필요합니다: \(error)")
                return
            }
            #expect(actual == file)
        } catch { Issue.record("예상하지 못한 오류: \(error)") }
    }
}
