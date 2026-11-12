import Foundation

/// 현재 목적지 서가에 매칭된 소장본의 표시 정보. 다른 소장 위치의 청구기호를 섞지 않는다.
struct BookNavigationBookInfo: Equatable, Sendable {
    let book: Book
    let shelf: IndoorShelfLabel
    let candidateShelves: [IndoorShelfLabel]
    let floorName: String?
    let holdings: [BookHolding]
    let locationNames: [String]
    let callNumbers: [String]

    init?(routePlan: RoutePlan, stopIndex: Int) {
        guard routePlan.stops.indices.contains(stopIndex) else { return nil }
        let stop = routePlan.stops[stopIndex]
        book = stop.book
        shelf = stop.shelf
        candidateShelves = stop.candidateShelves
        floorName = routePlan.map.floors.first { $0.id == stop.shelf.floorID }?.name
        holdings = ShelfResolver().resolve(stop.holdings, on: routePlan.map, labels: routePlan.shelfLabels)
            .filter { $0.shelves.contains { $0.id == stop.shelf.id } }
            .map(\.holding)
        locationNames = Self.unique(holdings.compactMap(\.locationName))
        callNumbers = Self.unique(holdings.compactMap(\.callNumber))
    }

    private static func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }
}
