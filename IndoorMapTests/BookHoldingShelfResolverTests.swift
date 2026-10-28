import Testing
@testable import fingerprint_library

@MainActor
struct BookHoldingShelfResolverTests {
    @Test("소장 위치 코드로 층을 제한하고 IMDF fixture ID까지 연결한다", arguments: [
        ("c3b", "S-3F-616-B"), ("c4b", "S-4F-706-A")
    ])
    func mapsConfirmedLocations(sample: (String, String)) async throws {
        let map = try await BundledIndoorMapLoader().loadLibrary()
        let labels = try await BundledShelfLabelLoader().loadLibrary(on: map)
        let resolutions = BookHoldingShelfResolver().resolve(
            [BookHoldingTestData.holding(code: sample.0)], on: map, labels: labels)
        let shelf = try #require(resolutions.first?.shelves.first)
        #expect(resolutions.first?.shelves.count == 1)
        #expect(shelf.fixtureNumber == sample.1)
        #expect(map.features.contains { $0.id == shelf.mapElementID && $0.name == sample.1 })
    }

    @Test("동일 청구기호의 일반서고·별치 자료를 각각 보존한다")
    func preservesUnmappedCopies() async throws {
        let map = try await BundledIndoorMapLoader().loadLibrary()
        let labels = try await BundledShelfLabelLoader().loadLibrary(on: map)
        let holdings = [BookHoldingTestData.holding(), BookHoldingTestData.holding(code: "smart"),
                        BookHoldingTestData.holding(code: "c4c")]
        let result = BookHoldingShelfResolver().resolve(holdings, on: map, labels: labels)
        #expect(result.map(\.holding) == holdings)
        #expect(result[0].shelves.count == 1)
        #expect(result[1].outcome == .unsupportedLocation)
        #expect(result[2].outcome == .unsupportedLocation)
    }

    @Test("겹치는 범위는 후보 모두 표시하고 빈 청구기호·범위 밖은 구분한다")
    func preservesAmbiguityAndMissingData() async throws {
        let map = try await BundledIndoorMapLoader().loadLibrary()
        let labels = try await BundledShelfLabelLoader().loadLibrary(on: map)
        let holdings = [BookHoldingTestData.holding(call: "AM79 .K8 2024"),
                        BookHoldingTestData.holding(1, call: ""), BookHoldingTestData.holding(2, call: "ZZ9999.A1")]
        let result = BookHoldingShelfResolver().resolve(holdings, on: map, labels: labels)
        #expect(Set(result[0].shelves.map(\.fixtureNumber)) == ["S-3F-657-A", "S-3F-657-B"])
        #expect(result[1].outcome == .missingCallNumber)
        #expect(result[2].outcome == .outsideIndex)
    }

    @Test("fixture 번호가 맞아도 실제 청구기호가 범위를 벗어나면 연결하지 않는다")
    func requiresMatchingCallNumberRange() async throws {
        let map = try await BundledIndoorMapLoader().loadLibrary()
        let shelf = try #require(try await BundledShelfLabelLoader().loadLibrary(on: map).first {
            $0.fixtureNumber == "S-3F-616-B"
        })
        let label = IndoorShelfLabel(
            fixtureNumber: shelf.fixtureNumber, realNumber: shelf.realNumber, side: shelf.side,
            sequence: shelf.sequence, floorID: shelf.floorID, mapElementID: shelf.mapElementID,
            geometry: shelf.geometry, content: .callNumberRange(start: "QA1.A1", end: "QA2.A9"))
        let result = BookHoldingShelfResolver().resolve([BookHoldingTestData.holding()], on: map, labels: [label])
        #expect(result.first?.outcome == .outsideIndex)
    }
}
