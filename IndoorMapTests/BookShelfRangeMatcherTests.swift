import Foundation
import Testing
@testable import fingerprint_library

@MainActor
struct BookShelfRangeMatcherTests {
    @Test("같은 청구기호가 두 층의 범위에 있어도 소장 층의 서가만 후보로 남긴다", arguments: [
        (3, "S-3F-616-B"), (4, "S-4F-706-A")
    ])
    func filtersFloorFirst(sample: (Int, String)) async throws {
        let map = try await BundledIndoorMapLoader().loadLibrary()
        let labels = try await BundledShelfLabelLoader().loadLibrary(on: map)
        let candidates = BookShelfRangeMatcher().candidates(
            for: .init(floorNumber: sample.0, callNumber: "RC263 .R632 1990"), on: map, labels: labels
        )
        #expect(candidates.map(\.fixtureNumber) == [sample.1])
        #expect(candidates.allSatisfy { candidate in
            map.floors.first { $0.id == candidate.floorID }?.ordinal == sample.0 - 1
        })
    }

    @Test("겹친 경계에서는 같은 층의 두 후보를 보존한다")
    func preservesBoundaryCandidates() async throws {
        let map = try await BundledIndoorMapLoader().loadLibrary()
        let labels = try await BundledShelfLabelLoader().loadLibrary(on: map)
        let candidates = BookShelfRangeMatcher().candidates(
            for: .init(floorNumber: 3, callNumber: "AM79 .K8 2024"), on: map, labels: labels
        )
        #expect(Set(candidates.map(\.fixtureNumber)) == ["S-3F-657-A", "S-3F-657-B"])
    }

    @Test("없는 층·범위 밖·해석할 수 없는 청구기호를 다른 서가로 대체하지 않는다", arguments: [
        (2, "RC263 .R632 1990"), (0, "RC263 .R632 1990"),
        (3, ""), (3, "확인 필요"), (3, "RC263 ???"), (3, "ZZ9999.A1"),
        (3, "RC263 .R632???"), (3, "RC263 .R632 20??")
    ])
    func rejectsUnmappedLocation(sample: (Int, String)) async throws {
        let map = try await BundledIndoorMapLoader().loadLibrary()
        let labels = try await BundledShelfLabelLoader().loadLibrary(on: map)
        #expect(BookShelfRangeMatcher().candidates(
            for: .init(floorNumber: sample.0, callNumber: sample.1), on: map, labels: labels
        ).isEmpty)
    }

    @Test("분류 번호는 수치로, Cutter 숫자는 소수 순서로 비교한다", arguments: [
        ("QA9.A1", "QA10.A2", "QA9.5 .A12 2024", true),
        ("QA9.A1", "QA10.A2", "QA99 .A1", false),
        ("QA10.A12", "QA10.A19", "QA10 .A2", false),
        ("QA10.A12", "QA10.A2", "QA10 .A19", true),
        ("TA418.9.C6.P7", "TA1632.C88", "TA418.9 .C6 P8 2020", true),
        ("PL959.65.유293.수75", "PL959.65.유293.수76", "PL959.65.유293 .수75 2023", true),
        ("QA10.A1", "QA10.A2", "QA10.A2.B3 2024", true)
    ])
    func comparesCallNumbers(sample: (String, String, String, Bool)) async throws {
        let map = try await BundledIndoorMapLoader().loadLibrary()
        let label = try #require(try await BundledShelfLabelLoader().loadLibrary(on: map).first)
        let range = IndoorShelfLabel(
            fixtureNumber: label.fixtureNumber, realNumber: label.realNumber, side: label.side,
            sequence: label.sequence, floorID: label.floorID, mapElementID: label.mapElementID,
            geometry: label.geometry, content: .callNumberRange(start: sample.0, end: sample.1)
        )
        let candidates = BookShelfRangeMatcher().candidates(
            for: .init(floorNumber: 3, callNumber: sample.2), on: map, labels: [range]
        )
        #expect(!candidates.isEmpty == sample.3)
    }
}
