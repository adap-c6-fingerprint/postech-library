import Foundation

@main
struct SecondFloorShelfProof {
    @MainActor static func main() async throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
            .appendingPathComponent("fingerprint-library/Resources/IndoorMaps/POSTECHLibrary")
        let map = try await BundledIndoorMapLoader().load(directory: root.appendingPathComponent("IMDFData"))
        let labels = try BundledShelfLabelLoader().decode(Data(contentsOf: root.appendingPathComponent("shelfdata.json")), on: map)
        let start = IndoorPosition(
            coordinate: .init(latitude: 36.0127633, longitude: 129.3251348), floorOrdinal: 2,
            horizontalAccuracy: 3, timestamp: Date(), source: .manual)
        // 2026-11-13 실제 소장 응답과 이름 호환 사례. 대출 상태는 고정하지 않는다.
        let samples: [(String?, String?, String?, String)] = [
            ("rec100", "삼각서가A2-3: 권장도서100선 (2층)", nil, "삼각서가 A"),
            (nil, "Display Shelf B (2F)", nil, "삼각서가 B"),
            (nil, "삼각서가C3: 원북 원포항 선정도서 (2층)", nil, "삼각서가 C"),
            ("C2EX", "Display Shelf D: Exhibition (2F)", "PQ2683.W4 .아44 2026", "삼각서가 B"),
            ("c2n", "신착서가 (2층)", "PL1171 .박56 2024", "신착서가 HN-P"),
            ("c2n", "신착서가 (2층)", "HC110.I52 .S26 2026", "신착서가 H-HM"),
            ("c2n", "신착서가 (2층)", "DS924 .권56 2026", "신착서가 DS-G"),
            ("c2n", "신착서가 (2층)", "B561.M52 .E65 2026", "신착서가 A-DS"),
            (nil, "원형서가 (2F) A", nil, "원형서가 A"),
            ("c2sb2", "원형서가 (2F) B: 과학 & SF & 여행", "G153 .프294", "원형서가 B"),
            ("c2sb2", "원형서가 (2F) B: 과학 & SF & 여행", "G153 .제68 2018", "원형서가 B"),
            ("c2e", "영어교양 2층", "PN1997.2.A94 .W545 2009", "영어 교양 서가")
        ]
        var destinations = Set<String>()
        for (index, sample) in samples.enumerated() {
            let holding = BookHolding(holdingID: nil, institutionCode: "82POSTECH_INST", libraryCode: "MAIN",
                locationCode: sample.0, locationName: sample.1, callNumber: sample.2, availability: nil)
            let shelves = ShelfResolver().resolve([holding], on: map, labels: labels).preferredRouteShelves
            precondition(shelves.count == 1 && shelves[0].realNumber == sample.3, "서가 매칭: \(sample.3)")
            precondition(map.floors.first { $0.id == shelves[0].floorID }?.ordinal == 1)
            let book = Book(id: "proof-\(index)", isbn: nil, controlNumber: nil, title: sample.3,
                author: "", publisher: nil, publicationYear: nil, description: nil, imageURL: nil)
            let plan = try await RoutePlanningLoader().load(directory: root, on: map, labels: labels, start: start,
                stops: [.init(book: book, holdings: [holding], candidateShelves: shelves)])
            precondition(plan.stops.first?.shelf.mapElementID == shelves[0].mapElementID)
            precondition(plan.route.distanceMeters.isFinite && plan.route.distanceMeters > 0)
            precondition(plan.route.segments.last?.floorID == shelves[0].floorID)
            destinations.insert(shelves[0].fixtureNumber)
            print("PASS: \(sample.3) → \(plan.route.distanceMeters.rounded())m, explicit fixture/node route")
        }
        precondition(destinations.count == 10, "2층의 서로 다른 서가 10개를 모두 확인한다")
        let worldEconomy = BookHolding(holdingID: nil, institutionCode: "82POSTECH_INST", libraryCode: "MAIN",
            locationCode: "c3b", locationName: "단행본3층", callNumber: "HB3730 .박75 2025", availability: nil)
        let general = ShelfResolver().resolve([worldEconomy], on: map, labels: labels).preferredRouteShelves
        precondition(!general.isEmpty)
        precondition(general.allSatisfy { shelf in map.floors.first { $0.id == shelf.floorID }?.ordinal == 2 })
        print("PASS: actual bundle, 12 location cases, all 10 second-floor destinations reachable; c3b remains on 3F.")
    }
}
