import Foundation

nonisolated struct BundledShelfLabelLoader {
    static let libraryVenueID = UUID(uuidString: "a1dc84ab-1569-4c1b-a024-5a89ec75e564")!

    @concurrent
    func loadLibrary(on map: IndoorMap, in bundle: Bundle = .main) async throws -> [IndoorShelfLabel] {
        guard let root = bundle.url(forResource: "IndoorMaps", withExtension: nil) else {
            throw ShelfLabelLoadError.missingResource
        }
        let file = root.appendingPathComponent("POSTECHLibrary/shelfdata.json")
        let data: Data
        do { data = try Data(contentsOf: file) }
        catch { throw ShelfLabelLoadError.missingResource }
        return try decode(data, on: map)
    }

    func decode(_ data: Data, on map: IndoorMap) throws -> [IndoorShelfLabel] {
        try Task.checkCancellation()
        let rows: [Record]
        do { rows = try JSONDecoder().decode([Record].self, from: data) }
        catch { throw ShelfLabelLoadError.invalidData("JSON 필드 형식을 확인하세요.") }
        guard !rows.isEmpty else { throw ShelfLabelLoadError.invalidData("서가 목록이 비어 있습니다.") }
        let fixtures = Dictionary(grouping: map.features.filter { $0.kind == .fixture }, by: \.name)
        var seen = Set<String>()
        return try rows.map { row in
            try Task.checkCancellation()
            guard !row.fixtureNumber.isEmpty, !row.realNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  seen.insert(row.fixtureNumber).inserted, row.sequence >= 0,
                  row.floor.hasSuffix("F"), let floorNumber = Int(row.floor.dropLast()), floorNumber > 0,
                  row.fixtureNumber.hasPrefix("S-\(row.floor)-"), row.fixtureNumber.hasSuffix("-\(row.side.rawValue)")
            else { throw ShelfLabelLoadError.invalidData("서가 번호·층·면을 확인하세요: \(row.fixtureNumber)") }
            let floors = map.floors.filter { $0.ordinal == floorNumber - 1 }
            let matches = fixtures[row.fixtureNumber] ?? []
            guard floors.count == 1, matches.count == 1, let fixture = matches.first,
                  fixture.floorID == floors[0].id else {
                throw ShelfLabelLoadError.invalidData("현재 지도에서 서가와 층을 찾을 수 없습니다: \(row.fixtureNumber)")
            }
            let range = [row.callStart, row.callEnd, row.classStart, row.classEnd]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            let other = row.other.trimmingCharacters(in: .whitespacesAndNewlines)
            let content: IndoorShelfLabel.Content
            if range.allSatisfy(\.isEmpty) {
                content = other.isEmpty ? .emptyShelf : .category(other)
            } else if range.allSatisfy({ !$0.isEmpty }), other.isEmpty {
                content = .callNumberRange(start: range[0], end: range[1])
            } else {
                throw ShelfLabelLoadError.invalidData("청구기호 범위 또는 기타 분류가 불완전합니다: \(row.fixtureNumber)")
            }
            return .init(fixtureNumber: row.fixtureNumber, realNumber: row.realNumber, side: row.side,
                         sequence: row.sequence, floorID: floors[0].id, mapElementID: fixture.id,
                         geometry: fixture.geometry, content: content)
        } + Self.namedShelfLabels(on: map)
    }

    static func namedShelfLabels(on map: IndoorMap, floorOrdinal: Int = 1,
                                 prefix: String = "S-2F-") -> [IndoorShelfLabel] {
        guard let floor = map.floors.first(where: { $0.ordinal == floorOrdinal }) else { return [] }
        let fixtures = map.features
            .filter { $0.kind == .fixture && $0.floorID == floor.id && $0.name?.hasPrefix(prefix) == true }
            .sorted { ($0.name ?? "") < ($1.name ?? "") }
        return fixtures.enumerated().compactMap { offset, fixture in
            guard let name = fixture.name else { return nil }
            let display = String(name.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
            guard !display.isEmpty else { return nil }
            return IndoorShelfLabel(
                fixtureNumber: name, realNumber: display, side: .a, sequence: offset,
                floorID: floor.id, mapElementID: fixture.id, geometry: fixture.geometry,
                content: .category(display))
        }
    }

    private struct Record: Decodable {
        let callStart: String
        let callEnd: String
        let classStart: String
        let classEnd: String
        let fixtureNumber: String
        let floor: String
        let other: String
        let realNumber: String
        let sequence: Int
        let side: IndoorShelfLabel.Side
    }
}

nonisolated enum ShelfLabelLoadError: Error, Equatable, Sendable, LocalizedError {
    case missingResource
    case invalidData(String)

    var errorDescription: String? {
        switch self {
        case .missingResource: "서가 표시 자료를 불러올 수 없어요."
        case .invalidData: "서가 표시 자료가 현재 지도와 맞지 않아요."
        }
    }
}
