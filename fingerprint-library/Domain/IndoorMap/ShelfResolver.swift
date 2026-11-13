import Foundation

nonisolated struct ShelfResolution: Equatable, Identifiable, Sendable {
    enum Outcome: Equatable, Sendable {
        case unsupportedLocation
        case missingCallNumber
        case outsideIndex
        case candidates([IndoorShelfLabel])
    }
    enum Area: Equatable, Sendable {
        case generalStack
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

nonisolated extension Array where Element == ShelfResolution {
    var preferredForRoute: [ShelfResolution] {
        let hasGeneralStack = contains { $0.area == .generalStack && !$0.shelves.isEmpty }
        guard hasGeneralStack else { return self }
        return filter { $0.area != .displayShelf }
    }

    var preferredRouteShelves: [IndoorShelfLabel] {
        var seen = Set<String>()
        return preferredForRoute.flatMap(\.shelves).filter { seen.insert($0.id).inserted }
    }
}

nonisolated struct ShelfResolver {
    func resolve(_ holdings: [BookHolding], on map: IndoorMap,
                 labels: [IndoorShelfLabel]) -> [ShelfResolution] {
        holdings.map { resolve($0, on: map, labels: labels) }
    }

    private func resolve(_ holding: BookHolding, on map: IndoorMap,
                         labels: [IndoorShelfLabel]) -> ShelfResolution {
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

    private static let displayShelfFloorOrdinal = 1

    static func displayShelfName(in locationName: String?) -> String? {
        guard let text = locationName?.precomposedStringWithCanonicalMapping,
              let match = text.firstMatch(of: /삼각\s*서가\s*([A-Za-z])/) else { return nil }
        return "삼각서가 \(match.1.uppercased())"
    }
}
