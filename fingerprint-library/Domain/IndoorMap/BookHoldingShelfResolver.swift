import Foundation

nonisolated struct BookHoldingShelfResolution: Equatable, Identifiable, Sendable {
    enum Outcome: Equatable, Sendable {
        case unsupportedLocation
        case missingCallNumber
        case outsideIndex
        case candidates([IndoorShelfLabel])
    }
    var id: String { holding.id }
    let holding: BookHolding
    let outcome: Outcome
    var shelves: [IndoorShelfLabel] {
        guard case .candidates(let shelves) = outcome else { return [] }
        return shelves
    }
}

/// 확인한 일반 서고만 검색한다. 별치 구역·자료 유형으로 층이나 책장을 추측하지 않는다.
nonisolated struct BookHoldingShelfResolver {
    func resolve(_ holdings: [BookHolding], on map: IndoorMap,
                 labels: [IndoorShelfLabel]) -> [BookHoldingShelfResolution] {
        holdings.map { holding in
            guard holding.institutionCode == "82POSTECH_INST", holding.libraryCode == "MAIN",
                  let floor = ["c3b": 3, "c4b": 4][holding.locationCode ?? ""] else {
                return .init(holding: holding, outcome: .unsupportedLocation)
            }
            guard let call = holding.callNumber, !call.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return .init(holding: holding, outcome: .missingCallNumber)
            }
            let shelves = BookShelfRangeMatcher().candidates(
                for: .init(floorNumber: floor, callNumber: call), on: map, labels: labels
            )
            return .init(holding: holding, outcome: shelves.isEmpty ? .outsideIndex : .candidates(shelves))
        }
    }
}
