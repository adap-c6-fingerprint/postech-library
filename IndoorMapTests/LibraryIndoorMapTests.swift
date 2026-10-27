import CryptoKit
import Foundation
import Testing
@testable import fingerprint_library

struct LibraryIndoorMapTests {
    @Test("앱의 기본 지도는 실제 도서관이며 1~5층과 원형 서가 도형을 읽는다")
    func loadsLibraryAsDefaultMap() async throws {
        let map = try await IndoorMapClient.liveValue.load()
        #expect(map.venue.name == "박태준 학술정보관")
        #expect(map.venue.sourceID == UUID(uuidString: "a1dc84ab-1569-4c1b-a024-5a89ec75e564"))
        #expect(map.floors.map(\.ordinal) == [0, 1, 2, 3, 4])
        #expect(map.floors.map(\.name) == ["1층", "2층", "3층", "4층", "5층"])
        #expect(map.features.filter { $0.kind == .unit }.count == 273)
        #expect(map.features.filter { $0.kind == .fixture }.count == 1_650)
        #expect(map.features.filter { $0.kind == .opening }.count == 254)
        #expect(map.features.filter { $0.kind == .section }.count == 2)
        #expect(map.features.allSatisfy { $0.kind != .amenity })
        #expect(map.diagnostics.isEmpty)
        let floors = Set(map.floors.map(\.id))
        #expect(map.features.filter { $0.kind != .footprint }.allSatisfy {
            $0.floorID.map(floors.contains) == true
        })
        #expect(map.features.filter { $0.kind == .fixture }.allSatisfy {
            if case .multiPolygon = $0.geometry { return true }
            return false
        })
    }

    @Test("제공된 도서관 원본 10개 파일을 변경하지 않고 번들에 포함한다")
    func preservesLibrarySource() throws {
        let root = try #require(Bundle.main.url(forResource: "IndoorMaps", withExtension: nil))
            .appendingPathComponent("POSTECHLibrary", isDirectory: true)
        struct Source: Decodable { let files_sha256: [String: String] }
        let source = try JSONDecoder().decode(Source.self, from: Data(contentsOf: root.appendingPathComponent("source.json")))
        #expect(source.files_sha256.count == 10)
        for (file, expected) in source.files_sha256 {
            let data = try Data(contentsOf: root.appendingPathComponent("IMDFData/" + file))
            let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            #expect(hash == expected, "\(file) 원본 불일치")
        }
    }

    @Test("도서관 노드 자료가 없을 때 C5 목업 경로를 섞지 않는다")
    func reportsUnpreparedNavigation() async throws {
        let map = try await BundledIndoorMapLoader().loadLibrary()
        do {
            _ = try await IndoorNavigationClient.liveValue.load(map)
            Issue.record("노드가 없는 도서관에 다른 지도의 길찾기 자료를 반환했습니다.")
        } catch let error as IndoorNavigationLoadError {
            #expect(error == .notPrepared)
        }
    }
}
