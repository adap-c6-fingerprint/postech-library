import Foundation
import Testing
@testable import fingerprint_library

struct ShelfResolverTests {
    @Test(arguments: [
        ("삼각서가C3: 원북 원포항 선정도서 (2층)", "삼각서가 C"),
        ("삼각 서가 a1", "삼각서가 A"),
        ("Display Shelf B: Recommended books (2F)", "삼각서가 B"),
        ("display shelf c3", "삼각서가 C"),
        ("Display Shelf D: Exhibition (2F)", "삼각서가 B"),
        ("삼각서가 D: 전시도서", "삼각서가 B"),
    ])
    func 삼각서가_위치_이름에서_도면_서가_이름을_만든다(locationName: String, expected: String) {
        #expect(ShelfResolver.displayShelfName(in: locationName) == expected)
    }

    @Test func 삼각서가가_아닌_위치는_서가로_추측하지_않는다() {
        #expect(ShelfResolver.displayShelfName(in: "3층 일반자료실") == nil)
        #expect(ShelfResolver.displayShelfName(in: nil) == nil)
        #expect(ShelfResolver.displayShelfName(in: "Display Shelf E") == nil)
        #expect(ShelfResolver.displayShelfName(in: "삼각서가 ABC") == nil)
    }

    @Test(arguments: [
        ("C2EX", "Display Shelf D: Exhibition (2F)", "PQ2683.W4 .아44 2026", "삼각서가 B"),
        ("c2n", "신착서가 (2층)", "PL1171 .박56 2024", "신착서가 HN-P"),
        (" C2N ", "신착서가 (2층)", "HC110.I52 .S26 2026", "신착서가 H-HM"),
        ("c2n", "신착서가 (2층)", "DS924 .권56 2026", "신착서가 DS-G"),
        ("c2n", "신착서가 (2층)", "B561.M52 .E65 2026", "신착서가 A-DS"),
        ("c2sb2", "원형서가 (2F) B: 과학 & SF & 여행", "G153 .프294", "원형서가 B"),
        ("c2sb2", "원형서가 (2F) B: 과학 & SF & 여행", "G153 .제68 2018", "원형서가 B"),
        ("c2e", "영어교양 2층", "PN1997.2.A94 .W545 2009", "영어 교양 서가")
    ])
    func 실제_소장_응답을_이층의_한_서가로_연결한다(
        code: String, name: String, call: String, expected: String
    ) throws {
        let scene = ShelfScene()
        let holding = scene.holding(code, name: name, call: call)
        let result = try #require(ShelfResolver().resolve([holding], on: scene.map, labels: scene.labels).first)
        #expect(result.holding == holding)
        #expect(result.shelves.map(\.realNumber) == [expected])
        #expect(result.shelves.allSatisfy { $0.floorID == scene.second })
    }

    @Test(arguments: [
        ("A1", "A-DS"), ("DR1", "A-DS"), ("DS1", "DS-G"), ("DT1", "DS-G"),
        ("G1", "DS-G"), ("GV1", "DS-G"), ("H1", "H-HM"), ("HM1", "H-HM"),
        ("HN1", "HN-P"), ("P1", "HN-P"), ("PN1", "HN-P"), ("PZ999", "HN-P"),
        (" pl 1171 .박56 2024 ", "HN-P")
    ])
    func 신착서가의_경계와_하위_분류를_구분한다(call: String, suffix: String) {
        let scene = ShelfScene()
        let results = ShelfResolver().resolve([scene.holding("c2n", call: call)], on: scene.map, labels: scene.labels)
        #expect(results.preferredRouteShelves.map(\.realNumber) == ["신착서가 \(suffix)"])
    }

    @Test(arguments: [
        ("원형서가 (2F) A: 문학", "원형서가 A"),
        ("원형 서가 B", "원형서가 B"),
        ("Special Collection A (2F)", "원형서가 A"),
        ("신착서가 (2층)", "신착서가 A-DS"),
        ("영어교양 2층", "영어 교양 서가"),
        ("삼각서가C3: 원북 원포항 선정도서 (2층)", "삼각서가 C")
    ])
    func 코드가_없어도_확인된_위치_이름으로_구분한다(name: String, expected: String) {
        let scene = ShelfScene()
        let results = ShelfResolver().resolve([scene.holding(nil, name: name)], on: scene.map, labels: scene.labels)
        #expect(results.preferredRouteShelves.map(\.realNumber) == [expected])
    }

    @Test(arguments: [
        ("c2e", "신착서가 (2층)", "영어 교양 서가"),
        ("c2sb2", "신착서가 (2층)", "원형서가 B"),
        ("c2n", "영어교양 2층", "신착서가 A-DS")
    ])
    func 확인된_위치_코드가_이름보다_우선한다(code: String, name: String, expected: String) {
        let scene = ShelfScene()
        let results = ShelfResolver().resolve([scene.holding(code, name: name)], on: scene.map, labels: scene.labels)
        #expect(results.preferredRouteShelves.map(\.realNumber) == [expected])
    }

