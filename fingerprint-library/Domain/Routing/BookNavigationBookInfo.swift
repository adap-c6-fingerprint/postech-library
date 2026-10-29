import Foundation

/// 현재 목적지 서가에 매칭된 소장본의 표시 정보. 다른 소장 위치의 청구기호를 섞지 않는다.
struct BookNavigationBookInfo: Equatable, Sendable {
    let book: Book
    let shelf: IndoorShelfLabel
    let floorName: String?
    let locationNames: [String]
    let callNumbers: [String]

    init?(session: BookNavigationSession, stopIndex: Int) {
        guard session.stops.indices.contains(stopIndex) else { return nil }
        let stop = session.stops[stopIndex]
        book = stop.book
        shelf = stop.shelf
        floorName = session.map.floors.first { $0.id == stop.shelf.floorID }?.name
        let holdings = BookHoldingShelfResolver().resolve(stop.holdings, on: session.map, labels: session.shelfLabels)
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
