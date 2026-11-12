import Foundation

nonisolated struct BookHoldingShelfResolution: Equatable, Identifiable, Sendable {
    enum Outcome: Equatable, Sendable {
        case unsupportedLocation
        case missingCallNumber
        case outsideIndex
        case candidates([IndoorShelfLabel])
    }
    /// 소장 위치가 속한 구역. 지원하지 않는 위치는 nil이다.
    enum Area: Equatable, Sendable {
        /// 3·4층 일반 서고. 청구기호 범위로 서가를 찾는다.
        case generalStack
        /// 2층 삼각서가 같은 별치 서가. 위치 이름으로 서가를 찾는다.
        case displayShelf
    }
    var id: String { holding.id }
    let holding: BookHolding
    let area: Area?
    let outcome: Outcome
    var shelves: [IndoorShelfLabel] {
        guard case .candidates(let shelves) = outcome else { return [] }
        return shelves
    }
}

extension Array where Element == BookHoldingShelfResolution {
    /// 길안내 목적지로 쓸 소장 위치.
    ///
    /// 3·4층 일반 서고에서 서가를 찾았으면 2층 별치 서가는 제외한다. 일반 서고 후보가 없을 때만 2층으로 안내한다.
    var preferredForRoute: [BookHoldingShelfResolution] {
        let hasGeneralStack = contains { $0.area == .generalStack && !$0.shelves.isEmpty }
        guard hasGeneralStack else { return self }
        return filter { $0.area != .displayShelf }
    }

    /// ``preferredForRoute``의 서가 후보. 같은 서가는 한 번만 담는다.
    var preferredRouteShelves: [IndoorShelfLabel] {
        var seen = Set<String>()
        return preferredForRoute.flatMap(\.shelves).filter { seen.insert($0.id).inserted }
    }
}

/// 확인한 일반 서고와 2층 삼각서가만 검색한다. 그 밖의 별치 구역·자료 유형으로 층이나 책장을 추측하지 않는다.
nonisolated struct BookHoldingShelfResolver {
    func resolve(_ holdings: [BookHolding], on map: IndoorMap,
                 labels: [IndoorShelfLabel]) -> [BookHoldingShelfResolution] {
        holdings.map { resolve($0, on: map, labels: labels) }
    }

    private func resolve(_ holding: BookHolding, on map: IndoorMap,
                         labels: [IndoorShelfLabel]) -> BookHoldingShelfResolution {
        guard holding.institutionCode == "82POSTECH_INST", holding.libraryCode == "MAIN" else {
            return .init(holding: holding, area: nil, outcome: .unsupportedLocation)
        }
        if let floor = ["c3b": 3, "c4b": 4][holding.locationCode ?? ""] {
            guard let call = holding.callNumber, !call.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return .init(holding: holding, area: .generalStack, outcome: .missingCallNumber)
            }
            let shelves = BookShelfRangeMatcher().candidates(
                for: .init(floorNumber: floor, callNumber: call), on: map, labels: labels
            )
            return .init(holding: holding, area: .generalStack,
                         outcome: shelves.isEmpty ? .outsideIndex : .candidates(shelves))
        }
        if let name = Self.displayShelfName(in: holding.locationName) {
            // 삼각서가는 청구기호 범위가 아니라 위치 이름으로 서가 하나를 가리킨다.
            let shelves = labels.filter { label in
                guard case .category(let category) = label.content else { return false }
                return category == name
                    && map.floors.first(where: { $0.id == label.floorID })?.ordinal == Self.displayShelfFloorOrdinal
            }
            return .init(holding: holding, area: .displayShelf,
                         outcome: shelves.isEmpty ? .outsideIndex : .candidates(shelves))
        }
        return .init(holding: holding, area: nil, outcome: .unsupportedLocation)
    }

    /// 2층(IMDF ordinal 1).
    private static let displayShelfFloorOrdinal = 1

    /// "삼각서가C3: 원북 원포항 선정도서 (2층)"처럼 서가 문자 뒤에 칸 번호가 붙은 위치 이름에서
    /// 도면 서가 이름("삼각서가 C")을 만든다. 칸 번호는 도면에 없어 버린다.
    static func displayShelfName(in locationName: String?) -> String? {
        guard let text = locationName?.precomposedStringWithCanonicalMapping,
              let match = text.firstMatch(of: /삼각\s*서가\s*([A-Za-z])/) else { return nil }
        return "삼각서가 \(match.1.uppercased())"
    }
}