    @Test func 정보가_없거나_지원하지_않는_위치를_추측하지_않는다() throws {
        let scene = ShelfScene()
        for call in [nil, "", "   "] as [String?] {
            let results = ShelfResolver().resolve([scene.holding("c2n", call: call)], on: scene.map, labels: scene.labels)
            #expect(results.first?.outcome == .missingCallNumber)
        }
        for call in ["Q141", "Z100", "PL", "한글 청구기호", "ABCD123"] {
            let results = ShelfResolver().resolve([scene.holding("c2n", call: call)], on: scene.map, labels: scene.labels)
            #expect(results.first?.outcome == .outsideIndex)
        }
        for name in [nil, "원형서가 C", "신착서가 (5층)", "영어교양 3층"] as [String?] {
            let results = ShelfResolver().resolve([scene.holding(nil, name: name)], on: scene.map, labels: scene.labels)
            #expect(results.first?.outcome == .unsupportedLocation)
        }
        let foreign = BookHolding(holdingID: nil, institutionCode: "OTHER", libraryCode: "MAIN",
                                  locationCode: "c2e", locationName: nil, callNumber: nil, availability: nil)
        #expect(ShelfResolver().resolve([foreign], on: scene.map, labels: scene.labels).first?.outcome == .unsupportedLocation)
        let misplaced = scene.named("영어 교양 서가", floor: scene.third)
        let results = ShelfResolver().resolve([scene.holding("c2e")], on: scene.map, labels: [misplaced])
        #expect(results.first?.outcome == .outsideIndex)
    }

    @Test(arguments: ["c3b", "c4b"])
    func 일반서가가_매칭되면_대출상태와_무관하게_모든_이층_서가보다_우선한다(code: String) throws {
        let scene = ShelfScene()
        let general = scene.holding(code, call: "HB3730 .박75 2025", availability: "unavailable")
        for named in scene.secondFloorHoldings {
            let holdings = [named, general]
            let results = ShelfResolver().resolve(holdings, on: scene.map, labels: scene.labels)
            #expect(results.preferredForRoute.map(\.holding) == [general])
            #expect(results.preferredRouteShelves.map(\.floorID) == [code == "c3b" ? scene.third : scene.fourth])
            let detail = try #require(BookDetailDestinationPresentation.resolve(
                holdings: holdings, map: scene.map, labels: scene.labels))
            #expect(detail.holding == general)
            #expect(detail.shelves == results.preferredRouteShelves)
            let markers = HomeMapMarkerBuilder.favorites(
                holdings: [["control", "same-record"]: holdings], on: scene.map, labels: scene.labels)
            #expect(markers.map(\.floorID) == detail.shelves.map(\.floorID))
        }
    }

    @Test func 일반서가를_못찾으면_이층_서가로_대체하고_복본은_중복하지_않는다() throws {
        let scene = ShelfScene()
        let named = scene.holding("c2n", call: "DS924 .권56 2026", availability: "unavailable")
        for call in [nil, "ZZ999"] as [String?] {
            let holdings = [scene.holding("c3b", call: call), named, named]
            let results = ShelfResolver().resolve(holdings, on: scene.map, labels: scene.labels)
            #expect(results.preferredRouteShelves.map(\.realNumber) == ["신착서가 DS-G"])
            let detail = try #require(BookDetailDestinationPresentation.resolve(
                holdings: holdings, map: scene.map, labels: scene.labels))
            #expect(detail.holding == named)
            #expect(detail.shelves.map(\.realNumber) == ["신착서가 DS-G"])
        }
    }
}

private struct ShelfScene {
    let second = UUID(), third = UUID(), fourth = UUID()
    private let featureIDs = (0..<12).map { _ in UUID() }
    private static let names = [
        "삼각서가 A", "삼각서가 B", "삼각서가 C", "신착서가 A-DS", "신착서가 DS-G",
        "신착서가 H-HM", "신착서가 HN-P", "원형서가 A", "원형서가 B", "영어 교양 서가"
    ]
    private var geometry: IndoorMapGeometry { .point(.init(latitude: 36.013, longitude: 129.325)) }

    var map: IndoorMap {
        .init(formatVersion: "1", venue: .init(sourceID: UUID(), kind: .venue, floorID: nil,
              category: nil, name: nil, geometry: geometry), floors: [
                .init(id: second, ordinal: 1, name: "2층", geometry: geometry),
                .init(id: third, ordinal: 2, name: "3층", geometry: geometry),
                .init(id: fourth, ordinal: 3, name: "4층", geometry: geometry)
              ], features: [], diagnostics: [])
    }

    var labels: [IndoorShelfLabel] {
        Self.names.map { named($0, floor: second) }
        + [third, fourth].enumerated().map { index, floor in
            .init(fixtureNumber: "general-\(floor)", realNumber: "301", side: .a, sequence: 0,
                  floorID: floor, mapElementID: .init(kind: .fixture, sourceID: featureIDs[10 + index]),
                  geometry: geometry, content: .callNumberRange(start: "B1", end: "PZ9999"))
        }
    }

    var secondFloorHoldings: [BookHolding] {
        [holding("C2EX", name: "Display Shelf D: Exhibition (2F)"),
         holding("c2n", call: "PL1171 .박56 2024"),
         holding("c2sb2"), holding("c2e"),
         holding(nil, name: "원형서가 (2F) A: 문학")]
    }

    func named(_ name: String, floor: UUID) -> IndoorShelfLabel {
        .init(fixtureNumber: "S-2F-\(name)", realNumber: name, side: .a, sequence: 0,
              floorID: floor, mapElementID: .init(kind: .fixture, sourceID: featureIDs[Self.names.firstIndex(of: name)!]),
              geometry: geometry, content: .category(name))
    }

    func holding(_ code: String?, name: String? = nil, call: String? = "B100", availability: String = "available") -> BookHolding {
        .init(holdingID: nil, institutionCode: "82POSTECH_INST", libraryCode: "MAIN",
              locationCode: code, locationName: name, callNumber: call, availability: availability)
    }
}
